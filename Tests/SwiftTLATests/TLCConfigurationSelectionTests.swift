import Testing
@testable import SwiftTLA

struct TLCConfigurationSelectionTests {
    @Test("an assumption-only module exports a TLC configuration without a state-machine directive")
    func rendersAssumptionOnlyConfiguration() throws {
        let rendered = try TLASpec("AssumptionOnly") {
            Constant("MaxNat", 7)
            Assume(true)
        }.compile().render()
        #expect(rendered.tlaBundle.tla.contains("ASSUME TRUE"))
        #expect(!rendered.tlaBundle.tla.contains("VARIABLES"))
        #expect(!rendered.tlaBundle.tla.contains("Init =="))
        #expect(rendered.tlaBundle.cfg == "CONSTANT MaxNat = 7\n")
        #expect(rendered.isAssumptionsOnly)
        #expect(!rendered.checksDeadlock)
        #expect(try rendered.tlaBundle(checking: [], checkDeadlock: false).cfg == "CONSTANT MaxNat = 7\n")
        #expect(throws: CompilationDiagnostic.self) {
            try rendered.tlaBundle(checking: [], checkDeadlock: true)
        }
    }

    @Test("validation selects declared checks without changing the emitted model")
    func selectsChecksFromRenderedModel() throws {
        let x = Var<Int>("x")
        let rendered = try TLASpec("SelectedChecks") {
            Variable(x, 0)
            Action("Advance") { x.becomes(x + 1) }
            Invariant("Nonnegative") { x >= 0 }
            Eventually("Progress", x > 0)
        }.compile().render()
        let complete = try rendered.tlaBundle(checking: [], checkDeadlock: false)
        let invariant = try rendered.tlaBundle(checking: ["Nonnegative"], checkDeadlock: true)
        let temporal = try rendered.tlaBundle(checking: ["Progress"], checkDeadlock: false)
        let initialAndNext = try rendered.tlaBundle(checking: ["Nonnegative"], checkDeadlock: true, behavior: .initialAndNext)
        for bundle in [complete, invariant, temporal, initialAndNext] {
            #expect(bundle.tla == rendered.tlaBundle.tla)
            #expect(bundle.imports == rendered.tlaBundle.imports)
            #expect(bundle.provenance == rendered.tlaBundle.provenance)
        }
        #expect(complete.cfg == "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n")
        #expect(invariant.cfg == "SPECIFICATION Spec\nCHECK_DEADLOCK TRUE\nINVARIANT Nonnegative\n")
        #expect(temporal.cfg == "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\nPROPERTY Progress\n")
        #expect(initialAndNext.cfg == "INIT Init\nNEXT Next\nCHECK_DEADLOCK TRUE\nINVARIANT Nonnegative\n")
        #expect(rendered.tlaBundle.cfg.contains("INVARIANT Nonnegative\nPROPERTY Progress\n"))
        #expect(throws: CompilationDiagnostic.self) {
            try rendered.tlaBundle(checking: ["Advance"], checkDeadlock: false)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try rendered.tlaBundle(checking: ["Missing"], checkDeadlock: true, behavior: .initialAndNext)
        }
    }

    @Test("explicit TLC symmetry selection never silently becomes an unreduced check")
    func rejectsUnsupportedSymmetrySelection() throws {
        let x = Var<Int>("x")
        let noSymmetry = try TLASpec("NoSymmetry") {
            Variable(x, 0)
            Action("Stay") { x.stays }
        }.compile().render()
        #expect(throws: CompilationDiagnostic.self) {
            _ = try noSymmetry.tlaBundle(
                checking: [], checkDeadlock: true,
                symmetryReduction: .enabled(maximumPermutationCount: 2)
            )
        }
        #expect(throws: CompilationDiagnostic.self) {
            _ = try noSymmetry.tlaBundle(symmetryReduction: .enabled(maximumPermutationCount: 2))
        }

        let declared = try TLASpec("DeclaredSymmetry") {
            Variable(x, 0)
            Action("Stay") { x.stays }
            Invariant("Nonnegative") { x >= 0 }
            Eventually("Progress", x > 0)
            Symmetry("Members", Set([0, 1]))
        }.compile().render()
        #expect(try declared.tlaBundle(
            checking: ["Nonnegative"], checkDeadlock: true,
            symmetryReduction: .enabled(maximumPermutationCount: 2)
        ).cfg.contains("SYMMETRY SymmMembers\n"))
        #expect(throws: CompilationDiagnostic.self) {
            _ = try declared.tlaBundle(
                checking: ["Progress"], checkDeadlock: false,
                symmetryReduction: .enabled(maximumPermutationCount: 2)
            )
        }
        #expect(throws: CompilationDiagnostic.self) {
            _ = try declared.tlaBundle(symmetryReduction: .enabled(maximumPermutationCount: 2))
        }
        #expect(throws: CompilationDiagnostic.self) {
            _ = try declared.tlaBundle(
                checking: ["Nonnegative"], checkDeadlock: true,
                symmetryReduction: .enabled(maximumPermutationCount: 0)
            )
        }
    }

    @Test("independent property passes retain their selected behavior and configuration declarations")
    func retainsBehaviorAcrossPasses() throws {
        let configuration = TLCConfiguration(behavior: .initialAndNext,
            declarations: ["CONSTANT N = 3", "CONSTRAINT Bound"], checkDeadlock: true,
            invariants: ["TypeOK"], properties: ["Progress"], symmetry: ["Nodes"])
        let temporal = try configuration.selecting(["Progress"], checkDeadlock: true)
        #expect(temporal.behavior == .initialAndNext)
        #expect(temporal.render(usesSymmetryReduction: true) == """
        INIT Init
        NEXT Next
        CHECK_DEADLOCK TRUE
        CONSTANT N = 3
        CONSTRAINT Bound
        PROPERTY Progress

        """)
        let specification = try temporal.selecting(["Progress"], checkDeadlock: true, behavior: .specification)
        #expect(specification.render(usesSymmetryReduction: false).hasPrefix("SPECIFICATION Spec\n"))
        #expect(configuration.behavior == .initialAndNext)
    }

    @Test("check selection preserves constants, constraints, and declaration order while disabling symmetry")
    func preservesConfigurationDeclarations() throws {
        let configuration = TLCConfiguration(
            declarations: ["CONSTANT N = 3", "CONSTRAINT Bound"], checkDeadlock: true,
            invariants: ["Second", "First"], properties: ["Progress"], symmetry: ["Nodes"])
        let selected = try configuration.selecting(["First", "Second"], checkDeadlock: false)
        #expect(selected.render(usesSymmetryReduction: false) == """
        SPECIFICATION Spec
        CHECK_DEADLOCK FALSE
        CONSTANT N = 3
        CONSTRAINT Bound
        INVARIANT Second
        INVARIANT First

        """)
        #expect(!configuration.render(usesSymmetryReduction: true).contains("SYMMETRY"))
        #expect(configuration.render(usesSymmetryReduction: true).contains("PROPERTY Progress\n"))
        #expect(selected.render(usesSymmetryReduction: true).hasSuffix("SYMMETRY Nodes\n"))
    }
}
