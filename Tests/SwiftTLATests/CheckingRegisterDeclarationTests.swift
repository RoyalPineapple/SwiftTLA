import Testing
import SwiftParser
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct CheckingRegisterDeclarationTests {
    @Test("Register declarations retain typed identities and symbolic initializers")
    func retainsDeclarations() throws {
        let spec = try checkingRegisterDeclarationSpec()
        #expect(spec.checkingRegisters.map { $0.reference.name } == ["firstFreeze", "found"])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: spec.compile()))
        let freeze = try #require(program.layout.checkingRegisters.first)
        let parameter = try #require(program.layout.parameters.first)
        #expect(freeze.reference == spec.checkingRegisters[0].reference)
        #expect(freeze.reference.sourceSpan.location != .unavailable)
        #expect(program.checkingRegisterTypes[freeze.id] == .int)
        #expect(program.behavior.checkingRegisterInitializations[freeze.id]?.operation == .boundValue(parameter.binder))
        #expect(program.layout.variables.map { $0.declaration.name } == ["value"])
        let module = try program.renderModule().renderedModuleSource
        #expect(module.contains("TLC"))
        #expect(module.contains("ASSUME TLCSet(0, \(program.binderNames[parameter.binder]!))"))
        #expect(module.contains("ASSUME TLCSet(1, FALSE)"))
    }

    @Test("Native generation emits typed register storage and configuration-based initialization")
    func emitsTypedStorage() throws {
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: checkingRegisterDeclarationSpec().compile()))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "InitializedCheckingRegisters", program: program))
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(generated.contains("public var firstFreeze: Int"))
        #expect(generated.contains("public var found: Bool"))
        #expect(generated.contains("firstFreeze: configuration.`initialFreeze`"))
        #expect(generated.contains("found: false"))
        #expect(!Parser.parse(source: "struct InitializedCheckingRegisters {\n\(generated)\n}").hasError)
    }

    @Test("Scoped declarations retain their typed handles and initial values")
    func declaresTypedHandles() {
        let scope = SpecificationScope()
        let register: CheckingRegister<Int> = scope.checkingRegister(as: Int.self, initial: 999, _name: "freeze")
        #expect(scope.checkingRegisters.count == 1)
        #expect(scope.checkingRegisters[0].reference == register.reference)
        #expect(scope.checkingRegisters[0].initial == .value(.int(999)))
    }

    @Test("Register initializer types are checked before native generation")
    func rejectsWrongType() throws {
        var spec = TLASpec("WrongRegisterType") {}
        spec.checkingRegisters = [.init(reference: .init(name: "freeze"), swiftType: "Int", initial: .value(.bool(false)))]
        #expect(throws: CompilationDiagnostic.self) {
            try CompiledProgram(inputs: SourceTypeResolver().resolve(in: spec.compile()))
        }
    }

    @Test("Run initialization cannot depend on a model state")
    func rejectsStateDependentInitialization() throws {
        var spec = TLASpec(name: "MutableRegisterInitial", variables: [.init(name: "value", initial: .int(0))],
            actions: [], invariants: [])
        spec.checkingRegisters = [.init(reference: .init(name: "freeze"), swiftType: "Int", initial: .variable("value"))]
        #expect(throws: CompilationDiagnostic.self) {
            try CompiledProgram(inputs: SourceTypeResolver().resolve(in: spec.compile()))
        }
    }

    @Test("Distinct models own distinct register identities even when names match")
    func ownsIdentity() {
        #expect(CheckingRegisterReference(name: "freeze") != CheckingRegisterReference(name: "freeze"))
    }
}
