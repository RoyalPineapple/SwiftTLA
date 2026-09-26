import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct BoundedRecursiveCall {
    static var spec: TLASpec {
        TLASpec("BoundedRecursiveCall") {
            let result = Var<Int>("result")
            Variable(result, 7)
            SwiftTLA.Action("advance") {
                result.becomes(Expr<Int>(StateExpr.letIn([
                    LocalOperator("CountDown", parameters: ["remaining"], body: StateExpr.if(
                        StateExpr.variable("remaining") == 0,
                        then: 0,
                        else: StateExpr.variable("Step").applying(StateExpr.variable("remaining") - 1))),
                    LocalOperator("Step", parameters: ["next"], domain: StateExpr.integerRange(0, 0),
                        body: StateExpr.variable("CountDown").applying(StateExpr.variable("next")))
                ], StateExpr.variable("CountDown").applying(2))))
            }
        }
    }
}

@Suite struct RecursiveFunctionDomainTests {
    @Test("Recursive calls check the callee's domain before entering its body")
    func checksDomainAcrossRecursiveCalls() throws {
        let compilation = try BoundedRecursiveCall.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "advance"))
        #expect(throws: EvalError.recursiveArgumentOutsideDomain) {
            try runtime.successors(for: action, from: initial)
        }
        var machine = try BoundedRecursiveCall.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.functionArgumentOutsideDomain) {
            try machine.send(.advance)
        }
        #expect(machine.state == before)
    }
}
