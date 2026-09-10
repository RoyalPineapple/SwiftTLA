@testable import SwiftTLAPlugin
import Testing
@testable import SwiftTLA

@Suite struct RecordProjectionEvidenceTests {
    @Test("record projection validates the selected nominal field and retains siblings")
    func selectedFieldContext() throws {
        let compilation = try compileSpecification(key: .value(.constant("first")))
        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        let checked = try inference.resolutionScope(compilation.semantics.formalOperatorDefinitions[0].body, expected: .named("Key"))
        let source = try #require(checked.children.first?.resultType)
        #expect(source == .record([
            .init(name: "key", type: .named("Key")),
            .init(name: "valid", type: .bool)
        ]))
    }

    @Test("record projection rejects literals outside the selected nominal domain")
    func invalidLiteralIsRejected() throws {
        let compilation = try compileSpecification(key: .value(.constant("other")))
        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        #expect(throws: CompilationDiagnostic.self) {
            try inference.type(of: compilation.semantics.formalOperatorDefinitions[0].body, expected: .named("Key"))
        }
    }

    @Test("record projection cannot reinterpret raw state as a named value")
    func rawStorageIsRejected() throws {
        let compilation = try compileSpecification(key: .variable("raw"), rawStorage: true)
        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        #expect(throws: CompilationDiagnostic.self) {
            try inference.type(of: compilation.semantics.formalOperatorDefinitions[0].body, expected: .named("Key"))
        }
    }

    @Test("stored nominal record and tuple fields project to their raw and finite representations")
    func storedFieldsProjectWithoutChangingStorage() throws {
        let sourceTypes = NativeSourceTypeMetadata(records: ["Payload": [
            .init(sourceName: "key", name: "key", swiftType: "Key"),
            .init(sourceName: "valid", name: "valid", swiftType: "Bool")
        ]], enums: ["Key": [.constant("first")]])
        let compilation = try TLASpec(name: "StoredProjection", variables: [
            .init(name: "record", initialization: .expression(.recordLiteral(.init(["key": .value(.constant("first")), "valid": .bool(true)]))), generatedSwiftType: "Record<Payload>", origin: .compiler),
            .init(name: "pair", initialization: .expression(.tupleLiteral([.value(.constant("first")), .bool(true)])), generatedSwiftType: "Pair<Key,Bool>", origin: .compiler)
        ], actions: [], invariants: [], formalOperatorDefinitions: [
            .init(name: "RecordKey", parameters: [], body: .recordAccess(.variable("record"), "key")),
            .init(name: "TupleKey", parameters: [], body: .tupleAccess(.variable("pair"), 1))
        ]).compile()
        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: sourceTypes)
        for definition in compilation.semantics.formalOperatorDefinitions {
            #expect(try inference.type(of: definition.body, expected: .atom) == .atom)
            #expect(try inference.type(of: definition.body, expected: .finite([.constant("first")])) == .finite([.constant("first")]))
            #expect(try inference.type(of: definition.body) == .named("Key"))
        }
    }

    @Test("finite record fields project only when every member has the requested representation")
    func finiteFieldRepresentationProof() throws {
        for mixed in [false, true] {
            let sourceTypes = NativeSourceTypeMetadata(records: ["Payload": [
                .init(sourceName: "value", name: "value", swiftType: "OneOf<First,Second>")
            ]], enums: ["First": [.constant("first")], "Second": mixed ? [.int(2)] : [.constant("second")]])
            let compilation = try TLASpec(name: "FiniteProjection", variables: [
                .init(name: "record", initialization: .expression(.recordLiteral(.init(["value": .value(.constant("first"))]))), generatedSwiftType: "Record<Payload>", origin: .compiler)
            ], actions: [], invariants: [], formalOperatorDefinitions: [
                .init(name: "Read", parameters: [], body: .recordAccess(.variable("record"), "value"))
            ]).compile()
            let inference = try NativeTypeInference(compilation: compilation, sourceTypes: sourceTypes)
            let body = compilation.semantics.formalOperatorDefinitions[0].body
            let stored = try inference.type(of: body)
            guard case .finite = stored else { Issue.record("Expected finite field"); return }
            if mixed {
                #expect(throws: CompilationDiagnostic.self) { try inference.type(of: body, expected: .atom) }
            } else {
                #expect(try inference.type(of: body, expected: .atom) == .atom)
            }
            #expect(try inference.type(of: body) == stored)
            #expect(!inference.canProjectRead(.atom, to: stored))
            #expect(!inference.canProjectRead(stored, to: .string))
        }
    }

    private var metadata: NativeSourceTypeMetadata {
        .init(enums: ["Key": [.constant("first")]])
    }

    private func compileSpecification(key: StateExpr, rawStorage: Bool = false) throws -> CompiledSpecification {
        var variables: [NamedVar] = [
            .init(name: "number", initialization: .expression(.int(0)), origin: .compiler)
        ]
        if rawStorage {
            variables.append(.init(name: "raw", initialization: .value(.constant("first")), origin: .compiler))
        }
        let projection = StateExpr.recordAccess(.recordLiteral(.init([
            "key": key, "valid": .bool(true)
        ])), "key")
        return try TLASpec(name: "RecordProjection", variables: variables,
            actions: [], invariants: [], formalOperatorDefinitions: [
                .init(name: "Projection", parameters: [], body: projection)
            ]).compile()
    }
}
