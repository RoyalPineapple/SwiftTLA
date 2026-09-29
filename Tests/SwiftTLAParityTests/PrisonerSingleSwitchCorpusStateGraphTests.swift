import Testing
import SwiftTLA
@testable import UpstreamParity

struct PrisonerSingleSwitchCorpusStateGraphTests {
    @Test("solo configurations retain the empty signalling function and every selected check", arguments: [false, true])
    func solo(lightUnknown: Bool) throws {
        let scenarios = try PrisonerSingleSwitchModel.validationScenarios()
        let scenario = scenarios[lightUnknown ? 3 : 2]
        let initial = try scenario.initialMachines()
        let signalled = try #require(TLAStateProjection.Token(validating: "signalled"))
        #expect(initial.count == (lightUnknown ? 2 : 1))
        for machine in initial {
            #expect(try machine.formalProjection(of: machine.snapshot).value(for: signalled) == .function([:]))
        }
        try check(scenario, initialCount: lightUnknown ? 2 : 1,
            states: lightUnknown ? 4 : 2, edges: lightUnknown ? 4 : 2)
    }

    @Test("three-prisoner configurations preserve complete graphs and every selected check", arguments: [false, true])
    func threePrisoners(lightUnknown: Bool) throws {
        let scenario = try PrisonerSingleSwitchModel.validationScenarios()[lightUnknown ? 1 : 0]
        try check(scenario, initialCount: lightUnknown ? 2 : 1,
            states: lightUnknown ? 62 : 16, edges: lightUnknown ? 186 : 48)
    }

    private func check(_ scenario: PrisonerSingleSwitchModel.ValidationScenario,
        initialCount: Int, states: Int, edges: Int) throws {
        let run = try NativeScenarioRun(scenario, maximumStates: 1_000)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        let graph = try #require(run.native.graph).graph
        #expect(graph.initialStateKeys.count == initialCount)
        #expect(graph.states.count == states)
        #expect(graph.edges.count == edges)
        #expect(run.native.checks.properties == [
            "TypeOK": .satisfied,
            "VictoryOK": .satisfied,
            "Terminating": .satisfied
        ])
        #expect(run.native.checks.deadlock == .satisfied)
    }
}
