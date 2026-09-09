import Testing
@testable import SwiftTLA

@Suite struct LocalOperatorInvocationTests {
    @Test("Explicit local calls preserve caller bindings and lazy arguments")
    func callerBindingsAndLazyArguments() throws {
        let expression = StateExpr.letValue("value", .int(41), .letIn([
            LocalOperator("AddOne", parameters: ["value", "unused"],
                body: .add(.variable("value"), .int(1)))
        ], .operatorApplication(.reference("AddOne", arity: 2), [
            .value(.variable("value")), .value(.divide(.int(1), .int(0)))
        ])))

        #expect(try evaluateClosed(expression) == .int(42))
    }

    @Test("Explicit local calls enforce the declared parameter domain", arguments: [0, 1])
    func parameterDomain(value: Int) throws {
        let expression = StateExpr.letIn([
            LocalOperator("OnlyZero", parameters: ["value"],
                domain: .setLiteral([.int(0)]), body: .variable("value"))
        ], .operatorApplication(.reference("OnlyZero", arity: 1), [.value(.int(value))]))

        if value == 0 {
            #expect(try evaluateClosed(expression) == .int(0))
        } else {
            #expect(throws: EvalError.self) { try evaluateClosed(expression) }
        }
    }
}
