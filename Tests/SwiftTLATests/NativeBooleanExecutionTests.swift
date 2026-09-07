import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct ConditionalPredicateFailures {
    static var spec: TLASpec {
        TLASpec("ConditionalPredicateFailures") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("skipAnd") {
                value != 0 && Expr<Int>(1) / 0 == 0
                value.stays
            }
            SwiftTLA.Action("skipOr") {
                value == 0 || Expr<Int>(1) / 0 == 0
                value.stays
            }
            SwiftTLA.Action("evaluateAnd") {
                value == 0 && Expr<Int>(1) / 0 == 0
                value.stays
            }
            SwiftTLA.Action("actionOr") {
                value.stays.when(value == 0) || value.stays.when(Expr<Int>(1) / 0 == 0)
            }
            SwiftTLA.Action("evaluateOr") {
                value != 0 || Expr<Int>(1) / 0 == 0
                value.stays
            }
        }
    }
}

@Suite struct NativeBooleanExecutionTests {
    @Test("Short-circuit predicates agree with formal enabledness and errors")
    func conditionalRightOperand() throws {
        let compilation = try ConditionalPredicateFailures.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let machine = try ConditionalPredicateFailures.makeMachine()
        let cases: [(String, ConditionalPredicateFailures.Action, Bool?)] = [
            ("skipAnd", .skipAnd, false), ("skipOr", .skipOr, true),
            ("evaluateAnd", .evaluateAnd, nil), ("evaluateOr", .evaluateOr, nil),
            ("actionOr", .actionOr, nil)
        ]
        for (name, action, enabled) in cases {
            let id = try #require(compilation.layout.testActionID(named: name))
            if let enabled {
                #expect(try machine.isEnabled(action) == enabled)
                #expect(try !runtime.successors(for: id, from: initial).isEmpty == enabled)
            } else {
                #expect(throws: EvalError.divisionByZero) {
                    try runtime.successors(for: id, from: initial)
                }
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.isEnabled(action)
                }
            }
        }
    }
}
