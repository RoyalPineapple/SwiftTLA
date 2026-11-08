import Testing
import SwiftSyntax
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ParameterResolutionTests {
    @Test("macro declarations retain names, source locations, and range structure")
    func retainsSourceDeclarations() throws {
        let spec = ConfiguredCounter.spec
        #expect(spec.parameters.map { $0.reference.name } == ["limit", "stopAtLimit"])
        let compilation = try spec.compile()
        for (source, lowered) in zip(spec.parameters, compilation.layout.parameters) {
            #expect(source.reference == lowered.reference)
            #expect(lowered.reference.sourceSpan.location != .unavailable)
            #expect(lowered.reference.sourceSpan.utf8Length > 0)
        }
        let limit = try #require(compilation.layout.parameters.first)
        #expect(compilation.semantics.behavior.parameterDomains[limit.binder]?.operation == .integerRange)
    }

    @Test("parameter identity survives variable substitution")
    func retainsIdentity() {
        let reference = ParameterReference(name: "limit")
        let parameter = ModelParameter<Int>(reference: reference)
        #expect(StateExpr.substituteVariable("limit", .int(99), in: parameter.stateExpr) == .parameter(reference))
        #expect(parameter.stateExpr.freeVariableNames.isEmpty)
        #expect(ParameterReference(name: "limit") != reference)
    }

    @Test("lowering retains a parameter as a resolved binder rather than a literal")
    func resolvesParameter() throws {
        let reference = ParameterReference(name: "limit")
        let parameter = ModelParameter<Int>(reference: reference)
        var spec = TLASpec("Configured") {
            Invariant("Nonnegative") { parameter >= 0 }
        }
        spec.parameters = [.init(reference: reference, swiftType: "Int", domain: .setLiteral([.value(.int(0)), .value(.int(1))]))]
        let compilation = try spec.compile()
        let binding = try #require(compilation.layout.parameters.first)
        #expect(binding.reference == reference)
        #expect(binding.swiftType == "Int")
        #expect(compilation.semantics.behavior.invariants[0].predicate.expression.children[0].operation == .boundValue(binding.binder))
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        #expect(program.bindingTypes[binding.binder] == .int)
        #expect(program.behavior.parameterDomains[binding.binder]?.resultType == .set(.int))
        #expect(program.behavior.invariants[0].predicate.expression.children[0].operation == .boundValue(binding.binder))
    }

    @Test("a same-named foreign parameter cannot bind to this model")
    func rejectsForeignParameter() throws {
        let foreign = ModelParameter<Int>(reference: .init(name: "limit"))
        var spec = TLASpec("Configured") {
            Invariant("Nonnegative") { foreign >= 0 }
        }
        spec.parameters = [.init(reference: .init(name: "limit"), swiftType: "Int", domain: .setLiteral([.value(.int(0))]))]
        #expect(throws: CompilationDiagnostic.self) { try spec.compile() }
    }

    @Test("parameter domains must match the declared type")
    func rejectsIncompatibleDomain() throws {
        var spec = TLASpec("Configured") {}
        spec.parameters = [.init(reference: .init(name: "enabled"), swiftType: "Bool", domain: .setLiteral([.value(.int(1))]))]
        let compilation = try spec.compile()
        #expect(throws: CompilationDiagnostic.self) {
            try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        }
    }

    @Test("legal parameter domains cannot depend on mutable state")
    func rejectsMutableDomain() throws {
        var spec = TLASpec(name: "MutableDomain", variables: [.init(name: "value", initial: .int(2))],
            actions: [], invariants: [])
        spec.parameters = [.init(reference: .init(name: "limit"), swiftType: "Int",
            domain: .integerRange(.int(0), .variable("value")))]
        let compilation = try spec.compile()
        #expect(throws: CompilationDiagnostic.self) {
            try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        }
    }

    @Test("legacy export rejects unbound model parameters instead of emitting invalid TLA")
    func rejectsUnboundExport() throws {
        let compilation = try ConfiguredCounter.spec.compile()
        #expect(throws: CompilationDiagnostic.self) { try compilation.render() }
    }

    @Test("formal parameter names cannot capture state, library or generated declarations")
    func separatesParameterAndStateNames() throws {
        for (name, needsAlias) in [
            ("ceiling", false), ("limit", true), ("Len", true),
            ("Init", true), ("Next", true), ("Spec", true),
        ] {
            let reference = ParameterReference(name: name)
            var spec = TLASpec(name: "ParameterNames", variables: [.init(name: "limit", initial: .int(0))],
                actions: [.init(name: "advance", body: .assign(.named("limit"), .int(1)))], invariants: [])
            spec.parameters = [.init(reference: reference, swiftType: "Int", domain: .integerRange(.int(1), .int(3)))]
            let compilation = try spec.compile()
            let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
            let parameter = try #require(program.layout.parameters.first)
            #expect(parameter.reference == reference)
            let formalName = try #require(program.binderNames[parameter.binder])
            #expect((formalName != name) == needsAlias, "Parameter \(name) must retain a distinct formal name only when needed")
            let module = try program.renderModule()
            #expect(module.renderedModuleSource.contains("VARIABLES limit"))
            #expect(module.renderedModuleSource.contains("CONSTANTS \(formalName)\n"))
            if needsAlias { #expect(!module.renderedModuleSource.contains("CONSTANTS \(name)\n")) }
            var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "ParameterNames", program: program))
            let declarations = try emitter.configurationDeclarations()
            let configuration = try #require(declarations.compactMap { $0.as(StructDeclSyntax.self) }
                .first { $0.name.text == "Configuration" })
            let identities = try #require(configuration.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
                .first { $0.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "fieldIdentities" } })
            let identityNames = identities.tokens(viewMode: .sourceAccurate).compactMap { token -> String? in
                if case .stringSegment(let value) = token.tokenKind { return value }
                return nil
            }
            #expect(identityNames == [name, formalName])
        }
    }
}
