import Foundation
import SwiftTLA
import Testing
@testable import UpstreamParity

struct QueensCorpusStateGraphTests {
    @Test("direct Queens preserves its complete graph without PlusCal control or termination steps")
    func completeConfiguredGraph() throws {
        let scenario = try #require(QueensModel.validationScenarios().first)
        let initial = try scenario.initialMachines()
        #expect(initial.count == 1)
        #expect(initial[0].state.todo == [[]])
        #expect(initial[0].state.sols.isEmpty)
        let graph = try scenario.explore(maximumStates: 5_000)
        #expect(graph.transitions.count == 785)
        #expect(graph.temporalResults.isEmpty)
        let terminal = try #require(graph.transitions.keys.first { $0.state.todo.isEmpty })
        #expect(graph.transitions.keys.filter { $0.state.todo.isEmpty }.count == 1)
        #expect(terminal.state.sols == [[2, 4, 1, 3], [3, 1, 4, 2]])
        #expect(graph.transitions[terminal]?.isEmpty == true)
        #expect(!graph.safetyViolations.isEmpty)
        for (snapshot, violations) in graph.safetyViolations {
            #expect(violations == [.invariant(.NoSolutions)])
            #expect(!snapshot.state.sols.isEmpty)
        }

        struct Edge: Hashable {
            let source: QueensModel.Snapshot
            let action: QueensModel.Action
            let target: QueensModel.Snapshot
        }
        let checkedEdges = Set(graph.transitions.flatMap { source, transitions in
            transitions.map { Edge(source: source, action: $0.action, target: $0.target) }
        })
        var pending = initial
        var states: Set<QueensModel.Snapshot> = []
        var edges: Set<Edge> = []
        while let machine = pending.popLast() {
            guard states.insert(machine.snapshot).inserted else { continue }
            try #require(states.count <= 785)
            let successors = try machine.successors(for: .PlaceQueen)
            var sent = machine
            if successors.isEmpty {
                #expect(machine.state.todo.isEmpty)
                #expect(try machine.enabledActions().isEmpty)
                #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try sent.send(.PlaceQueen) }
                #expect(sent.snapshot == machine.snapshot)
            } else if successors.count == 1 {
                let transition = try sent.send(.PlaceQueen)
                #expect(transition.before == machine.state)
                #expect(transition.after == successors[0].state)
                #expect(sent.snapshot == successors[0].snapshot)
            } else {
                #expect(throws: GeneratedMachineError.ambiguousAction) { try sent.send(.PlaceQueen) }
                #expect(sent.snapshot == machine.snapshot)
            }
            edges.formUnion(successors.map { Edge(source: machine.snapshot, action: .PlaceQueen, target: $0.snapshot) })
            pending.append(contentsOf: successors)
        }
        #expect(states == Set(graph.transitions.keys))
        #expect(edges == checkedEdges)

        let run = try NativeScenarioRun(scenario, maximumStates: 5_000)
        try run.validateExpectations()
        #expect(run.native.checks.deadlock == nil)
        #expect(run.native.graph == nil)
        #expect(run.native.checks.properties["TypeInvariant"] == .unavailable)
        #expect(run.native.checks.properties["Invariant"] == .unavailable)
        guard case .violated(let trace) = run.native.checks.properties["NoSolutions"] else {
            Issue.record("Expected the upstream NoSolutions counterexample")
            return
        }
        let rendered = try scenario.render()
        let exhaustive = try NativeModelRun(graph, rendered: rendered)
        try trace.validate(in: exhaustive.graph.graph)
        #expect(exhaustive.checks.properties["TypeInvariant"] == .satisfied)
        #expect(exhaustive.checks.properties["Invariant"] == .satisfied)
        #expect(rendered.checkNames == ["TypeInvariant", "Invariant", "NoSolutions"])
        #expect(!rendered.checksDeadlock)
        #expect(rendered.tlaBundle.tla.contains("WF_<<todo, sols>>(Next)"))
        #expect(!rendered.tlaBundle.tla.contains("Terminating =="))
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT N = 4"))
    }

    @Test("direct Queens resolves its model-owned scenario against independent pinned upstream inputs")
    func pinsIndependentReference() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.sourceModel == .queensFour })
        #expect(try declaration.resolveScenario()?.name == "FourQueens")
        let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.module))
        let configuration = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.configuration))
        #expect(SHA256.hex(module) == declaration.moduleSHA256)
        #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
        let original = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/queens-four/Queens.tla"))
        #expect(SHA256.hex(original) == "ce6c6787ab7e7733c62870f815c2f21460dc9d60747a30689fdc61c891e563bf")
    }
}
