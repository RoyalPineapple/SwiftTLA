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

    @Test("Declared symmetry remains available without reducing the default TLC check")
    func explicitSymmetryExportsToBothFiles() throws {
        let spec = TLASpec("ExplicitSymmetry") {
            Symmetry("Members", Set([1, 2]))
        }

        let rendered = try spec.compile().render()
        let bundle = rendered.tlaBundle
        #expect(bundle.tla.contains("SymmMembers == Permutations({1, 2})"))
        #expect(!bundle.cfg.contains("SYMMETRY"))
        #expect(try rendered.tlaBundle(symmetryReduction: .enabled(maximumPermutationCount: 2))
            .cfg.contains("SYMMETRY SymmMembers"))
    }

    @Test("A validation scenario does not select declared symmetry by default")
    func scenarioDefaultsToUnreducedChecking() throws {
        let model = try SymmetryScenarioModel.render()
        #expect(!model.tlaBundle.cfg.contains("SYMMETRY"))
        #expect(try model.tlaBundle(symmetryReduction: .enabled(maximumPermutationCount: 2))
            .cfg.contains("SYMMETRY Symmmembers"))
        let scenarios = try SymmetryScenarioModel.validationScenarios()
        let ordinary = try #require(scenarios.first(where: { $0.name == "ordinary" }))
        let reduced = try #require(scenarios.first(where: { $0.name == "reduced" }))
        #expect(try !ordinary.render().tlaBundle.cfg.contains("SYMMETRY"))
        #expect(try reduced.render().tlaBundle.cfg.contains("SYMMETRY Symmmembers"))
    }

    @Test("Scenario symmetry selection rejects foreign and duplicate handles")
    func scenarioSymmetryRequiresOneOwnedHandle() {
        let registered = Symmetry("members", Set([1, 2]))
        let foreign = Symmetry("members", Set([1, 2]))
        let state = Var<Int>("state")
        let foreignSpec = TLASpec("ForeignSymmetry") {
            Variable(state, 0)
            registered
            Validation(_name: "check") {}.usingSymmetry(foreign)
        }
        let duplicateSpec = TLASpec("DuplicateSymmetry") {
            Variable(state, 0)
            registered
            Validation(_name: "check") {}
                .usingSymmetry(registered).usingSymmetry(registered)
        }
        for (spec, reason) in [(foreignSpec, "foreign or unregistered symmetry selection"),
                               (duplicateSpec, "duplicate check selection")] {
            do {
                _ = try spec.compile()
                Issue.record("Expected symmetry selection to reject \(reason)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "validation.check")
                #expect(diagnostic.actual == reason)
            } catch {
                Issue.record("Expected CompilationDiagnostic, got \(error)")
            }
        }
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
            let reduced = Validation {}.usingSymmetry(members)
            reduced
        }
    }
}
