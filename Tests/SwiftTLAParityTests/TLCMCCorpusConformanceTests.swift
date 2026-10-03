import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct TLCMCCorpusConformanceTests {
    @Test("TLCMC Graph 1 has one canonical compiled specification")
    func hasOneCanonicalCompiledSpecification() throws {
        let entry = try #require(CanonicalCorpus.entries.first { $0.id == "tlcmc-graph-1" })
        let compilation = try TLCMCModel.spec.compile()
        let bundle = try entry.rendered().tlaBundle

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
        #expect(bundle.imports.map(\.name) == declaredCase.imports)
        #expect(declaredCase.dependencies.isEmpty)
        #expect(SHA256.hex(module) == declaredCase.moduleSHA256)
        #expect(SHA256.hex(configuration) == declaredCase.cfgSHA256)
    }

    @Test("TLCMC generated graph retains termination and the violation path")
    func generatedGraphRetainsTerminationAndViolationPath() throws {
        let initialStates = try TLCMCModel.initialMachines()
        #expect(initialStates.count == 2)
        #expect(throws: GeneratedMachineError.ambiguousInitialState) { try TLCMCModel.makeMachine() }
        let graph = try ReachabilityGraph(initialMachines: initialStates, maximumStates: 100_000)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.deadlockedStates.isEmpty)
        var terminalStates = 0
        for (state, edges) in graph.transitions where edges.contains(where: { $0.action == .Terminating }) {
            terminalStates += 1
            #expect(edges.count == 1)
            #expect(edges[0].target == state)
        }
        #expect(terminalStates > 0)
        let counterexample = try #require(TLAStateProjection.Token(validating: "counterexample"))
        let programCounter = try #require(TLAStateProjection.Token(validating: "pc"))
        let expectedPath: TLAValue = .tuple([.int(2), .int(3), .int(4)])
        let found = try graph.transitions.keys.contains { snapshot in
            let state = try initialStates[0].formalProjection(of: snapshot)
            return state.value(for: counterexample) == expectedPath
                && state.value(for: programCounter) == .string("Done")
        }
        #expect(found)
    }
}
