import Testing
import SwiftTLA
@testable import UpstreamParity

struct AsyncTerminationDetectionCorpusExecutionTests {
    @Test("the published four-node configuration retains all initial states and selected checks")
    func publishedConfiguration() throws {
        let scenario = try #require(EWD998TerminationModel.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 50_000)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        let graph = try #require(run.native.graph).graph
        #expect(graph.initialStateKeys.count == 17)
        #expect(graph.states.count == 4_097)
        #expect(run.native.checks.properties == [
            "TypeOK": .satisfied,
            "Safe": .satisfied,
            "Quiescence": .satisfied,
            "Live": .satisfied
        ])
        #expect(run.native.checks.deadlock == .satisfied)

        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["TypeOK", "Safe", "Quiescence", "Live"])
        #expect(rendered.tlaBundle.cfg.contains("N = 4"))
        #expect(rendered.tlaBundle.cfg.contains("CONSTRAINT StateConstraint"))
    }

    @Test("termination uses its updated activity to choose whether detection occurs")
    func terminateUsesUpdatedState() throws {
        let initial = try EWD998TerminationModel.initialMachines(configuration: .init(N: 4))
        let source = try #require(initial.first {
            $0.state.active[0] == true && $0.state.active[1] == false
                && $0.state.active[2] == false && $0.state.active[3] == false
                && $0.state.terminationDetected == false
        })
        let outcomes = try source.successors().filter { $0.action == .Terminate(node: 0) }
        #expect(outcomes.count == 2)
        #expect(outcomes.allSatisfy { $0.machine.state.active[0] == false })
        #expect(Set(outcomes.map { $0.machine.state.terminationDetected }) == [false, true])
    }
}
