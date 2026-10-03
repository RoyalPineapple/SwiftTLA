@testable import SwiftTLA
import Testing

struct SymmetryExportTests {
    @Test("Ordinary specifications do not declare symmetry")
    func ordinarySpecificationsDoNotExportSymmetry() throws {
        let counter = Var<Int>("counter")
        let spec = TLASpec("Ordinary") {
            Variable(counter, 0)
        }

        let bundle = try spec.compile().render().tlaBundle
        #expect(!bundle.tla.contains("Permutations("))
        #expect(!bundle.cfg.contains("SYMMETRY"))
    }

    @Test("Explicit finite symmetry is present in the TLA module and TLC configuration")
    func explicitSymmetryExportsToBothFiles() throws {
        let spec = TLASpec("ExplicitSymmetry") {
            Symmetry("Members", Set([1, 2]))
        }

        let bundle = try spec.compile().render().tlaBundle
        #expect(bundle.tla.contains("SymmMembers == Permutations({1, 2})"))
        #expect(bundle.cfg.contains("SYMMETRY SymmMembers"))
    }
}
