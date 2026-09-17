import Foundation
import SwiftTLA
import Testing
@testable import UpstreamParity

struct CoffeeCanCorpusStateGraphTests {
    @Test("CoffeeCan preserves its typed record, every action edge, and all temporal claims")
    func completeDiagnosticGraph() throws {
        let configuration = try CoffeeCanModel.Configuration(MaxBeanCount: 5)
        let initial = try CoffeeCanModel.initialMachines(configuration: configuration)
        #expect(initial.count == 20)
        let graph = try ReachabilityGraph(initialMachines: initial, maximumStates: 100)
        #expect(graph.transitions.count == 20)
        #expect(graph.initialStates == Set(graph.transitions.keys))
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 32)
        #expect(graph.safetyViolations.isEmpty)
        #expect(Set(graph.temporalResults.keys) == [.MonotonicDecrease, .EventuallyTerminates, .LoopInvariant, .TerminationHypothesis])
        #expect(graph.temporalResults.values.allSatisfy { $0.status == .satisfied })
        for machine in initial {
            let checked = try #require(graph.transitions[machine.snapshot])
            let enabled = try machine.enabledActions()
            #expect(Set(enabled) == Set(checked.map(\.action)))
            for action in enabled {
                var next = machine
                let transition = try next.send(action)
                #expect(transition.before == machine.state)
                #expect(transition.after == next.state)
                #expect(checked.contains { $0.action == action && $0.target == next.snapshot })
                let before = machine.state.can
                let after = next.state.can
                #expect(before.white % 2 == after.white % 2)
                if action == .Termination {
                    #expect(before.black + before.white == 1)
                    #expect(before == after)
                } else {
                    #expect(after.black + after.white == before.black + before.white - 1)
                }
            }
        }
        let ap = try #require(CoffeeCanModel.validationScenarios().first { $0.name == "APCoffeeCan" })
        let run = try NativeScenarioRun(ap, maximumStates: 100)
        try run.validateExpectations()
        #expect(run.native.checks.properties == ["TypeInvariant": .satisfied])
        #expect(run.native.checks.deadlock == .satisfied)
    }

    @Test("CoffeeCan retains every published configuration and independent source pin")
    func allPublishedConfigurations() throws {
        let scenarios = try CoffeeCanModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["CoffeeCan100Beans", "CoffeeCan1000Beans", "CoffeeCan3000Beans", "APCoffeeCan"])
        #expect(scenarios.map { $0.configuration.MaxBeanCount } == [100, 1000, 3000, 5])
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let cases = manifest.cases.filter { $0.sourceModel == .coffeeCan }
        #expect(cases.count == 4)
        var modules: Set<String> = []
        for scenario in scenarios {
            let rendered = try scenario.render()
            modules.insert(rendered.tlaBundle.tla)
            #expect(rendered.checksDeadlock)
            #expect(rendered.tlaBundle.cfg.contains("CONSTANT MaxBeanCount = \(scenario.configuration.MaxBeanCount)"))
            #expect(rendered.checkNames == (scenario.name == "APCoffeeCan"
                ? ["TypeInvariant"]
                : ["TypeInvariant", "MonotonicDecrease", "EventuallyTerminates", "LoopInvariant", "TerminationHypothesis"]))
            let reference = try #require(cases.first { $0.scenario == scenario.name })
            #expect(try reference.resolveScenario()?.name == scenario.name)
            let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + reference.module))
            let configuration = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + reference.configuration))
            #expect(SHA256.hex(module) == reference.moduleSHA256)
            #expect(SHA256.hex(configuration) == reference.cfgSHA256)
            let count = scenario.configuration.MaxBeanCount
            #expect(reference.exploration.maximumStateLimit >= count * (count + 3) / 2)
        }
        #expect(modules.count == 1)
    }
}
