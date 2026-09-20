import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct DieHardestCorpusCheckingTests {
    @Test("MCDieHardest selects decisive comparison with unchanged pinned upstream inputs")
    func preservesReferenceInputs() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "mc-die-hardest" })
        #expect(declaration.comparisonMode == .decisiveCounterexample)
        #expect(try declaration.resolveScenario()?.name == "MCDieHardest")
        let root = projectURL("Verification/FiniteGraph/fixtures")
        let bundle = try TLCProcessRequest.declaredBundle(
            root: root.appendingPathComponent(declaration.module),
            configuration: root.appendingPathComponent(declaration.configuration),
            imports: declaration.imports.map { root.appendingPathComponent($0) },
            dependencies: declaration.dependencies.map {
                .init(importingModule: $0.importingModule, importedModule: $0.importedModule,
                    structuralPath: [declaration.id])
            })
        #expect(SHA256.hex(Data(bundle.tla.utf8)) == declaration.moduleSHA256)
        #expect(SHA256.hex(Data(bundle.cfg.utf8)) == declaration.cfgSHA256)
        #expect(Set(bundle.imports.map(\.name)) == ["DieHardest", "DieHarder", "FiniteSetsExt", "Functions", "Folds"])
        #expect(!bundle.cfg.contains("CONSTRAINT"))
        #expect(!bundle.cfg.contains("CHECK_DEADLOCK FALSE"))
    }

    @Test("MCDieHardest retains unbounded counters and finds the shortest combined solution")
    func preservesInterleavedChecking() throws {
        let scenario = try #require(DieHardestModel.validationScenarios().first)
        let initial = try DieHardestModel.makeMachine(configuration: scenario.configuration)
        #expect(initial.state.c1 == ["j1": 0, "j2": 0])
        #expect(initial.state.c2 == ["j1": 0, "j2": 0, "j3": 0])
        var stutteringJugs = initial
        for count in 1...100 {
            let next = try #require(try stutteringJugs.successors().first {
                $0.machine.state.c1 == initial.state.c1 && $0.machine.state.c2 == initial.state.c2
                    && $0.machine.state.s1 == count && $0.machine.state.s2 == 0
            })
            stutteringJugs = next.machine
        }
        #expect(stutteringJugs.state.s1 == 100)
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["NotSolved"])
        #expect(rendered.checksDeadlock)
        #expect(!rendered.tlaBundle.cfg.contains("CONSTRAINT"))
        guard case .counterexample(let result) = try scenario.check(maximumStates: 100_000) else {
            Issue.record("The upstream configuration must stop at NotSolved")
            return
        }
        #expect(result.trace.count == 12)
        let final = try #require(result.trace.last).state.state
        #expect(final.s1 == 6)
        #expect(final.s2 == 5)
        #expect(final.c1.values.contains(4))
        #expect(final.c2.values.contains(4))
        #expect(result.violations == [.invariant(.NotSolved)])
    }
}
