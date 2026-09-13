import Testing
@testable import SwiftTLA

struct TLCConfigurationSelectionTests {
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
        for bundle in [complete, invariant, temporal] {
            #expect(bundle.tla == rendered.tlaBundle.tla)
            #expect(bundle.imports == rendered.tlaBundle.imports)
            #expect(bundle.provenance == rendered.tlaBundle.provenance)
        }
        #expect(complete.cfg == "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n")
        #expect(invariant.cfg == "SPECIFICATION Spec\nCHECK_DEADLOCK TRUE\nINVARIANT Nonnegative\n")
        #expect(temporal.cfg == "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\nPROPERTY Progress\n")
        #expect(rendered.tlaBundle.cfg.contains("INVARIANT Nonnegative\nPROPERTY Progress\n"))
        #expect(throws: CompilationDiagnostic.self) {
            try rendered.tlaBundle(checking: ["Advance"], checkDeadlock: false)
        }
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
