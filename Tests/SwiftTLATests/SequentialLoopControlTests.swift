import Testing
import UpstreamParity
@testable import SwiftTLA

struct SequentialLoopControlTests {
    @Test("HourClock preserves all twelve initial states and labeled transitions without control state")
    func preservesHourClockGraph() throws {
        let scenario = try #require(try HourClockModel.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 12)
        #expect(graph.initialStates.count == 12)
        #expect(graph.transitions.count == 12)
        #expect(graph.transitions.values.flatMap { $0 }.count == 12)
        #expect(graph.deadlockedStates.isEmpty)
        for (source, successors) in graph.transitions {
            let successor = try #require(successors.first)
            #expect(successor.target.state.hr == (source.state.hr == 12 ? 1 : source.state.hr + 1))
            #expect(successor.action == .HCnxt)
        }
        let run = try NativeScenarioRun(scenario, maximumStates: 12)
        try run.validateExpectations()
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.tla.contains("VARIABLES hr\n"))
        #expect(!rendered.tlaBundle.tla.contains("Terminating =="))
        #expect(try rendered.plusCalBundle().root.cfg == rendered.tlaBundle.root.cfg)
    }

    @Test("a blocked endless loop remains a deadlock without synthetic termination")
    func preservesDeadlock() throws {
        let graph = try ReachabilityGraph(initialMachines: GuardedEndlessLoop.initialMachines(), maximumStates: 4)
        #expect(graph.transitions.count == 2)
        #expect(graph.deadlockedStates.map { $0.state.value } == [1])
        #expect(try GuardedEndlessLoop.render().tlaBundle.tla.contains("VARIABLES value\n"))
    }

    @Test("a conditional loop retains control state and normal completion")
    func preservesCompletion() throws {
        let graph = try ReachabilityGraph(initialMachines: FinishingLoop.initialMachines(), maximumStates: 4)
        #expect(graph.transitions.count == 3)
        #expect(graph.deadlockedStates.isEmpty)
        #expect(try FinishingLoop.render().tlaBundle.tla.contains("VARIABLES pc, value\n"))
    }
}
