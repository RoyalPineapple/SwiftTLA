import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct DieHarderCorpusStateGraphTests {
    @Test("DieHarder reference declarations pin both original configurations and their shared module")
    func pinsIndependentReferences() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declarations = manifest.cases.filter { $0.sourceModel == .dieHarder }
        #expect(Set(declarations.map(\.scenario)) == ["MCDieHarder", "APDieHarder"])
        for declaration in declarations {
            #expect(try declaration.resolveScenario()?.name == declaration.scenario)
            let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.module))
            let configuration = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.configuration))
            #expect(SHA256.hex(module) == declaration.moduleSHA256)
            #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
            #expect(declaration.imports == ["die-harder/DieHarder.tla"])
        }
        let shared = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/die-harder/DieHarder.tla"))
        #expect(SHA256.hex(shared) == "01a2593d58bb383bdb2a8b36f8838ab2bfbe87dc9e00c94c5755c20db4e4a404")
    }

    @Test("DieHarder configurations retain complete labeled graphs and upstream check selections")
    func preservesConfiguredGraphs() throws {
        let scenarios = try DieHarderModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["MCDieHarder", "APDieHarder"])
        for scenario in scenarios {
            let run = try NativeScenarioRun(scenario, maximumStates: 100)
            try run.validateExpectations()
            let exhaustive = try NativeModelRun(scenario.explore(maximumStates: 100), rendered: scenario.render())
            #expect(exhaustive.graph.graph.states.count == 16)
            #expect(exhaustive.graph.graph.edges.count == 96)
            #expect(exhaustive.checks.deadlock == .satisfied)
            #expect(exhaustive.checks.properties["TypeOK"] == .satisfied)
            let rendered = try scenario.render()
            #expect(rendered.checksDeadlock)
            #expect(rendered.tlaBundle.tla.contains("DOMAIN contents"))
            #expect(!rendered.tlaBundle.tla.contains("VARIABLES pc"))
            if scenario.name == "MCDieHarder" {
                #expect(run.coverage.coversCompleteScenario)
                #expect(rendered.checkNames == ["TypeOK", "NotSolved"])
                guard case .violated(let trace) = run.native.checks.properties["NotSolved"] else {
                    Issue.record("Expected the upstream solution counterexample")
                    continue
                }
                try trace.validate(in: exhaustive.graph.graph)
                #expect(run.native.graph == nil)
                #expect(run.native.checks.deadlock == .unavailable)
                #expect(run.native.checks.properties["TypeOK"] == .unavailable)
            } else {
                #expect(!run.coverage.coversCompleteScenario)
                #expect(run.coverage.omittedProperties == ["NotSolved"])
                #expect(rendered.checkNames == ["TypeOK"])
                #expect(run.native.checks.properties["NotSolved"] == nil)
                #expect(run.native.graph == exhaustive.graph)
                #expect(run.native.checks.deadlock == .satisfied)
                #expect(run.native.checks.properties["TypeOK"] == .satisfied)
            }
        }
    }

    @Test("pouring preserves the captured amount and uses generated typed arguments")
    func preservesOrderedPouring() throws {
        let scenario = try #require(DieHarderModel.validationScenarios().first)
        var machine = try DieHarderModel.makeMachine(configuration: scenario.configuration)
        _ = try machine.send(.FillJug(j: "j2"))
        _ = try machine.send(.JugToJug(j: "j2", k: "j1"))
        #expect(machine.state.contents == ["j1": 3, "j2": 2])
        _ = try machine.send(.EmptyJug(j: "j1"))
        _ = try machine.send(.JugToJug(j: "j2", k: "j1"))
        #expect(machine.state.contents == ["j1": 2, "j2": 0])
        _ = try machine.send(.FillJug(j: "j2"))
        _ = try machine.send(.JugToJug(j: "j2", k: "j1"))
        #expect(machine.state.contents == ["j1": 3, "j2": 4])
    }
}
