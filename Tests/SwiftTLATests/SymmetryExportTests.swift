@testable import SwiftTLA
import SwiftTLAMacros
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

    @Test("A validation scenario does not select declared symmetry by default")
    func scenarioDefaultsToUnreducedChecking() throws {
        #expect(try SymmetryScenarioModel.render().tlaBundle.cfg.contains("SYMMETRY Symmmembers"))
        let scenario = try #require(SymmetryScenarioModel.validationScenarios().first)
        #expect(try !scenario.render().tlaBundle.cfg.contains("SYMMETRY"))
    }
}

@TLAModel
private struct SymmetryScenarioModel {
    enum Step: String, CaseIterable { case stay }
    enum Member: String, FiniteTLAValueDomain {
        case a, b
        static var defaultValue: Self { .a }
        static let finiteValues: [Self] = [.a, .b]
    }

    static var spec: TLASpec {
        #spec("SymmetryScenario") { scope in
            let value = scope.sharedVar(initial: 1)
            let members = Symmetry(Set(Member.all))
            members
            Do(Step.stay) { Assign(value, to: value) }
            let ordinary = Validation {}
            ordinary
        }
    }
}
