import Testing
@testable import SwiftTLA

@Suite struct NativeHigherOrderSpecializationTests {
    @Test("unused enclosing values do not change lambda or callback specialization", arguments: [false, true])
    func specializationUsesOnlyFreeValues(asCallback: Bool) throws {
        let lambda = FormalOperator.lambda(.init(parameters: ["argument"], body: .variable("used")))
        let body = asCallback
            ? StateExpr.operatorApplication(.reference("Invoke", arity: 1), [.operator(lambda)])
            : StateExpr.operatorApplication(lambda, [.value(.int(0))])
        let spec = TLASpec(name: "FreeValues", variables: [], actions: [], invariants: [], formalOperatorDefinitions: [
            .init(name: "Prepare", parameters: [.value("used"), .value("unused")], body: body),
            .init(name: "Invoke", parameters: [.operator("callback", arity: 1)],
                body: .operatorApplication(.reference("callback", arity: 1), [.value(.int(0))]))
        ])
        let compilation = try spec.compile()
        let checker = try NativeTypeInference(compilation: compilation)
        let prepare = try #require(compilation.semantics.formalOperatorDefinitions.first)
        func specialization(unused: CompiledValue) throws -> NativeOperatorSpecialization {
            let expression = CompiledStateExpr.operatorApplication(prepare.id, [
                .value(.value(.integer(7))), .value(.value(unused))
            ])
            let outer = try #require(try checker.resolutionScope(expression, expected: .int).call)
            guard case .checked(let body, _) = outer.implementation else {
                Issue.record("Expected a checked operator body")
                return outer.specialization
            }
            let inner = try #require(body.call)
            return inner.specialization
        }
        #expect(try specialization(unused: .integer(1)) == specialization(unused: .string("unrelated")))
    }

    @Test("zero-argument callbacks retain distinct identities and independent results")
    func zeroArgumentCallbacks() throws {
        let compilation = try specification().compile()
        let inference = try NativeTypeInference(compilation: compilation)
        let operation = try #require(compilation.semantics.formalOperatorDefinitions.first)
        let integerExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(id: .init(ordinal: 0), parameters: [], body: .value(.integer(7)), capturedBindings: [], referencedOperators: [])))
        ])
        let integerResolution = try inference.resolutionScope(integerExpression, expected: .int)
        let integer = try #require(integerResolution.call)
        let stringExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(id: .init(ordinal: 1), parameters: [], body: .value(.string("seven")), capturedBindings: [], referencedOperators: [])))
        ])
        let stringResolution = try inference.resolutionScope(stringExpression, expected: .string)
        let string = try #require(stringResolution.call)
        #expect(integer.result == .int)
        #expect(string.result == .string)
        #expect(integer.specialization.arguments.isEmpty)
        #expect(string.specialization.arguments.isEmpty)
        #expect(integer.specialization != string.specialization)
        let otherIntegerExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(id: .init(ordinal: 2), parameters: [], body: .value(.integer(9)), capturedBindings: [], referencedOperators: [])))
        ])
        let otherInteger = try #require(try inference.resolutionScope(otherIntegerExpression, expected: .int).call)
        #expect(integer.specialization != otherInteger.specialization)
        #expect(integer.callbackUses.values.flatMap { $0 }.allSatisfy { $0.parameters.isEmpty })
        #expect(integer.callbackUses.values.flatMap { $0 }.count == 1)
    }

    @Test("call arguments distinguish values from operators and validate callback arity")
    func argumentKinds() throws {
        let compilation = try specification().compile()
        let inference = try NativeTypeInference(compilation: compilation)
        let callbackOperation = try #require(compilation.semantics.formalOperatorDefinitions.first)
        let valueOperation = try #require(compilation.semantics.formalOperatorDefinitions.last)
        let callback = CompiledFormalOperator.lambda(.init(
            id: .init(ordinal: 0), parameters: [], body: .value(.integer(7)), capturedBindings: [], referencedOperators: []))
        let unaryCallback = CompiledFormalOperator.lambda(.init(
            id: .init(ordinal: 1), parameters: [.init(ordinal: 0)], body: .value(.integer(7)), capturedBindings: [], referencedOperators: []))
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

        let operation = try #require(compilation.semantics.formalOperatorDefinitions.first)
        let inference = try NativeTypeInference(compilation: compilation)
        let expression = (0..<24).reduce(CompiledStateExpr.value(.integer(7))) { nested, _ in
            .operatorApplication(operation.id, [.value(nested)])
        }
        #expect(try inference.type(of: expression) == .int)
        #expect(throws: CompilationDiagnostic.self) {
            try inference.type(of: expression, expected: .string)
        }
    }

    @Test("deep call arguments retain checked results without recursive invocation")
    func deepValueArguments() throws {
        let compilation = try TLASpec(name: "DeepCalls",
            variables: [], actions: [], invariants: [], formalOperatorDefinitions: [
                .init(name: "Identity", parameters: [.value("value")], body: .variable("value"))
            ]).compile()
        let operation = try #require(compilation.semantics.formalOperatorDefinitions.first)
        let checker = try NativeTypeInference(compilation: compilation)
        // Keep each layer alive so destroying the fixture does not recursively
        // release the entire expression on the test worker's small stack.
        var layers: [CompiledStateExpr] = [.value(.integer(7))]
        defer { while layers.popLast() != nil {} }
        for _ in 0..<1_000 {
            layers.append(.operatorApplication(operation.id, [.value(try #require(layers.last))]))
        }
        func check(_ expression: CompiledStateExpr) throws {
            let checked = try checker.resolutionScope(expression, expected: .int)
            #expect(checked.resultType == .int)
            #expect(checked.call?.result == .int)
            #expect(checked.call?.parameters.count == 1)
        }
        try check(try #require(layers.last))
    }

    @Test("long lexical binding chains preserve each binding's type")
    func lexicalBindingChain() throws {
        let compilation = try specification().compile()
        let inference = try NativeTypeInference(compilation: compilation)
        let count = 64
        let expression = (0..<count).reversed().reduce(
            CompiledStateExpr.boundValue(.init(ordinal: count - 1))
        ) { body, index in
            .letValue(.init(ordinal: index), .value(.integer(index)), body)
        }
        let resolution = try inference.resolutionScope(expression, expected: .int)
        #expect(resolution.resultType == .int)
        var binding = resolution
        for index in 0..<count {
            guard case .letValue(let id, _, _) = binding.expression else {
                Issue.record("Expected lexical binding at depth \(index)")
                return
            }
            #expect(id == .init(ordinal: index))
            #expect(binding.children[0].resultType == .int)
            binding = binding.children[1]
        }
        #expect(binding.computationType == .int)
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
            try spec.compile().semantics.formalOperatorDefinitions.map { definition in
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
        let compilation = try specification().compile()
        let inference = try NativeTypeInference(compilation: compilation)
        let operation = try #require(compilation.semantics.formalOperatorDefinitions.last)
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
        guard case .checked(let integerBody, _) = integer.implementation,
              case .checked(let stringBody, _) = string.implementation else {
            Issue.record("Expected checked operator bodies")
            return
        }
        #expect(integerBody.resultType == .int)
        #expect(stringBody.resultType == .string)
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
        let compilation = try spec.compile()
        let inference = try NativeTypeInference(compilation: compilation)
        let operation = try #require(compilation.semantics.formalOperatorDefinitions.first)
        let callExpression = CompiledStateExpr.operatorApplication(operation.id, [
            .operator(.lambda(.init(id: .init(ordinal: 0), parameters: [], body: .value(.integer(7)), capturedBindings: [], referencedOperators: [])))
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
