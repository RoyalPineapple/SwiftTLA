import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// Formal fixtures isolate expression scheduling from Algorithm control flow.
@TLAModel
private struct ExpressionEvaluationOrder {
    static var spec: TLASpec {
        TLASpec("ExpressionEvaluationOrder") {
            let result = Var<Int>("result")
            Variable(result, 0)
            SwiftTLA.Action("mapped") {
                result.becomes(Expr<Int>(StateExpr.if(
                    SetExpr<Int>.literal(1, 2).mapping { member in member.expr + 1 }
                        == SetExpr<Int>.literal(2, 3),
                    then: 1, else: 0
                )))
            }
            SwiftTLA.Action("division") {
                result.becomes((Expr<Int>(1) / 0) / Expr<Int>(StateExpr.negate(-9223372036854775808)))
            }
            SwiftTLA.Action("modulo") {
                result.becomes((Expr<Int>(1) / 0) % Expr<Int>(StateExpr.negate(-9223372036854775808)))
            }
            SwiftTLA.Action("application") {
                result.becomes(Expr<Int>(
                    StateExpr.functionLiteral(StateExpr.set([1]), "key", (Expr<Int>(1) / 0).stateExpr)
                        .applying(StateExpr.negate(-9223372036854775808))
                ))
            }
            SwiftTLA.Action("tupleDomain") {
                result.becomes(Expr<Int>(StateExpr.tuple([
                    (Expr<Int>(1) / 0).stateExpr, true.stateExpr
                ]).domain.cardinality))
            }
        }
    }
}

@Suite("Native expressions retain formal evaluation semantics")
struct NativeExpressionEvaluationTests {
    @Test("Set mapping evaluates its body over the declared domain")
    func setMappingRetainsOperandRoles() throws {
        let compilation = try ExpressionEvaluationOrder.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "mapped"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        var machine = try ExpressionEvaluationOrder.makeMachine()
        _ = try machine.send(.mapped)
        #expect(machine.state.result == 1)
        #expect(try successor.state.value(for: result) == .integer(machine.state.result))
    }

    @Test("Division, modulo, and function arguments retain right-operand precedence")
    func failuresFollowFormalOperandOrder() throws {
        let compilation = try ExpressionEvaluationOrder.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let actions: [(String, ExpressionEvaluationOrder.Action)] = [
            ("division", .division), ("modulo", .modulo), ("application", .application)
        ]
        for (name, action) in actions {
            let formalAction = try #require(compilation.layout.testActionID(named: name))
            #expect(throws: EvalError.integerOverflow(.negation, operands: [Int.min])) {
                _ = try runtime.successors(for: formalAction, from: initial)
            }
            var machine = try ExpressionEvaluationOrder.makeMachine()
            let before = machine.state
            #expect(throws: NativeMachineEvaluationError.integerOverflow(.negation, operands: [Int.min])) {
                _ = try machine.send(action)
            }
            #expect(machine.state == before)
        }
    }

    @Test("A statically known tuple domain still evaluates the tuple")
    func tupleDomainRetainsOperandFailures() throws {
        var machine = try ExpressionEvaluationOrder.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            _ = try machine.send(.tupleDomain)
        }
        #expect(machine.state == before)
    }
}
