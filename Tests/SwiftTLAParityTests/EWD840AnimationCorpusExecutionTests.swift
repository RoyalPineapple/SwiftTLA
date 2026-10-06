import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct EWD840AnimationCorpusExecutionTests {
    @Test("animated TLC case declares its full dependency closure and pins SVG")
    func pinnedSimulationInputs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "ewd840-anim-0" })
        #expect(declaration.comparisonMode == .simulation)
        let fixtures = root.appendingPathComponent("Verification/FiniteGraph/fixtures")
        let svg = try Data(contentsOf: fixtures.appendingPathComponent("ewd840/SVG.tla"))
        #expect(SHA256.hex(svg) == "a4d127c92ebc756b9f5c4bee354fd474f83a612e188915989212d197ab17747a")
        let bundle = try TLCProcessRequest.declaredBundle(
            root: fixtures.appendingPathComponent(declaration.module),
            configuration: fixtures.appendingPathComponent(declaration.configuration),
            imports: declaration.imports.map { fixtures.appendingPathComponent($0) },
            dependencies: declaration.dependencies.enumerated().map { index, edge in
                .init(importingModule: edge.importingModule,
                    importedModule: edge.importedModule,
                    structuralPath: [declaration.id, "dependencies", String(index)])
            })
        try bundle.validateDeclaredClosure()
        #expect(try declaration.resolveScenario()?.name == "EWD840_anim")
    }

    @Test("animated upstream configuration remains model-owned and bounded")
    func simulationConfiguration() throws {
        let scenario = try #require(EWD840AnimationModel.validationScenarios().first)
        #expect(scenario.name == "EWD840_anim")
        #expect(scenario.configuration.N == 9)
        #expect(scenario.checkingMode == .simulation(traces: 100, maximumDepth: 100))
        #expect(scenario.checking.properties == [.AnimInv])
        #expect(!scenario.checking.checkDeadlock)
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.cfg.contains("N = 9"))
        #expect(rendered.checkNames == ["AnimInv"])
        #expect(!rendered.checksDeadlock)
    }

    @Test("animated steps preserve typed history and render the level check")
    func generatedHistoryAndCheck() throws {
        let configuration = try EWD840AnimationModel.Configuration(N: 2)
        let initial = try EWD840AnimationModel.initialMachines(configuration: configuration)
        #expect(initial.count == 16)
        var machine = try #require(initial.first {
            $0.state.active[0] == true && $0.state.active[1] == false
        })
        #expect(machine.state.tpos == 1)
        #expect(machine.state.history == Triple(first: 0, second: 0, third: "init"))

        _ = try machine.send(.AnimSendMsg(i: 0))
        #expect(machine.state.active[1] == true)
        #expect(machine.state.color[0] == .black)
        #expect(machine.state.history == Triple(first: 0, second: 1, third: "SendMsg"))

        _ = try machine.send(.AnimDeactivate(i: 1))
        #expect(machine.state.active[1] == false)
        #expect(machine.state.history == Triple(first: 0, second: 1, third: "Deactivate"))

        _ = try machine.send(.AnimPassToken(i: 1))
        #expect(machine.state.tpos == 0)
        #expect(machine.state.history == Triple(first: 0, second: 1, third: "PassToken"))

        _ = try machine.send(.AnimInitiateProbe)
        #expect(machine.state.tpos == 1)
        #expect(machine.state.history == Triple(first: 0, second: 1, third: "InitiateProbe"))

        let rendered = try EWD840AnimationModel.render(configuration: configuration)
        #expect(rendered.tlaBundle.root.tla.contains("EXTENDS Integers, Naturals, TLC"))
        #expect(rendered.tlaBundle.root.tla.contains("TLCGet(\"level\")"))
        #expect(rendered.checkNames.contains("AnimInv"))
    }
}
