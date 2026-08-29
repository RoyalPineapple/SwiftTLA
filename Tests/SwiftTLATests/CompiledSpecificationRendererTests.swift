import Testing
@testable import SwiftTLA

@Suite("Compiled specification rendering")
struct CompiledSpecificationRendererTests {
    @Test("compilation rejects a module name that requires renderer rewriting")
    func compilationRejectsInvalidModuleName() {
        for name in ["Invalid Root", "MODULE"] {
            do {
                _ = try TLASpec(name: name, variables: [], actions: [], invariants: []).compile()
                Issue.record("Expected an invalid module name diagnostic for \(name).")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.code == .invalidSpecificationName)
                #expect(diagnostic.stage == .validation)
            } catch {
                Issue.record("Expected CompilationDiagnostic, got \(error).")
            }
        }
    }

    @Test("an invalid closure cannot render a bundle")
    func invalidClosureHasNoRenderedOutcome() throws {
        let invalid = TLASpec(
            name: "InvalidRoot",
            variables: [],
            actions: [],
            invariants: [],
            importConfigurations: [.init(moduleName: "Missing", replacements: [])]
        )
        #expect(throws: CompilationDiagnostic.self) {
            try invalid.compile().renderedTLAModuleBundle()
        }
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
        #expect(dependencies.map(\.importingModule) == ["Root", "Left", "Root", "Right"])
        #expect(dependencies.map(\.importedModule) == ["Left", "Support", "Right", "Support"])
    }

    @Test("authored PlusCal presentation uses the compiled bundle")
    func authoredPlusCalUsesCompiledBoundary() throws {
        let support = TLASpec(name: "Support", variables: [], actions: [], invariants: [])
        let specification = TLASpec("Authored") {
            Import(support)
            Algorithm("Authored", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Do(TestControlLabel.stay) { Assign(value, to: value.expr) }
            })
        }
        let compilation = try specification.compile()

        let bundle = try compilation.renderedPlusCalBundle()
        let directBundle = compilation.renderedTLAModuleBundle()
        #expect(bundle.root.tla.contains("--algorithm Authored"))
        #expect(bundle.root.cfg == directBundle.root.cfg)
        #expect(bundle.imports.map(\.name) == ["Support"])
        guard case .compiled = bundle.provenance else {
            Issue.record("A compiled authored PlusCal bundle lost its provenance.")
            return
        }

    }

    @Test("authored PlusCal export requires one canonical Algorithm root")
    func authoredPlusCalRejectsNonAlgorithmRoot() throws {
        let compilation = try TLASpec(
            name: "DirectOnly", variables: [], actions: [], invariants: []
        ).compile()

        #expect(throws: CompilationDiagnostic.self) {
            try compilation.renderedPlusCalBundle()
        }
    }

    @Test("compilation rejects malformed CASE expressions")
    func compilationRejectsMalformedCases() {
        let cases: [(StateExpr, String)] = [
            (.caseExpr([.bool(true)], nil), "an unmatched CASE branch"),
            (.caseExpr([], nil), "no CASE branches"),
            (.caseExpr([], .int(1)), "no CASE branches")
        ]

        for (index, testCase) in cases.enumerated() {
            let specification = TLASpec(
                name: "MalformedCase\(index)",
                variables: [],
                actions: [],
                invariants: [],
                formalOperatorDefinitions: [
                    .init(name: "Choice", parameters: [], body: testCase.0)
                ]
            )
            do {
                _ = try specification.compile()
                Issue.record("Expected malformed CASE expression \(index) to fail compilation.")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.code == .invalidFormalDeclaration)
                #expect(diagnostic.stage == .validation)
                #expect(diagnostic.actual == testCase.1)
            } catch {
                Issue.record("Expected CompilationDiagnostic, got \(error).")
            }
        }
    }

}
