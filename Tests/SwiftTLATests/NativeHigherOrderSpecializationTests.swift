import Testing
@testable import SwiftTLA

@Suite struct NativeHigherOrderSpecializationTests {
    @Test("zero-argument callbacks retain distinct identities and independent results")
    func zeroArgumentCallbacks() throws {
        let plan = NativeMachinePlan(compilation: try specification().compile())
        let inference = try NativeTypeInference(plan: plan)
        let operation = try #require(plan.formalOperatorDefinitions.first)
        let integerExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(id: .init(ordinal: 0), parameters: [], body: .value(.integer(7)))))
        ])
        let integerResolution = try inference.resolutionScope(integerExpression, expected: .int)
        let integer = try #require(integerResolution.call)
        let stringExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(id: .init(ordinal: 1), parameters: [], body: .value(.string("seven")))))
        ])
        let stringResolution = try inference.resolutionScope(stringExpression, expected: .string)
        let string = try #require(stringResolution.call)
        #expect(integer.result == .int)
        #expect(string.result == .string)
        #expect(integer.specialization.arguments.isEmpty)
        #expect(string.specialization.arguments.isEmpty)
        #expect(integer.specialization != string.specialization)
        let otherIntegerExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(id: .init(ordinal: 2), parameters: [], body: .value(.integer(9)))))
        ])
        let otherInteger = try #require(try inference.resolutionScope(otherIntegerExpression, expected: .int).call)
        #expect(integer.specialization != otherInteger.specialization)
        #expect(integer.callbackUses.values.flatMap { $0 }.allSatisfy { $0.parameters.isEmpty })
        #expect(integer.callbackUses.values.flatMap { $0 }.count == 1)
    }

    @Test("call arguments distinguish values from operators and validate callback arity")
    func argumentKinds() throws {
        let plan = NativeMachinePlan(compilation: try specification().compile())
        let inference = try NativeTypeInference(plan: plan)
        let callbackOperation = try #require(plan.formalOperatorDefinitions.first)
        let valueOperation = try #require(plan.formalOperatorDefinitions.last)
        let callback = CompiledFormalOperator.lambda(.init(
            id: .init(ordinal: 0), parameters: [], body: .value(.integer(7))))
        let unaryCallback = CompiledFormalOperator.lambda(.init(
            id: .init(ordinal: 1), parameters: [.init(ordinal: 0)], body: .value(.integer(7))))
        for expression in [
            CompiledStateExpr.operatorApplication(callbackOperation.id, [.value(.value(.integer(7)))]),
            .operatorApplication(callbackOperation.id, [.operator(unaryCallback)]),
            .operatorApplication(valueOperation.id, [.operator(callback)])
        ] {
            #expect(throws: CompilationDiagnostic.self) {
                try inference.resolutionScope(expression, expected: .int)
            }
        }
    }

    @Test("nested calls retain checked argument types and reject incompatible result contexts")
    func nestedValueArguments() throws {
        let compilation = try TLASpec(name: "NestedCalls", variables: [
            .init(name: "number", initialization: .value(.int(0)), origin: .compiler)
        ], actions: [], invariants: [], formalOperatorDefinitions: [
            .init(name: "Identity", parameters: [.value("value")], body: .variable("value"))
        ]).compile()
        let plan = NativeMachinePlan(compilation: compilation)
        let operation = try #require(plan.formalOperatorDefinitions.first)
        let inference = try NativeTypeInference(plan: plan)
        let expression = (0..<24).reduce(CompiledStateExpr.value(.integer(7))) { nested, _ in
            .operatorApplication(operation.id, [.value(nested)])
        }
        #expect(try inference.type(of: expression) == .int)
        #expect(throws: CompilationDiagnostic.self) {
            try inference.type(of: expression, expected: .string)
        }
    }

    @Test("long lexical binding chains preserve each binding's type")
    func lexicalBindingChain() throws {
        let plan = NativeMachinePlan(compilation: try specification().compile())
        let inference = try NativeTypeInference(plan: plan)
        let count = 64
        let expression = (0..<count).reversed().reduce(
            CompiledStateExpr.boundValue(.init(ordinal: count - 1))
        ) { body, index in
            .letValue(.init(ordinal: index), .value(.integer(index)), body)
        }
        let resolution = try inference.resolutionScope(expression, expected: .int)
        #expect(resolution.resultType == .int)
        for index in 0..<count {
            #expect(resolution.scope.bindings[.init(ordinal: index)] == .int)
        }
    }

    @Test("Shared lowering assigns deterministic identities to anonymous functions")
    func loweredFunctionIdentities() throws {
        let spec = TLASpec(name: "AnonymousFunctions", variables: [
            .init(name: "number", initialization: .value(.int(0)), origin: .compiler)
        ], actions: [], invariants: [], formalOperatorDefinitions: (0..<2).map { index in
            FormalOperatorDefinition(name: "Function\(index)", parameters: [], body:
                .operatorApplication(.lambda(.init(parameters: ["argument"], body: .int(index))), [.value(.int(0))]))
        })
        func identities() throws -> [LambdaID] {
            try NativeMachinePlan(compilation: spec.compile()).formalOperatorDefinitions.map { definition in
                guard case .lambdaApplication(let lambda, _) = definition.body else {
                    throw NativeIdentityTestError.expectedLambda
                }
                return lambda.id
            }
        }
        let first = try identities()
        #expect(first.count == 2)
        #expect(Set(first).count == 2)
        #expect(try identities() == first)
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
            .operator(.lambda(.init(id: .init(ordinal: 0), parameters: [], body: .value(.integer(7)))))
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

private enum NativeIdentityTestError: Error { case expectedLambda }
