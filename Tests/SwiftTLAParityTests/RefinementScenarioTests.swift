import Testing
@testable import SwiftTLA
import UpstreamParity

struct RefinementScenarioTests {
    @Test("refinement scenarios preserve all checks and retain expected failure traces")
    func checksRefinementScenarios() throws {
        let scenarios = try RefinementScenarioCounter.validationScenarios()
        #expect(RefinementScenarioCounter.formalPropertyNames[.UnitSteps] == "UnitSteps")
        #expect(RefinementScenarioCounter.propertyDisplayNames[.UnitSteps] == "Unit-step behavior")
        #expect(scenarios.count == 2)
        for scenario in scenarios {
            #expect(scenario.checking.properties == Set(RefinementScenarioCounter.Property.allCases))
            #expect(scenario.checking.checkDeadlock)
            #expect(scenario.expectations[.bounded] == .satisfied)
            #expect(scenario.deadlockExpectation == .violated)
            let graph = try scenario.explore(maximumStates: 4)
            let rendered = try scenario.render()
            let run = try NativeModelRun(graph, rendered: rendered)
            #expect(rendered.refinementNames == ["UnitSteps"])
            #expect(rendered.invariantNames == ["bounded"])
            #expect(run.checks.properties["bounded"] == .satisfied)
            if scenario.name == "Unit steps" {
                #expect(scenario.expectations[.UnitSteps] == .satisfied)
                #expect(graph.refinementFailures.isEmpty)
                #expect(run.checks.properties["UnitSteps"] == .satisfied)
            } else {
                #expect(scenario.expectations[.UnitSteps] == .violated)
                #expect(graph.refinementFailures[.UnitSteps] != nil)
                guard case .violated(let trace) = run.checks.properties["UnitSteps"] else {
                    Issue.record("Expected the skipped abstract step to retain a counterexample")
                    continue
                }
                try trace.validate(in: run.graph.graph)
                #expect(trace.steps.count == 2)
            }
        }
    }
}
