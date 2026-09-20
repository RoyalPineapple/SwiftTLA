import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct DiningPhilosophersCorpusConfigurationTests {
    @Test("Spec and INIT/NEXT configurations share the complete Dining graph")
    func preservesBothConfigurations() throws {
        let scenarios = try DiningPhilosophersModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["NP5", "AP NP5"])
        let runs = try scenarios.map { try NativeScenarioRun($0, maximumStates: 67) }
        for run in runs { try run.validateExpectations() }
        #expect(runs[0].native.graph == runs[1].native.graph)
        let graph = try #require(runs[0].native.graph).graph
        #expect(graph.initialStateKeys.count == 1)
        #expect(graph.states.count == 67)
        #expect(graph.edges.count == 335)
        #expect(scenarios[0].behavior == .specification)
        #expect(scenarios[1].behavior == .initialAndNext)
        #expect(scenarios[1].checking.properties == [.TypeOK, .ExclusiveAccess])
        #expect(scenarios.allSatisfy { $0.checking.checkDeadlock })
        #expect(runs[0].native.checks.properties["NobodyStarves"] == .satisfied)
        #expect(runs[1].native.checks.properties["NobodyStarves"] == nil)
        let rendered = try scenarios[1].render()
        let cfg = try #require(rendered.tlaBundle.root.cfg)
        #expect(cfg.contains("INIT Init\nNEXT Next\n"))
        #expect(!cfg.contains("SPECIFICATION"))
        #expect(!cfg.contains("PROPERTY NobodyStarves"))
        #expect(try rendered.plusCalBundle().root.cfg == cfg)
    }

    @Test("each pinned reference resolves its model-owned scenario and module closure")
    func resolvesPinnedVariants() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let cases = manifest.cases.filter { $0.sourceModel == .diningPhilosophers }
        #expect(cases.map(\.id) == ["dining-philosophers", "ap-dining-philosophers"])
        for declaration in cases {
            let scenario = try #require(try declaration.resolveScenario())
            #expect(scenario.name == declaration.scenario)
            let root = projectURL("Verification/FiniteGraph/fixtures")
            #expect(SHA256.hex(try Data(contentsOf: root.appendingPathComponent(declaration.module))) == declaration.moduleSHA256)
            #expect(SHA256.hex(try Data(contentsOf: root.appendingPathComponent(declaration.configuration))) == declaration.cfgSHA256)
            #expect(declaration.sourceInput?.sha256 == declaration.moduleSHA256)
        }
        let ap = try #require(cases.last)
        #expect(ap.imports == [cases[0].module])
        #expect(ap.dependencies.count == 1)
        #expect(ap.dependencies.first?.importingModule == "APDiningPhilosophers")
        #expect(ap.dependencies.first?.importedModule == "DiningPhilosophers")
    }

    @Test("missing or unknown scenarios cannot fall back to default model checks", arguments: [nil, "", "NP4"] as [String?])
    func rejectsUnknownScenario(name: String?) throws {
        let source = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json"))) as? [String: Any])
        let cases = try #require(source["cases"] as? [[String: Any]])
        var declaration = try #require(cases.first { $0["id"] as? String == "ap-dining-philosophers" })
        declaration["scenario"] = name
        let decoded = try JSONDecoder().decode(FiniteGraphManifest.Case.self,
            from: JSONSerialization.data(withJSONObject: declaration))
        #expect(throws: EvidenceFormatError.invalidField(record: "ap-dining-philosophers", field: "model-owned scenario")) {
            try decoded.resolveScenario()
        }
    }
}
