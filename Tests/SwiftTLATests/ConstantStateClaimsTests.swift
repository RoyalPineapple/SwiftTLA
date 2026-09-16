import Testing
import UpstreamParity
@testable import SwiftTLA

struct ConstantStateClaimsTests {
    @Test("constant operators retain witnesses when their state arguments are unused")
    func preservesIgnoredStateArguments() throws {
        let predicates = TLASpec("ConstantPredicates") {
            DefineRecursive("Never", params: ["ignored"]) { StateExpr.value(.bool(false)) }
        }
        let value = Var<Int>("value")
        let target = Instance("Predicates", of: predicates)
        let source = TLASpec("IgnoredStateArgument") {
            Variable(value, 0)
            Action("stay") { value.stays }
            target
            Invariant("NeverHolds") { target.call("Never", value.stateExpr) }
        }
        let rendered = try source.compile().render().tlaBundle.tla
        #expect(rendered.contains("NeverHolds == (Predicates!Never(value)) /\\ (value = value)"))
    }

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
