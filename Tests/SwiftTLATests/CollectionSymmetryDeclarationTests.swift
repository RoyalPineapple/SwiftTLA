@testable import SwiftTLAPlugin
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA

@Suite struct CollectionSymmetryDeclarationTests {
    private struct Device: Identifiable, Sendable { let id: Int }

    private func model(symmetric: Bool) -> TLASpec {
        let devices = CollectionVar<Device, Int>("devices")
        return TLASpec("CollectionSymmetry") {
            ModelCollection(devices, verificationScope: 2, initial: 0)
            if symmetric { Symmetry(devices) }
            CollectionAction("activate", on: devices) { member in devices.update(member, to: 1) }
        }
    }

    @Test("Ordinary collections neither declare nor enable symmetry")
    func ordinaryCollections() throws {
        let compilation = try model(symmetric: false).compile()
        #expect(compilation.semantics.symmetrySets.isEmpty)
        let bundle = try compilation.render().tlaBundle
        #expect(!bundle.tla.contains("Permutations("))
        #expect(!bundle.cfg.contains("SYMMETRY"))
        #expect(throws: FiniteExplorationConfigurationError.symmetryReductionWithoutDeclarations) {
            _ = try SymmetryPlan(compilation: compilation, reduction: .enabled(maximumPermutationCount: 10))
        }
    }

    @Test("Explicit collection symmetry reduces equivalent states without changing transitions")
    func explicitSymmetry() throws {
        let compilation = try model(symmetric: true).compile()
        let ordinary = try ModelChecker(compilation: compilation, configuration: .init(
            maximumStateLimit: 100, symmetryReduction: .disabled)).exploreGraph()
        let reduced = try ModelChecker(compilation: compilation, configuration: .init(
            maximumStateLimit: 100, symmetryReduction: .enabled(maximumPermutationCount: 10))).exploreGraph()
        #expect(ordinary.states.count == 4)
        #expect(reduced.states.count == 3)
        #expect(compilation.semantics.symmetrySets.count == 1)
        #expect(try compilation.render().tlaBundle.cfg.contains("SYMMETRY Symmdevices"))
    }

    @Test("Collection symmetry parsing agrees with the builder independently of declaration order")
    func parserAndBuilder() throws {
        let source = """
        {
            let devices = CollectionVar<Device, Int>("devices")
            Symmetry(devices)
            ModelCollection(devices, verificationScope: 2, initial: 0)
            CollectionAction("activate", on: devices) { member in devices.update(member, to: 1) }
        }
        """
        let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "CollectionSymmetry", closure)
        #expect(parsed.diagnostics.isEmpty)
        let compilation = try parsed.compile()
        let direct = try model(symmetric: true).compile()
        #expect(compilation.identity == direct.identity)
    }
}
