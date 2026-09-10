@testable import SwiftTLAPlugin
import Testing
@testable import SwiftTLA

@Suite struct DomainContextEvidenceTests {
    @Test("DOMAIN comparisons revalidate computed finite keys in the declared nominal domain")
    func computedDomainComparison() throws {
        let compilation = try compileSpecification()
        let program = try NativeResolvedProgram(compilation: compilation, sourceTypes: metadata)
        let root = try #require(program.invariants.values.first)
        let domain = program[program[root].children[0]]
        #expect(domain.resultType == .set(.named("Key")))
        #expect(program[domain.children[0]].resultType == .dictionary(.named("Key"), .int))
    }

    @Test("DOMAIN context does not reinterpret raw dictionary storage or admit unknown keys")
    func invalidDomainEvidenceIsRejected() throws {
        for input in [(raw: true, invalid: false), (raw: false, invalid: true)] {
            let compilation = try compileSpecification(rawStorage: input.raw, invalid: input.invalid)
            #expect(throws: CompilationDiagnostic.self) {
                try NativeResolvedProgram(compilation: compilation, sourceTypes: metadata)
            }
        }
    }

    private var metadata: NativeSourceTypeMetadata { .init(enums: ["Key": [.constant("first")]]) }

    private func compileSpecification(rawStorage: Bool = false, invalid: Bool = false) throws -> CompiledSpecification {
        let function = StateExpr.functionLiteral(.setLiteral([.value(.constant(invalid ? "other" : "first"))]), "key", .int(1))
        var variables: [NamedVar] = [
            .init(name: "keys", initialization: .expression(.setLiteral([.value(.constant("first"))])), generatedSwiftType: "SetExpr<Key>", origin: .compiler)
        ]
        if rawStorage { variables.append(.init(name: "raw", initialization: .expression(function), origin: .compiler)) }
        let domain = StateExpr.domain(rawStorage ? .variable("raw") : function)
        return try TLASpec(name: "DomainContext", variables: variables,
            actions: [], invariants: [.init(name: "Keys", body: .equal(domain, .variable("keys")))]).compile()
    }
}
