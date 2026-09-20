import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct AsynchInterfaceCorpusStateGraphTests {
    @Test("AsynchInterface pins original and AP references with model-owned scenarios")
    func pinsIndependentReferences() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declarations = manifest.cases.filter { $0.sourceModel == .asynchInterface }
        #expect(Set(declarations.map(\.id)) == ["asynch-interface", "ap-asynch-interface"])
        for declaration in declarations {
            #expect(try declaration.resolveScenario()?.name == declaration.scenario)
            let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.module))
            let configuration = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.configuration))
            #expect(SHA256.hex(module) == declaration.moduleSHA256)
            #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
            if declaration.id == "ap-asynch-interface" {
                #expect(declaration.imports == ["asynch-interface/AsynchInterface.tla"])
            }
        }
        let original = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/asynch-interface/AsynchInterface.tla"))
        #expect(SHA256.hex(original) == "86adf068c65219ebe140e047dece85a9d04b9492d508e4aa4d5f86685ada09d4")
    }

    @Test("AsynchInterface preserves complete configured graphs, invariants, deadlocks, and formal tags")
    func preservesConfiguredGraphs() throws {
        let scenarios = try AsynchInterfaceModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["Upstream", "APAsynchInterface"])
        for scenario in scenarios {
            let count = scenario.configuration.Data.count
            let run = try NativeScenarioRun(scenario, maximumStates: 100)
            try run.validateExpectations()
            #expect(run.coverage.coversCompleteScenario)
            let graph = try #require(run.native.graph).graph
            #expect(graph.initialStateKeys.count == 2 * count)
            #expect(graph.states.count == 4 * count)
            #expect(graph.edges.count == 2 * count * (count + 1))
            #expect(run.native.checks.deadlock == .satisfied)
            #expect(run.native.checks.properties == ["TypeInvariant": .satisfied])
            let rendered = try scenario.render()
            #expect(rendered.checksDeadlock)
            #expect(rendered.checkNames == ["TypeInvariant"])
            #expect(!rendered.tlaBundle.tla.contains("Terminating =="))
            #expect(rendered.tlaBundle.tla.contains("\\in Data"))
            if scenario.name == "Upstream" {
                #expect(count == 3)
                #expect(rendered.tlaBundle.cfg.contains("CONSTANT Data = {d1, d2, d3}"))
            } else {
                #expect(count == 2)
                #expect(rendered.tlaBundle.cfg.contains("CONSTANT Data = {\"d1_OF_DATUM\", \"d2_OF_DATUM\"}"))
            }
        }
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try AsynchInterfaceModel.Configuration(Data: [.d1, .ap1])
        }
    }
}
