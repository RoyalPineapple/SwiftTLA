import Testing
@testable import SwiftTLA

@Suite struct NativeHigherOrderSpecializationTests {
    @Test("zero-argument callbacks retain structural identity and independent results")
    func zeroArgumentCallbacks() throws {
        let plan = NativeMachinePlan(compilation: try specification().compile())
        let inference = try NativeTypeInference(plan: plan)
        let operation = try #require(plan.formalOperatorDefinitions.first)
        let integerExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(parameters: [], body: .value(.integer(7)))))
        ])
        let integerResolution = try inference.resolutionScope(integerExpression, expected: .int)
        let integer = try #require(integerResolution.call)
        let stringExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(parameters: [], body: .value(.string("seven")))))
        ])
        let stringResolution = try inference.resolutionScope(stringExpression, expected: .string)
        let string = try #require(stringResolution.call)
        #expect(integer.result == .int)
        #expect(string.result == .string)
        #expect(integer.specialization != string.specialization)
        #expect(integer.callbackUses.values.flatMap { $0 }.allSatisfy { $0.parameters.isEmpty })
        #expect(integer.callbackUses.values.flatMap { $0 }.count == 1)
    }

    @Test("callbacks capture the value shape of each enclosing specialization")
    func capturedValueShapes() throws {
        let plan = NativeMachinePlan(compilation: try specification().compile())
        let inference = try NativeTypeInference(plan: plan)
        let operation = try #require(plan.formalOperatorDefinitions.last)
        let integerExpression = CompiledStateExpr.operatorApplication(operation.id,
            [.value(.value(.integer(7)))])
        let integerResolution = try inference.resolutionScope(integerExpression, expected: .int)
        let integer = try #require(integerResolution.call)
        let stringExpression = CompiledStateExpr.operatorApplication(operation.id,
            [.value(.value(.string("seven")))])
        let stringResolution = try inference.resolutionScope(stringExpression, expected: .string)
        let string = try #require(stringResolution.call)
        #expect(integer.result == .int)
        #expect(string.result == .string)
        #expect(integer.specialization != string.specialization)
        #expect(try integer.inference.type(of: integer.body, expected: .int) == .int)
        #expect(try string.inference.type(of: string.body, expected: .string) == .string)
    }

    @Test("local operators propagate the callback signatures they capture")
    func localOperatorCallbackDemand() throws {
        let spec = TLASpec(name: "CapturedCallback", variables: [
            .init(name: "number", initialization: .expression(.int(0)), origin: .compiler)
        ], actions: [], invariants: [], formalOperatorDefinitions: [
            .init(name: "ApplyThroughLocal", parameters: [.operator("callback", arity: 0)],
                body: .letIn([
                    .init("Local", parameters: [], body: .operatorApplication(.reference("callback", arity: 0), []))
                ], .recursiveCall("Local", [])))
        ])
        let plan = NativeMachinePlan(compilation: try spec.compile())
        let inference = try NativeTypeInference(plan: plan)
        let operation = try #require(plan.formalOperatorDefinitions.first)
        let callExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(parameters: [], body: .value(.integer(7)))))
        ])
        let callResolution = try inference.resolutionScope(callExpression, expected: .int)
        let call = try #require(callResolution.call)
        #expect(call.result == .int)
        #expect(call.callbackUses.values.flatMap { $0 }.count == 1)
    }

    private func specification() -> TLASpec {
        TLASpec(name: "CallbackShapes", variables: [
            .init(name: "number", initialization: .expression(.int(0)), origin: .compiler)
        ], actions: [], invariants: [], formalOperatorDefinitions: [
            .init(name: "Invoke", parameters: [.operator("callback", arity: 0)],
                body: .operatorApplication(.reference("callback", arity: 0), [])),
            .init(name: "Capture", parameters: [.value("value")],
                body: .letIn([
                    .init("Captured", parameters: [], body: .variable("value"))
                ], .operatorApplication(.reference("Invoke", arity: 1), [
                    .operator(.reference("Captured", arity: 0))
                ])))
        ])
    }
}
