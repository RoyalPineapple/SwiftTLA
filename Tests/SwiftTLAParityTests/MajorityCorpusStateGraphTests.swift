import Foundation
import SwiftTLA
import Testing
@testable import UpstreamParity

struct MajorityCorpusStateGraphTests {
    @Test("Majority preserves all bounded initial choices, transitions, and invariants")
    func completeBoundedGraph() throws {
        let scenario = try #require(MajorityModel.validationScenarios().first)
        let initial = try scenario.initialMachines()
        #expect(initial.count == 1092)
        let native = try scenario.explore(maximumStates: 10_000)
        #expect(native.transitions.count == 2733)
        let terminalStates = Set(native.transitions.keys.filter { $0.state.i > $0.state.seq.count })
        #expect(!terminalStates.isEmpty)
        #expect(native.safetyViolations.isEmpty)
        #expect(terminalStates.allSatisfy { native.transitions[$0]?.isEmpty == true })
        let run = try NativeScenarioRun(scenario, maximumStates: 10_000)
        try run.validateExpectations()
        #expect(run.native.checks.properties == ["TypeOK": .satisfied, "Correct": .satisfied, "Inv": .satisfied])
        #expect(run.native.checks.deadlock == nil)
        let rendered = try scenario.render()
        #expect(!rendered.checksDeadlock)
        #expect(rendered.tlaBundle.tla.contains("WF_<<seq, i, cand, cnt>>(Next)"))
        #expect(!rendered.tlaBundle.tla.contains("Terminating =="))
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT bound = 5"))
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT Value = {A, B, C}"))

        struct Edge: Hashable {
            let source: MajorityModel.Snapshot
            let action: MajorityModel.Action
            let target: MajorityModel.Snapshot
        }
        let checkedEdges = Set(native.transitions.flatMap { source, transitions in
            transitions.map { Edge(source: source, action: $0.action, target: $0.target) }
        })
        var pending = initial
        var states: Set<MajorityModel.Snapshot> = []
        var edges: Set<Edge> = []
        while let machine = pending.popLast() {
            guard states.insert(machine.snapshot).inserted else { continue }
            try #require(states.count <= 2733)
            var next = machine
            if terminalStates.contains(machine.snapshot) {
                #expect(try machine.enabledActions().isEmpty)
                #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try next.send(.Next) }
                #expect(next.snapshot == machine.snapshot)
            } else {
                #expect(try machine.enabledActions() == [.Next])
                let transition = try next.send(.Next)
                #expect(transition.before == machine.state)
                #expect(transition.after == next.state)
                edges.insert(Edge(source: machine.snapshot, action: .Next, target: next.snapshot))
                pending.append(next)
            }
        }
        #expect(states == Set(native.transitions.keys))
        #expect(edges == checkedEdges)
    }

    @Test("Majority resolves its model-owned scenario against the pinned upstream modules and configuration")
    func pinsIndependentReference() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.sourceModel == .majority })
        #expect(try declaration.resolveScenario()?.name == "MCMajority")
        let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.module))
        let configuration = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.configuration))
        #expect(SHA256.hex(module) == declaration.moduleSHA256)
        #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
        let original = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/majority/Majority.tla"))
        #expect(SHA256.hex(original) == "09651709752cc32e4b9d9546a90170cff6f186da9d6b8d39e63dd991e2c86033")
    }
}
