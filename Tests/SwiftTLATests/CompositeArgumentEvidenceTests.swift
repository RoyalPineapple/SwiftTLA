import Testing
@testable import SwiftTLA

@Suite struct CompositeArgumentEvidenceTests {
    @Test("computed composite arguments retain their finite construction evidence")
    func computedDictionaryArgumentRefines() throws {
        let compilation = try compileSpecification()
        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        let body = try #require(compilation.semantics.formalOperatorDefinitions.last).body
        #expect(try inference.type(of: body, expected: expected) == expected)
    }

    @Test("composite argument refinement rejects invalid construction members")
    func invalidDictionaryMemberIsRejected() throws {
        let compilation = try compileSpecification(invalid: true)
        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        let body = try #require(compilation.semantics.formalOperatorDefinitions.last).body
        #expect(throws: CompilationDiagnostic.self) { try inference.type(of: body, expected: expected) }
    }

    @Test("composite argument evidence never reinterprets raw stored dictionaries")
    func rawDictionaryStorageIsRejected() throws {
        let compilation = try compileSpecification(rawStorage: true)
        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        let body = try #require(compilation.semantics.formalOperatorDefinitions.last).body
        #expect(throws: CompilationDiagnostic.self) { try inference.type(of: body, expected: expected) }
    }

    @Test("shared operator calls validate each argument construction independently")
    func distinctConstructionDomains() throws {
        for invalidFirst in [false, true] {
            func call(member: String) -> StateExpr {
                let dictionary = StateExpr.functionLiteral(
                    .setLiteral([.value(.constant(member))]), "key", .value(.constant("NoValue"))
                )
                return .operatorApplication(.reference("Read", arity: 1), [
                    .value(.recordLiteral(.init(["nextState": dictionary])))
                ])
            }
            let valid = call(member: "first")
            let invalid = call(member: "other")
            let body = StateExpr.tupleLiteral(invalidFirst ? [invalid, valid] : [valid, invalid])
            let compilation = try TLASpec(name: "DistinctDomains",
                variables: [], actions: [], invariants: [], formalOperatorDefinitions: [
                    .init(name: "Read", parameters: [.value("acc")],
                        body: .recordAccess(.variable("acc"), "nextState")),
                    .init(name: "Construct", parameters: [], body: body)
                ]).compile()
            let checker = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
            let compiled = try #require(compilation.semantics.formalOperatorDefinitions.last).body
            #expect(throws: CompilationDiagnostic.self) {
                try checker.type(of: compiled, expected: .array(expected))
            }
        }
    }

    @Test("nominal dictionary fields project outward without changing stored key or value evidence")
    func dictionaryReadProjection() throws {
        let sourceTypes = NativeSourceTypeMetadata(records: ["Payload": [
            .init(sourceName: "nextState", name: "nextState", swiftType: "Function<Key,OneOf<First,Second>>")
        ]], enums: ["Key": [.constant("first")], "First": [.constant("NoValue")], "Second": [.constant("second")]])
        let dictionary = StateExpr.functionLiteral(.setLiteral([.value(.constant("first"))]), "key", .value(.constant("NoValue")))
        let compilation = try TLASpec(name: "DictionaryProjection", variables: [
            .init(name: "stored", initialization: .expression(.recordLiteral(.init(["nextState": dictionary]))), generatedSwiftType: "Record<Payload>", origin: .compiler)
        ], actions: [], invariants: [], formalOperatorDefinitions: [
            .init(name: "Read", parameters: [], body: .recordAccess(.variable("stored"), "nextState"))
        ]).compile()
        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: sourceTypes)
        let body = try #require(compilation.semantics.formalOperatorDefinitions.first).body
        let original = try inference.type(of: body)
        let raw = NativeType.dictionary(.atom, .atom)
        #expect(try inference.type(of: body, expected: raw) == raw)
        #expect(try inference.type(of: body) == original)
        #expect(!inference.canProjectRead(raw, to: original))
        #expect(!inference.canProjectRead(original, to: .dictionary(.string, .atom)))
    }

    @Test("recursive composite proofs validate their original base construction")
    func recursiveConstructionEvidence() throws {
        for rawStorage in [false, true] {
            let dictionary = StateExpr.functionLiteral(.setLiteral([.value(.constant("first"))]), "key", .value(.constant("NoValue")))
            var variables: [NamedVar] = [.init(name: "number", initialization: .expression(.int(0)), origin: .compiler)]
            if rawStorage { variables.append(.init(name: "raw", initialization: .expression(dictionary), origin: .compiler)) }
            let initial = StateExpr.recordLiteral(.init(["nextState": rawStorage ? .variable("raw") : dictionary]))
            let operation = FormalOperatorDefinition(name: "Accumulate", parameters: [.value("n"), .value("acc")], body: .ifThenElse(
                .equal(.variable("n"), .int(0)), .variable("acc"),
                .operatorApplication(.reference("Accumulate", arity: 2), [
                    .value(.subtract(.variable("n"), .int(1))),
                    .value(.recordLiteral(.init(["nextState": .recordAccess(.variable("acc"), "nextState")])))
                ])
            ))
            let compilation = try TLASpec(name: "RecursiveEvidence", variables: variables,
                actions: [], invariants: [], formalOperatorDefinitions: [operation,
                    .init(name: "Construct", parameters: [], body: .operatorApplication(.reference("Accumulate", arity: 2), [.value(.int(2)), .value(initial)]))
                ]).compile()
            let inference = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
            let body = try #require(compilation.semantics.formalOperatorDefinitions.last).body
            let result = NativeType.record([.init(name: "nextState", type: expected)])
            if rawStorage {
                #expect(throws: CompilationDiagnostic.self) { try inference.type(of: body, expected: result) }
            } else {
                #expect(try inference.type(of: body, expected: result) == result)
            }
        }
    }

    private var expected: NativeType { .dictionary(.named("Key"), .finite([.constant("NoValue")])) }
    private var metadata: NativeSourceTypeMetadata { .init(enums: ["Key": [.constant("first")]]) }

    private func compileSpecification(invalid: Bool = false, rawStorage: Bool = false) throws -> CompiledSpecification {
        let dictionary = StateExpr.functionLiteral(
            .setLiteral([.value(.constant(invalid ? "other" : "first"))]), "key", .value(.constant("NoValue")))
        var variables: [NamedVar] = [.init(name: "number", initialization: .expression(.int(0)), origin: .compiler)]
        if rawStorage { variables.append(.init(name: "raw", initialization: .expression(dictionary), origin: .compiler)) }
        let record = StateExpr.recordLiteral(.init([
            "nextState": rawStorage ? .variable("raw") : dictionary,
            "execution": .tupleLiteral([])
        ]))
        let compilation = try TLASpec(name: "CompositeArguments", variables: variables,
            actions: [], invariants: [], formalOperatorDefinitions: [
                .init(name: "Read", parameters: [.value("acc")], body: .recordAccess(.variable("acc"), "nextState")),
                .init(name: "Construct", parameters: [], body: .operatorApplication(.reference("Read", arity: 1), [.value(record)]))
            ]).compile()
        return compilation
    }
}
