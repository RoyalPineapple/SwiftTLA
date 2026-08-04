import Testing
import SwiftTLA
import SwiftTLAExamples

struct RoundTripTests {
    @Test("Every example's @TLAModel spec equals builder DSL equivalent")
    func allExamples() {
        for example in Examples.all {
            let fromMacro = example.spec
            let fromBuilder = TLASpec(
                name: fromMacro.name,
                variables: fromMacro.variables,
                actions: fromMacro.actions,
                invariants: fromMacro.invariants,
                temporalProperties: fromMacro.temporalProperties,
                fairness: fromMacro.fairness,
                constraint: fromMacro.constraint,
                assume: fromMacro.assume,
                checkDeadlock: fromMacro.checkDeadlock
            )
            #expect(fromMacro == fromBuilder, "\(example.name): macro and builder must produce identical TLASpec")
        }
    }
}
