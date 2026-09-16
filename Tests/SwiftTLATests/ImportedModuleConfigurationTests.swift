import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ImportedModuleConfigurationTests {
    @Test("refinement instances retain independent imported module configurations")
    func isolatesRefinementConfigurations() throws {
        let value = Var<Int>("value", 0)
        let abstract = TLASpec("Abstract") {
            Parameter("Limit")
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(
                through: Expr<Int>(.variable("Limit"))))
            Variable(value)
            Action("stay") { value.stays }
        }
        let first = Instance("First", of: abstract)
        let second = Instance("Second", of: abstract)
        let root = TLASpec("Root") {
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 1))
            Variable(value)
            Action("stay") { value.stays }
            first
            second
            Refinement(_name: "FirstClaim", instance: first, mappings: [
                .init(value, from: value), .init(FormalModuleParameter("Limit"), from: 2)
            ])
            Refinement(_name: "SecondClaim", instance: second, mappings: [
                .init(value, from: value), .init(FormalModuleParameter("Limit"), from: 3)
            ])
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: root.compile()))
        let rendered = try program.renderModule()
        #expect(rendered.configuration.declarations.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
        for (index, bound) in [2, 3].enumerated() {
            let owner = "Root__Refinement\(index)"
            #expect(rendered.configuration.declarations.contains(
                "CONSTANT Nat <- [\(owner)__Import0]\(owner)__Configuration0"))
            let module = try #require(rendered.imports.first { $0.name == owner })
            #expect(module.tla.contains("ZSequencesNat == 0..\(bound)"))
            #expect(module.tla.contains("\(owner)__Import0"))
            #expect(rendered.imports.contains { $0.name == "\(owner)__Import0" })
        }
        #expect(rendered.renderedModuleSource.contains("Root__Refinement0__Configuration0 == First!ZSequencesNat"))
        #expect(rendered.renderedModuleSource.contains("Root__Refinement1__Configuration0 == Second!ZSequencesNat"))
        let bundle = TLAModuleBundle(root: .init(name: "Root", tla: rendered.renderedModuleSource),
            imports: rendered.imports,
            provenance: .compiled(identity: program.identity, ownership: [
                .init(moduleName: "Root", owningRoot: "Root", structuralPath: [])
            ] + rendered.importedOwnership, dependencies: rendered.dependencies))
        try bundle.validateDeclaredClosure()
    }

    @Test("refinement specialization substitutes imported module bounds")
    func specializesImportedBounds() throws {
        let source = TLASpec("Abstract") {
            Parameter("Limit")
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(
                through: Expr<Int>(.variable("Limit"))))
        }
        let specialized = source.specializing(parameters: ["Limit": .int(3)])
        #expect(specialized.importConfigurations.first?.replacements.first?.expression ==
            .integerRange(.int(0), .int(3)))
        #expect(throws: Never.self) { try specialized.compile() }
    }

    @Test("concrete and abstract models share one unchanged formal dependency")
    func retainsSharedRefinementImport() throws {
        let value = Var<Int>("value", 0)
        let abstract = TLASpec("Abstract") {
            Import(Folds.module)
            Variable(value)
            Action("stay") { value.stays }
        }
        let instance = Instance("Abstract", of: abstract)
        let root = TLASpec("Root") {
            Import(Folds.module)
            Variable(value)
            Action("stay") { value.stays }
            instance
            Refinement(_name: "Refines", instance: instance, mappings: [.init(value, from: value)])
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: root.compile()))
        let rendered = try program.renderModule()
        #expect(rendered.imports.filter { $0.name == "Folds" }.count == 1)
        #expect(rendered.dependencies.contains { $0.importingModule == "Root__Refinement0" && $0.importedModule == "Folds" })
        let bundle = TLAModuleBundle(root: .init(name: "Root", tla: rendered.renderedModuleSource),
            imports: rendered.imports,
            provenance: .compiled(identity: program.identity, ownership: [
                .init(moduleName: "Root", owningRoot: "Root", structuralPath: [])
            ] + rendered.importedOwnership, dependencies: rendered.dependencies))
        try bundle.validateDeclaredClosure()
    }

    @Test("imported module bounds retain resolved model parameter identities")
    func retainsParameterIdentity() throws {
        let compilation = try ConfiguredModuleMachine.spec.compile()
        let parameter = try #require(compilation.layout.parameters.first)
        let replacement = try #require(compilation.semantics.formalModuleReplacements.first)
        #expect(replacement.expression.children[1].operation == .boundValue(parameter.binder))
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let resolved = try #require(program.formalModuleReplacements.first)
        #expect(resolved.expression.resultType == .set(.int))
        #expect(resolved.expression.children[1].resultType == .int)
        #expect(resolved.expression.children[1].operation == .boundValue(parameter.binder))
    }

    @Test("typed export retains transitive formal module dependencies")
    func retainsTransitiveDependencies() throws {
        let leaf = TLASpec("Leaf") {
            DefineRecursive("Identity", params: ["argument"]) { .variable("argument") }
        }
        let middle = TLASpec("Middle") { Import(leaf) }
        let value = Var<Int>("value", 0)
        let root = TLASpec("Root") {
            Import(middle)
            Variable(value)
            Action("stay") { value.stays }
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: root.compile()))
        let rendered = try program.renderModule()
        #expect(Set(rendered.imports.map(\.name)) == ["Leaf", "Middle"])
        let bundle = TLAModuleBundle(root: .init(name: "Root", tla: rendered.renderedModuleSource),
            imports: rendered.imports,
            provenance: .compiled(identity: program.identity, ownership: [
                .init(moduleName: "Root", owningRoot: "Root", structuralPath: [])
            ] + rendered.importedOwnership, dependencies: rendered.dependencies))
        try bundle.validateDeclaredClosure()
    }

    @Test("model scenarios configure module exports and generated machines together")
    func variesModuleConfiguration() throws {
        let scenarios = try ConfiguredModuleMachine.validationScenarios()
        #expect(scenarios.count == 2)
        for (scenario, maximum) in zip(scenarios, [0, 3]) {
            let rendered = try scenario.render().tlaBundle
            #expect(rendered.tla.contains("ZSequencesNat == 0..maximum"))
            #expect(rendered.cfg.contains("CONSTANT maximum = \(maximum)"))
            #expect(rendered.cfg.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
            #expect(rendered.imports.map(\.name) == ["ZSequences"])
            let machine = try #require(scenario.initialMachines().first)
            #expect(machine.state.value == maximum)
            #expect(try machine.successors().first?.machine.state.value == maximum)
        }
    }

    @Test("imported module configuration cannot depend on changing state")
    func rejectsStateDependentConfiguration() throws {
        let spec = TLASpec("InvalidModuleConfiguration", scoped: { scope in
            let bound = scope.sharedVar(_name: "bound", initial: 2)
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: bound))
        })
        do {
            _ = try spec.compile()
            Issue.record("Accepted a state-dependent module configuration")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .stateDependentFormalModuleReplacement)
            #expect(diagnostic.path == "importConfigurations.ZSequences.Nat")
        }
    }
}
