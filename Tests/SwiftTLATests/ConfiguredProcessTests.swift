import Testing
@testable import SwiftTLA

struct ConfiguredProcessTests {
    @Test("configured populations share generated types, transitions, and symbolic export")
    func variesPopulation() throws {
        let scenarios = try ConfiguredProcessMachine.validationScenarios()
        #expect(scenarios.count == 3)
        let modules = try scenarios.map { try $0.render().tlaBundle.tla }
        #expect(Set(modules).count == 1)
        for scenario in scenarios {
            let population = scenario.configuration.nodes
            var machine = try #require(scenario.initialMachines().first)
            let actions = try machine.enabledActions()
            for action in actions {
                _ = try machine.send(action)
            }
            #expect(machine.state.selected == population)
            let graph = try scenario.explore(maximumStates: 20)
            #expect(graph.transitions.count == 1 << population.count)
            #expect(graph.deadlockedStates.isEmpty)
            guard case .reached = graph.reachabilityResults["Complete"] else {
                Issue.record("Missing completed-population witness")
                continue
            }
            let rendered = try scenario.render()
            let visits = rendered.actions.filter { $0.sourceName == "visit" }
            #expect(Set(visits.map(\.arguments)) == Set(population.map { [TLAValue.int($0)] }))
        }
    }
}
