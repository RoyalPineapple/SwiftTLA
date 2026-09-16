import Testing
import UpstreamParity
@testable import SwiftTLA

struct ConstantStateClaimsTests {
    @Test("constant claims retain their outcomes and initial-state witnesses")
    func preservesConstantPredicates() throws {
        for scenario in try ConstantStateClaims.validationScenarios() {
            let run = try NativeScenarioRun(scenario, maximumStates: 4)
            try run.validateExpectations()
            let graph = try scenario.explore(maximumStates: 4)
            guard case .reached(let witness) = graph.reachabilityResults[.initialWitness] else {
                Issue.record("Expected a constant true reachability witness")
                continue
            }
            #expect(try graph.trace(to: witness).count == 1)
            #expect(graph.reachabilityResults[.absentWitness] == .unreachable)
            let rendered = try scenario.render()
            for predicate in ["trueInvariant == (TRUE)", "falseInvariant == (FALSE)",
                              "initialWitness == (~(TRUE))", "absentWitness == (~(FALSE))",
                              "configuredWitness == (~(enabled))"] {
                #expect(rendered.tlaBundle.tla.contains(predicate + " /\\ (pc = pc)"))
                #expect(try rendered.plusCalBundle().root.tla.contains(predicate + " /\\ (pc = pc)"))
            }
        }
    }
}
