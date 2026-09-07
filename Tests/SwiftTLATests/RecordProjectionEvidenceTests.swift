import Testing
@testable import SwiftTLA

@Suite struct RecordProjectionEvidenceTests {
    @Test("record projection validates the selected nominal field and retains siblings")
    func selectedFieldContext() throws {
        let plan = try makePlan(key: .value(.constant("first")))
        let inference = try NativeTypeInference(plan: plan, sourceTypes: metadata)
        guard case .recordAccess(let record, _, let key) = plan.formalOperatorDefinitions[0].body else {
            Issue.record("Expected record projection fixture")
            return
        }
        let source = try inference.recordProjectionSourceType(record, key: key, expected: .named("Key"))
        #expect(source == .record([
            .init(name: "key", type: .named("Key")),
            .init(name: "valid", type: .bool)
        ]))
    }

    @Test("record projection rejects literals outside the selected nominal domain")
    func invalidLiteralIsRejected() throws {
        let plan = try makePlan(key: .value(.constant("other")))
        let inference = try NativeTypeInference(plan: plan, sourceTypes: metadata)
        #expect(throws: CompilationDiagnostic.self) {
            try inference.type(of: plan.formalOperatorDefinitions[0].body, expected: .named("Key"))
        }
    }

    @Test("record projection cannot reinterpret raw state as a named value")
    func rawStorageIsRejected() throws {
        let plan = try makePlan(key: .variable("raw"), rawStorage: true)
        let inference = try NativeTypeInference(plan: plan, sourceTypes: metadata)
        #expect(throws: CompilationDiagnostic.self) {
            try inference.type(of: plan.formalOperatorDefinitions[0].body, expected: .named("Key"))
        }
    }

    @Test("stored nominal record and tuple fields project to their raw and finite representations")
    func storedFieldsProjectWithoutChangingStorage() throws {
        let sourceTypes = NativeSourceTypeMetadata(records: ["Payload": [
            .init(sourceName: "key", name: "key", swiftType: "Key"),
            .init(sourceName: "valid", name: "valid", swiftType: "Bool")
        ]], enums: ["Key": [.constant("first")]])
        let plan = NativeMachinePlan(compilation: try TLASpec(name: "StoredProjection", variables: [
            .init(name: "record", initialization: .recordLiteral(.init(["key": .value(.constant("first")), "valid": .bool(true)])), generatedSwiftType: "Record<Payload>", origin: .compiler),
            .init(name: "pair", initialization: .tupleLiteral([.value(.constant("first")), .bool(true)]), generatedSwiftType: "Pair<Key,Bool>", origin: .compiler)
        ], actions: [], invariants: [], formalOperatorDefinitions: [
            .init(name: "RecordKey", parameters: [], body: .recordAccess(.variable("record"), "key")),
            .init(name: "TupleKey", parameters: [], body: .tupleAccess(.variable("pair"), 1))
        ]).compile())
        let inference = try NativeTypeInference(plan: plan, sourceTypes: sourceTypes)
        for definition in plan.formalOperatorDefinitions {
            #expect(try inference.type(of: definition.body, expected: .atom) == .atom)
            #expect(try inference.type(of: definition.body, expected: .finite([.constant("first")])) == .finite([.constant("first")]))
            #expect(try inference.type(of: definition.body) == .named("Key"))
        }
    }

    private var metadata: NativeSourceTypeMetadata {
        .init(enums: ["Key": [.constant("first")]])
    }

    private func makePlan(key: StateExpr, rawStorage: Bool = false) throws -> NativeMachinePlan {
        var variables: [NamedVar] = [
            .init(name: "number", initialization: .int(0), origin: .compiler)
        ]
        if rawStorage {
            variables.append(.init(name: "raw", initialization: .value(.constant("first")), origin: .compiler))
        }
        let projection = StateExpr.recordAccess(.recordLiteral(.init([
            "key": key, "valid": .bool(true)
        ])), "key")
        return .init(compilation: try TLASpec(name: "RecordProjection", variables: variables,
            actions: [], invariants: [], formalOperatorDefinitions: [
                .init(name: "Projection", parameters: [], body: projection)
            ]).compile())
    }
}
