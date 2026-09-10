import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct TLCMCCorpusConformanceTests {
    @Test("TLCMC Graph 1 has one canonical compiled specification")
    func hasOneCanonicalCompiledSpecification() throws {
        let entry = try #require(CanonicalCorpus.entries.first { $0.id == "tlcmc-graph-1" })
        let compilation = try entry.specification().compile()
        let resolved = try TLCMCModel.spec.compile()
        let bundle = try compilation.render().tlaBundle

        #expect(compilation.identity == resolved.identity)
        #expect(compilation.description.actions.map(\.name).contains("returnToDequeue") == false)
        #expect(compilation.description.controlLocations.map(\.sourceName).contains("returnToDequeue") == false)
        #expect(bundle.root.tla.contains("SelectSeq"))

        let manifestData = try Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json"))
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self, from: manifestData)
        let declaredCase = try #require(manifest.cases.first { $0.id == entry.id })
        let sourceInput = try #require(declaredCase.sourceInput)
        #expect(sourceInput.path == "tlaplus/Examples@ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/TLC/TLCMC.tla")
        #expect(sourceInput.sha256 == "5d553b7066376e909a093c6f5c0f881d5d37c4907a19f5d5738a465ec2ab4294")

        let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/tlcmc-graph-1/TLCMC.tla"))
        let configuration = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/tlcmc-graph-1/TLCMC.cfg"))
        let renderedModule = Data(bundle.root.tla.utf8)
        #expect(module == renderedModule)
        #expect(configuration == Data(entry.swiftConfiguration.tlaText.utf8))
        #expect(bundle.imports.map(\.name) == declaredCase.imports)
        #expect(declaredCase.dependencies.isEmpty)
        #expect(SHA256.hex(module) == declaredCase.moduleSHA256)
        #expect(SHA256.hex(configuration) == declaredCase.cfgSHA256)
    }

    @Test("TLCMC Graph 1 explores the violation path before termination")
    func exploresViolationPathBeforeTermination() throws {
        let compilation = try TLCMCModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)
        ).explore()
        guard case .ok = exploration.outcome else {
            Issue.record("TLCMC Graph 1 must finish its finite exploration.")
            return
        }

        let counterexample = try #require(TLAStateProjection.Token(validating: "counterexample"))
        let programCounter = try #require(TLAStateProjection.Token(validating: "pc"))
        let expectedPath: TLAValue = .tuple([.int(2), .int(3), .int(4)])
        #expect(exploration.graph.states.values.contains {
            $0.value(for: counterexample) == expectedPath && $0.value(for: programCounter) == .string("Done")
        })
    }
}
