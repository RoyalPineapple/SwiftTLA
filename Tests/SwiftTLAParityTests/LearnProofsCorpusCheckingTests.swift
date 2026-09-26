import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct LearnProofsCorpusCheckingTests {
    @Test("MCFindHighest uses the pinned reference and the registered model-owned scenario")
    func resolvesConfiguredReference() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let reference = try #require(manifest.cases.first { $0.id == "find-highest" })
        #expect(reference.comparisonMode == .exhaustive)
        let scenario = try #require(try reference.resolveScenario())
        #expect(scenario.name == "MCFindHighest")
        #expect(try modelValidationScenarios().contains { $0.id == "find-highest-0" && $0.scenario.name == scenario.name })
        let root = projectURL("Verification/FiniteGraph/fixtures")
        for (path, hash) in [
            (reference.module, reference.moduleSHA256),
            (reference.configuration, reference.cfgSHA256),
            ("learn-proofs/FindHighest.tla", "2236ae6e1547246c7539c96368ed8b2707243e2c215cbc48b981bc6896eee1bc"),
            ("boulanger/TLAPS.tla", "9afe54984062748a0568966434cc0945d682f8cd89fdbc38f73b5579751b0c55")
        ] {
            #expect(SHA256.hex(try Data(contentsOf: root.appendingPathComponent(path))) == hash)
        }
        let run = try NativeScenarioRun(scenario, maximumStates: reference.exploration.maximumStateLimit)
        try run.validateExpectations()
        #expect(try #require(run.native.graph).isComparable)
        #expect(run.native.rendered.checksDeadlock)
        #expect(run.native.rendered.checkNames == ["TypeOK", "InductiveInvariant", "DoneIndexValue", "Correctness"])
    }

    @Test("AddTwo preserves the unbounded upstream transition without control state")
    func preservesAddTwo() throws {
        var machine = try AddTwoModel.makeMachine()
        #expect(machine.state.x == 0)
        for step in 1...100 {
            let successors = try machine.successors()
            #expect(successors.count == 1)
            let next = try #require(successors.first)
            #expect(next.action == .Next)
            #expect(next.machine.state.x == step * 2)
            _ = try machine.send(.Next)
            #expect(machine.state == next.machine.state)
        }
        let rendered = try AddTwoModel.render()
        #expect(!rendered.tlaBundle.cfg.contains("CONSTRAINT"))
        #expect(!rendered.tlaBundle.tla.contains("pc"))
        #expect(rendered.checkNames == ["TypeOK", "Even"])
    }

    @Test("MCFindHighest separates its substituted sequence domain from the state constraint")
    func preservesConfiguredDomain() throws {
        let scenario = try #require(FindHighestModel.validationScenarios().first)
        let initial = try scenario.initialMachines()
        #expect(initial.count == 781)
        #expect(initial.contains { $0.state.f.count == 4 })
        let graph = try scenario.explore(maximumStates: 10_000)
        #expect(graph.initialStates.count == 156)
        #expect(graph.transitions.count == 742)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.transitions.keys.allSatisfy { $0.state.f.count <= 3 })
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["TypeOK", "InductiveInvariant", "DoneIndexValue", "Correctness"])
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.cfg.contains("CONSTRAINT"))
    }
}
