import Testing
import UpstreamParity
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
            #expect(graph.temporalResults["AllVisited"]?.status == (population.isEmpty ? .satisfied : .violated))
            guard case .reached = graph.reachabilityResults["Complete"] else {
                Issue.record("Missing completed-population witness")
                continue
            }
            let rendered = try scenario.render()
            let visits = rendered.actions.filter { $0.sourceName == "visit" }
            #expect(Set(visits.map(\.arguments)) == Set(population.map { [TLAValue.int($0)] }))
        }
    }

    @Test("weak fairness applies to every configured instance, not the action family")
    func weakFairness() throws {
        for scenario in try WeaklyFairConfiguredProcessMachine.validationScenarios() {
            try checkFairness(try #require(scenario.initialMachines().first),
                population: scenario.configuration.nodes.count, strong: false)
            let tla = try scenario.render().tlaBundle.tla
            #expect(tla.contains("\\A"))
            #expect(tla.contains("(\\A _process \\in nodes: WF_<<selected, pc>>(visit(_process)))"))
        }
    }

    @Test("strong fairness applies to every configured instance, including empty populations")
    func strongFairness() throws {
        for scenario in try StronglyFairConfiguredProcessMachine.validationScenarios() {
            try checkFairness(try #require(scenario.initialMachines().first),
                population: scenario.configuration.nodes.count, strong: true)
            #expect(try scenario.render().tlaBundle.tla.contains("(\\A _process \\in nodes: SF_<<selected, pc>>(visit(_process)))"))
        }
    }

    private func checkFairness<M: StateMachine>(_ machine: M, population: Int, strong: Bool) throws {
        let fairness = try machine.fairnessConditions()
        #expect(fairness.count == population)
        #expect(fairness.allSatisfy { $0.isStrong == strong })
        let actions = try machine.successors().map(\.action)
        for obligation in fairness {
            #expect(actions.filter(obligation.matches).count == 1)
        }
        let graph = try ReachabilityGraph(initialMachines: [machine], maximumStates: 20)
        #expect(graph.deadlockedStates.isEmpty)
        #expect(graph.temporalResults["AllVisited"]?.status == .satisfied)
        #expect(graph.transitions.count == 1 << population)
    }
}
