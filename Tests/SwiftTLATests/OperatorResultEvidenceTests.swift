import Testing
@testable import SwiftTLA

@Suite struct OperatorResultEvidenceTests {
    private var metadata: NativeSourceTypeMetadata {
        .init(
            records: ["Operation": [.init(sourceName: "op", name: "op", swiftType: "OperationKind")]],
            enums: ["OperationKind": [.string("read")]]
        )
    }

    @Test("provisional operator record literals acquire validated declared field evidence")
    func cachedLiteralResultRefines() throws {
        let plan = try makePlan(argument: .value(.string("read")), parameterized: false)
        let inference = try NativeTypeInference(plan: plan, sourceTypes: metadata)
        let operation = try #require(plan.formalOperatorDefinitions.first)
        let expected = NativeType.record([.init(name: "op", type: .named("OperationKind"))])
        let resolution = try inference.resolutionScope(.operatorApplication(operation.id, []), expected: expected)
        #expect(resolution.resultType == expected)
        #expect(try #require(resolution.call).result == expected)
    }

    @Test("operator result refinement revalidates actual literal arguments")
    func argumentsRetainFiniteDomainProof() throws {
        let plan = try makePlan(argument: .value(.string("read")), parameterized: true)
        let inference = try NativeTypeInference(plan: plan, sourceTypes: metadata)
        let operation = try #require(plan.formalOperatorDefinitions.first)
        let expected = NativeType.record([.init(name: "op", type: .named("OperationKind"))])
        let expression = CompiledStateExpr.operatorApplication(operation.id, [.value(.value(.string("read")))])
        let resolution = try inference.resolutionScope(expression, expected: expected)
        #expect(resolution.resultType == expected)
        #expect(try #require(resolution.call).result == expected)
        let invalid = try makePlan(argument: .value(.string("write")), parameterized: true)
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(plan: invalid, sourceTypes: metadata)
        }
    }

    @Test("operator contextual results do not convert raw state storage to declared enums")
    func stateRepresentationIsPreserved() throws {
        let plan = try makePlan(argument: .variable("raw"), parameterized: true, rawStorage: true)
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(plan: plan, sourceTypes: metadata)
        }
        let invalidLiteral = try makePlan(argument: .value(.string("write")), parameterized: false)
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(plan: invalidLiteral, sourceTypes: metadata)
        }
    }

    private func makePlan(argument: StateExpr, parameterized: Bool, rawStorage: Bool = false) throws -> NativeMachinePlan {
        let call = StateExpr.operatorApplication(
            .reference("Operation", arity: parameterized ? 1 : 0),
            parameterized ? [.value(argument)] : []
        )
        let body = StateExpr.recordLiteral(.init(["op": parameterized ? .variable("value") : argument]))
        var variables: [NamedVar] = [
            .init(name: "items", initialization: .value(.tuple([])), generatedSwiftType: "TupleExpr<Record<Operation>>", origin: .compiler)
        ]
        if rawStorage {
            variables.append(.init(name: "raw", initialization: .value(.string("read")), generatedSwiftType: "String", origin: .compiler))
        }
        let compilation = try TLASpec(
            name: "ContextualOperatorResult",
            variables: variables,
            actions: [.init(name: "append", body: .and(
                .guard_(.equal(.recordAccess(call, "op"), .value(.string("read")))),
                .assign(.named("items"), .tupleLiteral([call]))
            ))],
            invariants: [],
            formalOperatorDefinitions: [.init(name: "Operation", parameters: parameterized ? [.value("value")] : [], body: body)]
        ).compile()
        return .init(compilation: compilation)
    }
}
