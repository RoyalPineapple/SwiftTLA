import Foundation
import Testing
@testable import SwiftTLA

@Suite("Compiled specification rendering")
struct CompiledSpecificationRendererTests {
    @Test("compilation rejects a module name that requires renderer rewriting")
    func compilationRejectsInvalidModuleName() {
        let specification = TLASpec(name: "Invalid Root", variables: [], actions: [], invariants: [])

        do {
            _ = try specification.compile()
            Issue.record("Expected an invalid module name diagnostic.")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidSpecificationName)
            #expect(diagnostic.stage == .validation)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error).")
        }
    }

    @Test("the compiled declaration plan owns direct module text")
    func compiledPlanOwnsDirectModuleText() throws {
        let compilation = try compiledBundle()
        let plan = try #require(compilation.moduleSectionPlans["Root"])
        let bundle = try compilation.renderedTLAModuleBundle()

        #expect(bundle.root.tla == plan.renderedModuleSource)
        #expect(bundle.root.cfg == plan.renderedConfiguration)
    }

    @Test("an invalid closure cannot render or materialize a bundle")
    func invalidClosureHasNoRenderedOutcome() throws {
        let invalid = TLASpec(
            name: "InvalidRoot",
            variables: [],
            actions: [],
            invariants: [],
            importConfigurations: [.init(moduleName: "Missing", replacements: [])]
        )
        let destination = temporaryDirectory().appendingPathComponent("bundle")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        #expect(throws: CompilationDiagnostic.self) {
            try invalid.compile().renderedTLAModuleBundle()
        }
        #expect(throws: CompilationDiagnostic.self) {
            try invalid.compile().materializeModuleBundle(to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("rendering carries each shared dependency and its source ownership once")
    func renderDeduplicatesClosureDependencies() throws {
        let support = TLASpec(name: "Support", variables: [], actions: [], invariants: [])
        let left = TLASpec(name: "Left", variables: [], actions: [], invariants: [], imports: [support])
        let right = TLASpec(name: "Right", variables: [], actions: [], invariants: [], imports: [support])
        let root = TLASpec(name: "Root", variables: [], actions: [], invariants: [], imports: [left, right])

        let bundle = try root.compile().renderedTLAModuleBundle()

        #expect(bundle.files.map(\.name) == ["Support", "Left", "Right", "Root"])
        #expect(Set(bundle.files.map(\.name)).count == bundle.files.count)
        guard case let .compiled(_, ownership, dependencies) = bundle.provenance else {
            Issue.record("A compiled renderer produced an external bundle.")
            return
        }
        #expect(ownership.map(\.structuralPath) == [
            ["Root", "Left", "Support"], ["Root", "Left"], ["Root", "Right"], ["Root"]
        ])
        #expect(dependencies.map { ($0.importingModule, $0.importedModule) } == [
            ("Root", "Left"), ("Left", "Support"), ("Root", "Right"), ("Right", "Support")
        ])
    }

    @Test("rendering rejects a bundle whose identity no longer matches its source")
    func renderingRejectsSourceFidelityMismatch() throws {
        let compilation = try compiledBundle()
        let stale = CompiledSpecification(
            spec: compilation.spec,
            formalModuleClosure: compilation.formalModuleClosure,
            identity: .init(value: "stale"),
            layout: compilation.layout,
            bindings: compilation.bindings,
            semantics: compilation.semantics,
            refinements: compilation.refinements,
            moduleSectionPlans: compilation.moduleSectionPlans
        )

        do {
            _ = try stale.renderedTLAModuleBundle()
            Issue.record("Expected rendering to reject a stale compilation identity.")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .compilationIdentityMismatch)
            #expect(diagnostic.stage == .rendering)
        }
    }

    @Test("authored PlusCal presentation also requires the compiled source identity")
    func authoredPlusCalUsesCompiledBoundary() throws {
        let support = TLASpec(name: "Support", variables: [], actions: [], invariants: [])
        let specification = TLASpec("Authored") {
            Import(support)
            Algorithm("Authored") { scope in
                let value = scope.sharedVar("value", initial: 0)
                Do(TestControlLabel.stay) { Assign(value, to: value.expr) }
            }
        }
        let compilation = try specification.compile()

        let bundle = try compilation.renderedPlusCalBundle()
        #expect(bundle.root.tla.contains("--algorithm Authored"))
        #expect(bundle.root.cfg == try compilation.renderedTLAModuleBundle().root.cfg)
        #expect(bundle.imports.map(\.name) == ["Support"])
        guard case .compiled = bundle.provenance else {
            Issue.record("A compiled authored PlusCal bundle lost its provenance.")
            return
        }

        let stale = CompiledSpecification(
            spec: compilation.spec,
            formalModuleClosure: compilation.formalModuleClosure,
            identity: .init(value: "stale"),
            layout: compilation.layout,
            bindings: compilation.bindings,
            semantics: compilation.semantics,
            refinements: compilation.refinements,
            moduleSectionPlans: compilation.moduleSectionPlans
        )
        #expect(throws: CompilationDiagnostic.self) {
            try stale.renderedPlusCalBundle()
        }
    }

    @Test("authored PlusCal export requires one canonical Algorithm root")
    func authoredPlusCalRejectsNonAlgorithmRoot() throws {
        let compilation = try TLASpec(
            name: "DirectOnly", variables: [], actions: [], invariants: []
        ).compile()

        #expect(throws: AlgorithmPlusCalRenderDiagnostic.self) {
            try compilation.renderedPlusCalBundle()
        }
    }

    @Test("materialization publishes the complete compiled bundle in one directory")
    func materializationPublishesCompleteBundle() throws {
        let compilation = try compiledBundle()
        let parent = temporaryDirectory()
        let destination = parent.appendingPathComponent("bundle")
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        try compilation.materializeModuleBundle(to: destination)

        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Support.tla").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Root.tla").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Root.cfg").path))
        let manifest = try String(contentsOf: destination.appendingPathComponent("bundle-manifest.json"))
        #expect(manifest.contains(compilation.identity.value))
        #expect(manifest.contains("Support"))
    }

    @Test("a failed final rename leaves no partial replacement bundle")
    func failedMaterializationPreservesExistingDestination() throws {
        let compilation = try compiledBundle()
        let parent = temporaryDirectory()
        let destination = parent.appendingPathComponent("bundle")
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try Data("existing output".utf8).write(to: destination)

        do {
            try compilation.materializeModuleBundle(to: destination)
            Issue.record("Expected the final directory rename to reject an occupied destination.")
        } catch {}

        #expect(try Data(contentsOf: destination) == Data("existing output".utf8))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        #expect(!siblings.contains { $0.contains("swifttla-staging") })
    }

    private func compiledBundle() throws -> CompiledSpecification {
        let support = TLASpec(name: "Support", variables: [], actions: [], invariants: [])
        let root = TLASpec(name: "Root", variables: [], actions: [], invariants: [], imports: [support])
        return try root.compile()
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
