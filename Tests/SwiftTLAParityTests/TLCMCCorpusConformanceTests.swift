import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct TLCMCCorpusConformanceTests {
    @Test("TLCMC Graph 1 has one canonical compiled specification")
    func hasOneCanonicalCompiledSpecification() throws {
        let entry = try #require(CanonicalCorpus.entries.first { $0.id == "tlcmc-graph-1" })
        let compilation = try entry.specification().compile()
        let resolved = try TLCMCModel.spec.compile()
        let bundle = try compilation.render().tlaBundle

        #expect(compilation.identity == resolved.identity)
        #expect(compilation.description.actions.map(\.name).contains("returnToDequeue") == false)
        #expect(compilation.description.controlLocations.map(\.sourceName).contains("returnToDequeue") == false)
        #expect(bundle.root.tla.contains("SelectSeq"))

        let manifestData = try Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json"))
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self, from: manifestData)
        let declaredCase = try #require(manifest.cases.first { $0.id == entry.id })
        let sourceInput = try #require(declaredCase.sourceInput)
        #expect(sourceInput.path == "tlaplus/Examples@ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/TLC/TLCMC.tla")
        #expect(sourceInput.sha256 == "5d553b7066376e909a093c6f5c0f881d5d37c4907a19f5d5738a465ec2ab4294")

        let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/tlcmc-graph-1/TLCMC.tla"))
        let configuration = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/tlcmc-graph-1/TLCMC.cfg"))
        let renderedModule = Data(bundle.root.tla.utf8)
        #expect(module == renderedModule)
        #expect(configuration == Data(entry.swiftConfiguration.tlaText.utf8))
        #expect(bundle.imports.map(\.name) == declaredCase.imports)
        #expect(declaredCase.dependencies.isEmpty)
        #expect(SHA256.hex(module) == declaredCase.moduleSHA256)
        #expect(SHA256.hex(configuration) == declaredCase.cfgSHA256)
    }

    @Test("TLCMC native execution covers the complete formal graph used by TLC")
    func nativeExecutionMatchesFormalGraph() throws {
        let compilation = try TLCMCModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initialStates = try runtime.initialStates()
        #expect(initialStates.count == 2)
        #expect(throws: GeneratedMachineError.ambiguousInitialState) { try TLCMCModel.makeMachine() }
        let frontiers: [[TLCMCModel.Node]] = [[.one, .two], [.two, .one]]
        var pending: [(CompiledState, TLCMCModel)] = try frontiers.map { frontier in
            let machine = try TLCMCModel.makeMachine(.init(
                frontier: frontier, closed: [], currentState: .member_null_4,
                successors: [], initialIndex: 1, counterexample: [], predecessorEdges: [], levels: [:]
            ))
            let projection = try formalProjection(of: machine.state)
            let state = try #require(initialStates.first { try matches(projection, $0, compilation: compilation) })
            return (state, machine)
        }
        #expect(Set(pending.map(\.0)) == Set(initialStates))
        let allActions: [TLCMCModel.Action] = [.scanInitialStates, .checkInitialStates, .dequeue, .exploreSuccessors, .trace]
        var visited = Set<CompiledState>()
        while let (state, machine) = pending.popLast() {
            guard visited.insert(state).inserted else { continue }
            let successors = try runtime.successors(from: state)
            let enabled = try machine.enabledActions()
            let names = Dictionary(uniqueKeysWithValues: compilation.layout.actions.map { ($0.id, $0.declaration.name) })
            let transitions = successors.filter { names[$0.action] != "Terminating" }
            #expect(Set(enabled.map { String(describing: $0) }) == Set(transitions.compactMap { names[$0.action] }))
            let violations = try compilation.semantics.behavior.invariants.filter { try !runtime.invariantHolds($0, in: state) }.map(\.name)
            #expect(try machine.violatedInvariants() == violations)
            for successor in successors where names[successor.action] == "Terminating" {
                #expect(successor.state == state)
                #expect(enabled.isEmpty)
            }
            for action in allActions {
                var next = machine
                if !enabled.contains(action) {
                    #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try next.send(action) }
                    #expect(next.state == machine.state)
                    #expect(try next.enabledActions() == enabled)
                    continue
                }
                let expected = transitions.filter { names[$0.action] == String(describing: action) }
                // This bounded graph has two initial states but deterministic actions.
                #expect(expected.count == 1)
                let successor = try #require(expected.first)
                let transition = try next.send(action)
                #expect(transition.before == machine.state)
                #expect(transition.after == next.state)
                #expect(try matches(formalProjection(of: next.state), successor.state, compilation: compilation))
                pending.append((successor.state, next))
            }
        }
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)
        ).explore()
        guard case .ok = exploration.outcome else {
            Issue.record("The shared TLC scenario must finish its finite exploration.")
            return
        }
        #expect(visited.count == exploration.graph.states.count)
    }

    private func matches(_ native: TLAStateProjection, _ state: CompiledState, compilation: CompiledSpecification) throws -> Bool {
        let formal = try state.projection(using: compilation.layout)
        return native.entries.allSatisfy { formal.value(for: $0.token) == $0.value }
    }

    private func formalProjection(of state: TLCMCModel.State) throws -> TLAStateProjection {
        let current: TLAValue = switch state.currentState {
        case .member_1_0: .int(1)
        case .member_2_1: .int(2)
        case .member_3_2: .int(3)
        case .member_4_3: .int(4)
        case .member_null_4: .string("null")
        }
        let fields: [(String, TLAValue)] = [
            ("frontier", .tuple(state.frontier.map(\.tlaValue))),
            ("closed", .set(Set(state.closed.map(\.tlaValue)))),
            ("currentState", current),
            ("successors", .set(Set(state.successors.map(\.tlaValue)))),
            ("initialIndex", .int(state.initialIndex)),
            ("counterexample", .tuple(state.counterexample.map(\.tlaValue))),
            ("predecessorEdges", .tuple(state.predecessorEdges.map { .tuple([$0.first.tlaValue, $0.second.tlaValue]) })),
            ("levels", .function(Dictionary(uniqueKeysWithValues: state.levels.map { ($0.key.tlaValue, .int($0.value)) })))
        ]
        return try TLAStateProjection(validating: fields.map { name, value in
            .init(token: try #require(TLAStateProjection.Token(validating: name)), value: value)
        })
    }

    @Test("TLCMC Graph 1 explores the violation path before termination")
    func exploresViolationPathBeforeTermination() throws {
        let compilation = try TLCMCModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)
        ).explore()
        guard case .ok = exploration.outcome else {
            Issue.record("TLCMC Graph 1 must finish its finite exploration.")
            return
        }

        let counterexample = try #require(TLAStateProjection.Token(validating: "counterexample"))
        let programCounter = try #require(TLAStateProjection.Token(validating: "pc"))
        let expectedPath: TLAValue = .tuple([.int(2), .int(3), .int(4)])
        #expect(exploration.graph.states.values.contains {
            $0.value(for: counterexample) == expectedPath && $0.value(for: programCounter) == .string("Done")
        })
    }
}
