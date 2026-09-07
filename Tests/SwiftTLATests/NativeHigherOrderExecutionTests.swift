import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// Formal fixtures exercise operator arguments through the generated native API.
@TLAModel
private struct HigherOrderOperatorExecution {
    static var spec: TLASpec {
        TLASpec("HigherOrderOperatorExecution") {
            let number = Var<Int>("number")
            let text = Var<String>("text")
            Variable(number, 0)
            Variable(text, "")
            FormalDefinition("ApplyTwice", parameters: [
                .operator("operation", arity: 1), .value("initial")
            ], body: StateExpr.operatorApplication(
                .reference("operation", arity: 1), [.value(StateExpr.operatorApplication(
                    .reference("operation", arity: 1), [.value(StateExpr.variable("initial"))]
                ))]
            ))
            FormalDefinition("Increment", parameters: [.value("value")],
                body: StateExpr.variable("value") + 1)
            FormalDefinition("Identity", parameters: [.value("value")],
                body: StateExpr.variable("value"))
            FormalDefinition("ApplyThroughLocal", parameters: [
                .operator("operation", arity: 1), .value("initial")
            ], body: StateExpr.letIn([
                LocalOperator("Forward", parameters: [], body: StateExpr.operatorApplication(
                    .reference("operation", arity: 1), [.value(StateExpr.variable("initial"))]
                ))
            ], StateExpr.operatorApplication(.reference("Forward", arity: 0), [])))
            SwiftTLA.Action("distinct") {
                number.becomes(Expr<Int>(StateExpr.operatorApplication(
                    .reference("ApplyTwice", arity: 2), [
                        .operator(.reference("Increment", arity: 1)), .value(0)
                    ]
                )))
                text.becomes(Expr<String>(StateExpr.operatorApplication(
                    .reference("ApplyTwice", arity: 2), [
                        .operator(.reference("Identity", arity: 1)), .value("seven")
                    ]
                )))
            }
            SwiftTLA.Action("captured") {
                number.becomes(Expr<Int>(StateExpr.operatorApplication(
                    .reference("ApplyTwice", arity: 2), [
                        .operator(.lambda(FormalLambda(parameters: ["unused"],
                            body: StateExpr.variable("number") + 5))),
                        .value(StateExpr.variable("number") / 0)
                    ]
                )))
            }
            SwiftTLA.Action("local") {
                number.becomes(Expr<Int>(StateExpr.operatorApplication(
                    .reference("ApplyThroughLocal", arity: 2), [
                        .operator(.reference("Increment", arity: 1)), .value(4)
                    ]
                )))
            }
        }
    }
}

@Suite struct NativeHigherOrderExecutionTests {
    @Test("Higher-order calls specialize integer and string operands independently")
    func distinctOperatorArgumentsMatchFormalSuccessors() throws {
        var machine = try HigherOrderOperatorExecution.makeMachine()
        #expect(machine.state.number == 0)
        #expect(machine.state.text == "")
        try compare(action: .distinct, named: "distinct", machine: &machine)
        #expect(machine.state.number == 2)
        #expect(machine.state.text == "seven")
    }

    @Test("Operator lambdas retain state captures and leave unused arguments unevaluated")
    func capturedLambdasRetainLazyArguments() throws {
        var machine = try HigherOrderOperatorExecution.makeMachine()
        try compare(action: .captured, named: "captured", machine: &machine)
        #expect(machine.state.number == 5)
        #expect(machine.state.text == "")
    }

    @Test("Local operators retain enclosing operator parameters")
    func localOperatorCapturesCallback() throws {
        var machine = try HigherOrderOperatorExecution.makeMachine()
        try compare(action: .local, named: "local", machine: &machine)
        #expect(machine.state.number == 5)
        #expect(machine.state.text == "")
    }

    private func compare(
        action: HigherOrderOperatorExecution.Action,
        named name: String,
        machine: inout HigherOrderOperatorExecution
    ) throws {
        let compilation = try HigherOrderOperatorExecution.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let number = try #require(compilation.layout.testVariableID(named: "number"))
        let text = try #require(compilation.layout.testVariableID(named: "text"))
        #expect(try initial.value(for: number) == .integer(machine.state.number))
        #expect(try initial.value(for: text) == .string(machine.state.text))
        let actionID = try #require(compilation.layout.testActionID(named: name))
        let successors = try runtime.successors(for: actionID, from: initial)
        #expect(successors.count == 1)
        let successor = try #require(successors.first)
        #expect(try machine.isEnabled(action))
        let transition = try machine.send(action)
        #expect(try successor.state.value(for: number) == .integer(transition.after.number))
        #expect(try successor.state.value(for: text) == .string(transition.after.text))
    }
}
