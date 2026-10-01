import Testing
import SwiftTLA
@testable import UpstreamParity

struct MixedStepCompositionTests {
    @Test("independent and algorithm steps share generated state without sharing control")
    func composesIndependentAndAlgorithmSteps() throws {
        let scenario = try #require(MixedStepComposition.validationScenarios().first)
        let initial = try #require(scenario.initialMachines().first)
        let advance = try #require(try initial.enabledActions().first)
        #expect(advance != .reset)
        let advanced = try #require(try initial.successors(for: advance).first)
        #expect(advanced.state.value == 1)
        let reset = try #require(try advanced.successors(for: .reset).first)
        #expect(reset.state.value == 0)
        #expect(reset.snapshot != initial.snapshot)
        let completed = try #require(try advanced.successors(for: advance).first)
        #expect(completed.state.value == 2)
        #expect(try reset.successors(for: advance).first?.snapshot == completed.snapshot)
        #expect(try completed.enabledActions().isEmpty)

        let graph = try scenario.explore(maximumStates: 10)
        #expect(graph.transitions.count == 4)
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 4)
        #expect(graph.deadlockedStates == [completed.snapshot])
        let rendered = try scenario.render()
        #expect(Set(rendered.actions.map(\.sourceName)).isSuperset(of: ["advance", "reset"]))
        let run = try NativeScenarioRun(scenario, maximumStates: 10)
        try run.validateExpectations()
    }
}
