import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct ChannelCorpusStateGraphTests {
    @Test("Channel pins each upstream wrapper and resolves its model-owned scenario")
    func pinsIndependentReferences() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declarations = manifest.cases.filter { $0.sourceModel == .channel }
        #expect(Set(declarations.map(\.id)) == ["channel", "ap-channel", "ap-channel-composing", "ap-channel-fifo"])
        for declaration in declarations {
            #expect(try declaration.resolveScenario()?.name == declaration.scenario)
            let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.module))
            let configuration = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.configuration))
            #expect(SHA256.hex(module) == declaration.moduleSHA256)
            #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
            if declaration.id != "channel" {
                #expect(declaration.imports == ["channel/Channel.tla"])
            }
        }
        let channel = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/channel/Channel.tla"))
        #expect(SHA256.hex(channel) == "8b2cbd4533a157ae0760e3117e3c008fb9a31dc3673005fc8b537d3879de1bfc")
    }

    @Test("Channel configurations retain complete graphs, invariants, deadlock checks, and formal value tags")
    func preservesConfiguredGraphs() throws {
        let scenarios = try ChannelModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["Upstream", "APChannel"])
        for scenario in scenarios {
            let count = scenario.configuration.Data.count
            let run = try NativeScenarioRun(scenario, maximumStates: 100)
            try run.validateExpectations()
            #expect(run.coverage.coversCompleteScenario)
            #expect(run.native.graph.graph.initialStateKeys.count == 2 * count)
            #expect(run.native.graph.graph.states.count == 4 * count)
            #expect(run.native.graph.graph.edges.count == 2 * count * (count + 1))
            #expect(run.native.checks.deadlock == .satisfied)
            #expect(run.native.checks.properties == ["TypeInvariant": .satisfied])
            let rendered = try scenario.render()
            #expect(rendered.checksDeadlock)
            #expect(rendered.checkNames == ["TypeInvariant"])
            if scenario.name == "Upstream" {
                #expect(count == 3)
                #expect(rendered.tlaBundle.cfg.contains("CONSTANT Data = {d1, d2, d3}"))
            } else {
                #expect(count == 2)
                #expect(rendered.tlaBundle.cfg.contains("CONSTANT Data = {\"d1_OF_DATUM\", \"d2_OF_DATUM\"}"))
            }
        }
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            try ChannelModel.Configuration(Data: [.d1, .ap1])
        }
    }
}
