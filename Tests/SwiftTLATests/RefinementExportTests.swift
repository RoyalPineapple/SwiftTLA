import Foundation
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct RefinementExportTests {
    @Test("imported concrete constants and model values receive explicit substitutions")
    func bindsImportedConstants() throws {
        enum Step: String, CaseIterable { case stay }
        let value = Var<Int>("value")
        let abstract = TLASpec("AbstractConstants") {
            Constant("Limit", 2)
            Constant("Marker", TLAValue.constant("Token"))
            Variable(value, 0)
            Action("stay") { value.stays }
        }
        let instance = Instance("Abstract", of: abstract)
        let source = TLASpec("ConcreteConstants") {
            Algorithm("Loop", scoped: { scope in
                let state = scope.sharedVar("value", initial: 0)
                While(Step.stay, true) { Assign(state, to: state) }
            })
            instance
            Refinement(name: "Refines", instance: instance, mappings: [.init(value, from: value)])
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: source.compile()))
        let module = try program.renderModule()
        #expect(module.renderedModuleSource.contains("CONSTANTS Token\n"))
        #expect(module.renderedModuleSource.contains("Limit <- 2"))
        #expect(module.renderedModuleSource.contains("Marker <- Token"))
        #expect(module.renderedModuleSource.contains("Token <- Token"))
        #expect(module.configuration.declarations.contains("CONSTANT Token = Token"))
        #expect(try #require(module.imports.first).tla.contains("CONSTANTS Limit, Marker, Token\n"))
        let plusCal = try #require(try program.renderAuthoredPlusCal(declarations: module))
        #expect(plusCal.contains("CONSTANTS Token\n"))
        #expect(plusCal.contains("Abstract == INSTANCE ConcreteConstants__Refinement0"))
        #expect(plusCal.contains("Limit <- 2"))
        #expect(plusCal.contains("Marker <- Token"))
        #expect(plusCal.contains("Token <- Token"))
        let instancePosition = try #require(plusCal.range(of: "Abstract == INSTANCE"))
        let claimPosition = try #require(plusCal.range(of: "Refines == Abstract!Spec"))
        #expect(instancePosition.lowerBound < claimPosition.lowerBound)
        try validateBundle(module, name: program.moduleName, identity: program.identity, plusCal: plusCal)
    }

    @Test("specialization substitutes parameters through nested refinement mappings")
    func specializesNestedMappings() throws {
        let value = Var<Int>("value")
        let limit = Var<Int>("Limit")
        let leaf = TLASpec("Leaf") {
            Parameter("Limit")
            Variable(value, limit)
            Action("stay") { value.stays }
        }
        let inner = Instance("Inner", of: leaf)
        let middle = TLASpec("Middle") {
            Parameter("Limit")
            Variable(value, limit)
            Action("stay") { value.stays }
            inner
            Refinement(name: "InnerClaim", instance: inner,
                mappings: [.init(value, from: value), .init(FormalModuleParameter("Limit"), from: limit)])
        }
        let outer = Instance("Outer", of: middle)
        let root = TLASpec("Root") {
            Variable(value, 3)
            Action("stay") { value.stays }
            outer
            Refinement(name: "OuterClaim", instance: outer,
                mappings: [.init(value, from: value), .init(FormalModuleParameter("Limit"), from: 3)])
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: root.compile()))
        let module = try program.renderModule()
        #expect(module.imports.count == 2)
        for imported in module.imports {
            #expect(imported.tla.contains("Init == value = 3"))
            #expect(!imported.tla.contains("CONSTANTS Limit"))
        }
        try validateBundle(module, name: program.moduleName, identity: program.identity)
    }

    @Test("typed export preserves distinct instances of one abstract module")
    func exportsDistinctInstances() throws {
        let value = Var<Int>("value")
        let abstract = TLASpec("AbstractTarget") {
            Variable(value, 0)
            Action("stay") { value.stays }
        }
        let first = Instance("First", of: abstract)
        let second = Instance("Second", of: abstract)
        let count = Var<Int>("count")
        let source = TLASpec("ConcreteTargets") {
            Variable(count, 0)
            Action("stay") { count.stays }
            first
            second
            Refinement(name: "SecondClaim", instance: second, mappings: [.init(value, from: count + 1)])
            Refinement(name: "FirstClaim", instance: first, mappings: [.init(value, from: count)])
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: source.compile()))
        let module = try program.renderModule()
        #expect(module.configuration.refinements == ["SecondClaim", "FirstClaim"])
        #expect(module.imports.map(\.name) == ["ConcreteTargets__Refinement1", "ConcreteTargets__Refinement0"])
        #expect(module.renderedModuleSource.contains("Second == INSTANCE ConcreteTargets__Refinement1 WITH value <- (count + 1)"))
        #expect(module.renderedModuleSource.contains("First == INSTANCE ConcreteTargets__Refinement0 WITH value <- count"))
        #expect(module.renderedModuleSource.contains("SecondClaim == Second!Spec"))
        #expect(module.importedOwnership.map(\.structuralPath) == [["Second"], ["First"]])
        try validateBundle(module, name: program.moduleName, identity: program.identity)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "ConcreteTargets", program: program))
        let native = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(native.contains("_generatedImports:"))
        #expect(!native.contains(".compile("))
    }

    @Test("nested refinement exports retain the complete typed dependency closure")
    func exportsNestedInstances() throws {
        let value = Var<Int>("value")
        let leaf = TLASpec("Leaf") {
            Variable(value, 0)
            Action("stay") { value.stays }
        }
        let leafInstance = Instance("Inner", of: leaf)
        let middle = TLASpec("Middle") {
            Variable(value, 0)
            Action("stay") { value.stays }
            leafInstance
            Refinement(name: "InnerClaim", instance: leafInstance, mappings: [.init(value, from: value)])
        }
        let middleInstance = Instance("Outer", of: middle)
        let root = TLASpec("Root") {
            Variable(value, 0)
            Action("stay") { value.stays }
            middleInstance
            Refinement(name: "OuterClaim", instance: middleInstance, mappings: [.init(value, from: value)])
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: root.compile()))
        let module = try program.renderModule()
        #expect(module.imports.map(\.name) == ["Root__Refinement0", "Root__Refinement0__Refinement0"])
        #expect(module.importedOwnership.map(\.structuralPath) == [["Outer"], ["Outer", "Inner"]])
        #expect(module.dependencies.map(\.importingModule) == ["Root", "Root__Refinement0"])
        try validateBundle(module, name: program.moduleName, identity: program.identity)
    }

    @Test("refinement substitutions follow the concrete actions used for enabledness")
    func ordersEnablednessDependencies() throws {
        let available = Var<Bool>("available")
        let abstract = TLASpec("Availability") {
            Variable(available, true)
            Action("stay") { available.stays }
        }
        let count = Var<Int>("count")
        let action = Action("advance") { count.becomes(count + 1).when(count < 2) }
        let instance = Instance("Availability", of: abstract)
        let source = TLASpec("EnabledMapping") {
            Variable(count, 0)
            action
            instance
            Refinement(name: "Refines", instance: instance, mappings: [.init(available, from: StateExpr.enabled(action))])
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: source.compile()))
        let module = try program.renderModule()
        let actionPosition = try #require(module.renderedModuleSource.range(of: "advance =="))
        let instancePosition = try #require(module.renderedModuleSource.range(of: "Availability == INSTANCE"))
        #expect(actionPosition.lowerBound < instancePosition.lowerBound)
        try validateBundle(module, name: program.moduleName, identity: program.identity)
    }

    private func validateBundle(_ module: RenderedModule, name: String, identity: CompilationIdentity, plusCal: String? = nil) throws {
        let configuration = module.configuration
        let rendered = try RenderedSpecification(_generatedModule: name, source: module.renderedModuleSource,
            compilationIdentity: identity.value, declarations: configuration.declarations,
            checkDeadlock: configuration.checkDeadlock, invariants: configuration.invariants,
            reachabilityProperties: configuration.reachabilityProperties, properties: configuration.properties,
            refinements: configuration.refinements, symmetry: configuration.symmetry, actions: module.renderedActions,
            _generatedPlusCal: plusCal.map { .success($0) },
            _generatedImports: try module.imports.map { imported in
                let owner = try #require(module.importedOwnership.first { $0.moduleName == imported.name })
                return (imported.name, imported.tla, owner.structuralPath)
            },
            _generatedDependencies: module.dependencies.map { ($0.importingModule, $0.importedModule, $0.structuralPath) })
        try rendered.tlaBundle.validateDeclaredClosure()
        #expect(rendered.tlaBundle.imports == module.imports)
        if plusCal != nil {
            let authored = try rendered.plusCalBundle()
            try authored.validateDeclaredClosure()
            #expect(authored.imports == module.imports)
            #expect(authored.root.cfg == rendered.tlaBundle.root.cfg)
        }
    }
}
