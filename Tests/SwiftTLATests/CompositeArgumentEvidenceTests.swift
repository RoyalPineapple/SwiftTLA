import Testing
@testable import SwiftTLA

@Suite struct CompositeArgumentEvidenceTests {
    @Test("computed composite arguments retain their finite construction evidence")
    func computedDictionaryArgumentRefines() throws {
        let plan = try makePlan()
        let inference = try NativeTypeInference(plan: plan, sourceTypes: metadata)
        let body = try #require(plan.formalOperatorDefinitions.last).body
        #expect(try inference.type(of: body, expected: expected) == expected)
    }

    @Test("composite argument refinement rejects invalid construction members")
    func invalidDictionaryMemberIsRejected() throws {
        let plan = try makePlan(invalid: true)
        let inference = try NativeTypeInference(plan: plan, sourceTypes: metadata)
        let body = try #require(plan.formalOperatorDefinitions.last).body
        #expect(throws: CompilationDiagnostic.self) { try inference.type(of: body, expected: expected) }
    }

    @Test("composite argument evidence never reinterprets raw stored dictionaries")
    func rawDictionaryStorageIsRejected() throws {
        let plan = try makePlan(rawStorage: true)
        let inference = try NativeTypeInference(plan: plan, sourceTypes: metadata)
        let body = try #require(plan.formalOperatorDefinitions.last).body
        #expect(throws: CompilationDiagnostic.self) { try inference.type(of: body, expected: expected) }
    }

    private var expected: NativeType { .dictionary(.named("Key"), .finite([.constant("NoValue")])) }
    private var metadata: NativeSourceTypeMetadata { .init(enums: ["Key": [.constant("first")]]) }

    private func makePlan(invalid: Bool = false, rawStorage: Bool = false) throws -> NativeMachinePlan {
        let dictionary = StateExpr.functionLiteral(
            .setLiteral([.value(.constant(invalid ? "other" : "first"))]), "key", .value(.constant("NoValue")))
        var variables: [NamedVar] = [.init(name: "number", initialization: .int(0), origin: .compiler)]
        if rawStorage { variables.append(.init(name: "raw", initialization: dictionary, origin: .compiler)) }
        let record = StateExpr.recordLiteral(.init([
            "nextState": rawStorage ? .variable("raw") : dictionary,
            "execution": .tupleLiteral([])
        ]))
        let compilation = try TLASpec(name: "CompositeArguments", variables: variables,
            actions: [], invariants: [], formalOperatorDefinitions: [
                .init(name: "Read", parameters: [.value("acc")], body: .recordAccess(.variable("acc"), "nextState")),
                .init(name: "Construct", parameters: [], body: .operatorApplication(.reference("Read", arity: 1), [.value(record)]))
            ]).compile()
        return .init(compilation: compilation)
    }
}
