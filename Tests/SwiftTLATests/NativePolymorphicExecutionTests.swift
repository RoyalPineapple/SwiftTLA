import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// Formal declarations exercise shared compiler bindings at the native boundary.
@TLAModel
private struct IndependentlyTypedOperatorCalls {
    static var spec: TLASpec {
        TLASpec("IndependentlyTypedOperatorCalls") {
            let number = Var<Int>("number")
            let text = Var<String>("text")
            Variable(number, 0)
            Variable(text, "")
            FormalDefinition("Identity", parameters: [.value("value")], body: StateExpr.variable("value"))
            FormalDefinition("Captured", parameters: [.value("value")], body: StateExpr.letIn([
                LocalOperator("ReadCapture", parameters: [], body: StateExpr.variable("value"))
            ], StateExpr.operatorApplication(.reference("ReadCapture", arity: 0), [])))
            SwiftTLA.Action("direct") {
                number.becomes(FormalCall("Identity", 7))
                text.becomes(FormalCall("Identity", "seven"))
            }
            SwiftTLA.Action("captured") {
                number.becomes(FormalCall("Captured", 9))
                text.becomes(FormalCall("Captured", "nine"))
            }
        }
    }
}

@Suite struct NativePolymorphicExecutionTests {
    @Test("integer and string specializations share formal semantics without sharing storage types")
    func distinctArgumentRepresentations() throws {
        let compilation = try IndependentlyTypedOperatorCalls.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let number = try #require(compilation.layout.testVariableID(named: "number"))
        let text = try #require(compilation.layout.testVariableID(named: "text"))
        let cases: [(String, IndependentlyTypedOperatorCalls.Action)] = [
            ("direct", .direct), ("captured", .captured)
        ]
        for (name, action) in cases {
            var machine = try IndependentlyTypedOperatorCalls.makeMachine()
            #expect(try initial.value(for: number) == .integer(machine.state.number))
            #expect(try initial.value(for: text) == .string(machine.state.text))
            #expect(try machine.enabledActions().contains(action))
            let actionID = try #require(compilation.layout.testActionID(named: name))
            let successors = try runtime.successors(for: actionID, from: initial)
            #expect(successors.count == 1)
            let successor = try #require(successors.first)
            let transition = try machine.send(action)
            #expect(try successor.state.value(for: number) == .integer(transition.after.number))
            #expect(try successor.state.value(for: text) == .string(transition.after.text))
        }
    }
}
