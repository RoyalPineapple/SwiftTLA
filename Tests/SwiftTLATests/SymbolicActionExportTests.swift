import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SymbolicActionExportTests {
    @Test("configured action domains export symbolic quantifiers and concrete invocation metadata")
    func exportsConfiguredDomain() throws {
        let reference = ParameterReference(name: "limit")
        var spec = canonicalTestSpec(variables: [("value", .value(.int(0)))], actions: [
            ("select", .assign(.named("value"), .variable("member")), [
                ActionBinding(name: "member", domain: .integerRange(.int(1), .parameter(reference)), generatedSwiftType: "Int"),
                ActionBinding(name: "other", domain: .integerRange(.int(1), .variable("member")), generatedSwiftType: "Int")
            ])
        ])
        spec.parameters = [.init(reference: reference, swiftType: "Int", domain: .integerRange(.int(0), .int(3)))]
        let compilation = try spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let action = try #require(program.behavior.actions.first)
        let member = try #require(program.binderNames[action.bindings[0].binder])
        let other = try #require(program.binderNames[action.bindings[1].binder])
        let parameter = try #require(program.layout.parameters.first)
        let limit = try #require(program.binderNames[parameter.binder])
        let module = try program.renderModule()
        #expect(module.symbolicActions == [action.id])
        #expect(module.renderedActions.isEmpty)
        #expect(module.renderedModuleSource.contains("Next == (\\E \(member) \\in 1..\(limit): (\\E \(other) \\in 1..\(member): select(\(member), \(other))))"))
        #expect(!module.renderedModuleSource.contains("select__"))
        #expect(throws: CompilationDiagnostic.self) { try compilation.render() }

        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "Configured", program: program))
        let generated = try emitter.exportDeclarations().map(\.description).joined(separator: "\n")
        #expect(generated.contains("configuration.`limit`"))
        #expect(generated.contains("_actions.append(RenderedAction"))
        #expect(generated.contains("FormalActionCall(name:"))
        #expect(generated.contains("arguments: _arguments"))
        #expect(!generated.contains(".compile("))
        #expect(!generated.contains("CompiledEvaluator"))
    }

    @Test("export metadata rejects domains that read machine state")
    func rejectsStateDependentMetadata() throws {
        let spec = canonicalTestSpec(variables: [("value", .value(.int(1)))], actions: [
            ("select", .assign(.named("value"), .variable("member")), [
                ActionBinding(name: "member", domain: .integerRange(.int(1), .variable("value")), generatedSwiftType: "Int")
            ])
        ])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: spec.compile()))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "StateDependent", program: program))
        let generated = try emitter.exportDeclarations().map(\.description).joined(separator: "\n")
        #expect(generated.contains("an immutable domain independent of machine state"))
        #expect(!generated.contains("_actions.append"))
    }
}
