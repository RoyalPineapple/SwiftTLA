import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct SyncTerminationDetectionCorpusExecutionTests {
    @Test("termination may detect quiescence using the updated active state")
    func terminateUsesUpdatedState() throws {
        let initial = try SyncTerminationDetectionModel.initialMachines(configuration: .init(N: 2))
        let source = try #require(initial.first {
            $0.state.active[0] == true && $0.state.active[1] == false
                && $0.state.terminationDetected == false
        })
        let graph = try ReachabilityGraph(initialMachines: initial, maximumStates: 100)
        let outcomes = try #require(graph.transitions[source.snapshot])
            .filter { $0.action == .Terminate(node: 0) }
        #expect(outcomes.count == 2)
        #expect(outcomes.allSatisfy {
            $0.target.state.active[0] == false && $0.target.state.active[1] == false
        })
        #expect(Set(outcomes.map { $0.target.state.terminationDetected }) == [false, true])
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("the published seven-node scenario checks the complete graph and all selected properties")
    func publishedScenario() throws {
        let scenario = try #require(SyncTerminationDetectionModel.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 1_000)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        let graph = try #require(run.native.graph).graph
        #expect(graph.initialStateKeys.count == 129)
        #expect(graph.states.count == 129)
        #expect(run.native.checks.properties == [
            "TypeOK": .satisfied,
            "TDCorrect": .satisfied,
            "Quiescence": .satisfied,
            "Liveness": .satisfied
        ])
        #expect(run.native.checks.deadlock == .satisfied)
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["TypeOK", "TDCorrect", "Quiescence", "Liveness"])
        #expect(rendered.tlaBundle.cfg.contains("N = 7"))
    }

    @Test("the annotation wrapper reuses the seven-node machine with its selected invariants")
    func annotationWrapperConfiguration() throws {
        let scenarios = try SyncTerminationDetectionModel.validationScenarios()
        let scenario = try #require(scenarios.first { $0.name == "APSyncTerminationDetection" })
        let run = try NativeScenarioRun(scenario, maximumStates: 1_000)
        try run.validateExpectations()
        #expect(run.coverage.selectedProperties == ["TDCorrect", "TypeOK"])
        #expect(run.coverage.omittedProperties == ["Liveness", "Quiescence"])
        #expect(try #require(run.native.graph).graph.states.count == 129)
        #expect(run.native.checks.properties == ["TypeOK": .satisfied, "TDCorrect": .satisfied])
        #expect(run.native.checks.deadlock == .satisfied)

        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["TypeOK", "TDCorrect"])
        let baseRendered = try scenarios[0].render()
        #expect(rendered.tlaBundle.tla == baseRendered.tlaBundle.tla)
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let reference = try #require(manifest.cases.first { $0.id == "sync-termination-detection-ap" })
        #expect(try reference.resolveScenario()?.name == scenario.name)
    }
}
