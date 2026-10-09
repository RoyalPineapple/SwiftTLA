import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct EWD840AnimationCorpusExecutionTests {
    @Test("animated TLC case declares and pins its community-module closure")
    func pinnedSimulationInputs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "ewd840-anim-0" })
        #expect(declaration.comparisonMode == .simulation)
        #expect(declaration.imports.contains("ewd840/IOUtils.tla"))
        #expect(declaration.dependencies.contains {
            $0.importingModule == "SVG" && $0.importedModule == "IOUtils"
        })
        let fixtures = root.appendingPathComponent("Verification/FiniteGraph/fixtures")
        let pinnedHelpers = [
            "ewd840/SVG.tla": "a4d127c92ebc756b9f5c4bee354fd474f83a612e188915989212d197ab17747a",
            "ewd840/IOUtils.tla": "c107b97b6fa302f0c84855eaa8b6b6cd536710302e7e2e5ebbbbbd47accad4ad",
            "ewd840/SequencesExt.tla": "c1917953561b54bc70b0d4d9580e3357df2df03e9cbceb22fa4de221166c1333",
            "die-hardest/FiniteSetsExt.tla": "dc5d6944395dd18e2f8acf696296808a9460cbbf1b9888f88c5ac4c83a5237f9",
            "kvsnap/Folds.tla": "aa59063fd600bb640b2ae24dc85ef770277ef5bf7955092b76b8b471790086da",
            "kvsnap/Functions.tla": "b54ff63b7c76c327525c17c188d5f9f5e53d92f3fd701f5e2ba54f0f54391063"
        ]
        for (path, digest) in pinnedHelpers {
            let source = try Data(contentsOf: fixtures.appendingPathComponent(path))
            #expect(SHA256.hex(source) == digest)
        }
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

    @Test("the published nine-node simulation finds its selected safety witness")
    func sampledExpectedFailure() throws {
        let scenario = try #require(EWD840AnimationModel.validationScenarios().first)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let result = try NativeValidationRunner.run(scenario: scenario,
            caseID: "ewd840-anim-0", maximumStates: 10_000_000, to: output)
        #expect(!result.graphComplete)
        #expect(result.properties == ["AnimInv": .violated])
        #expect(result.deadlock == nil)
        try NativeValidationRunner.verifySampledWitness(scenario: scenario,
            caseID: "ewd840-anim-0", report: result, in: output)
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
