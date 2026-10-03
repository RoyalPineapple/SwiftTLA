import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct DieHardestCorpusCheckingTests {
    @Test("Global freeze keeps the faster instance at its shortest solution while the slower finishes")
    func checksGlobalFreeze() throws {
        let scenario = try #require(DieHardestGlobalFreezeModel.validationScenarios().first)
        guard case .counterexample(let result) = try scenario.check(maximumStates: 100_000) else {
            Issue.record("Global freeze must find the upstream running example's solution")
            return
        }
        #expect(result.trace.count == 7)
        #expect(result.violations == [.invariant(.NotSolved)])
        let states = result.trace.map { $0.state.state }
        #expect(states.allSatisfy { $0.s1 == 0 && $0.s2 == 0 })
        #expect(states[2].c2.values.contains(2))
        #expect(states.dropFirst(2).allSatisfy { $0.c2 == states[2].c2 })
        #expect(try #require(states.last).c1.values.contains(2))
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.tla.contains("TLCGet(\"level\")"))
        #expect(!rendered.tlaBundle.cfg.contains("CONSTRAINT"))
    }

    @Test("Global-freeze trace replay includes register writes outside the reported path")
    func replaysGlobalExploration() throws {
        let scenario = try #require(DieHardestGlobalFreezeModel.validationScenarios().first)
        guard case .counterexample(let result) = try scenario.check(maximumStates: 100_000) else {
            Issue.record("Expected global-freeze counterexample")
            return
        }
        let rendered = try scenario.render()
        let initial = try DieHardestGlobalFreezeModel.initialMachines(configuration: scenario.configuration)
        func data(_ states: [DieHardestGlobalFreezeModel.State]) throws -> Data {
            let encoded: [[Any]] = states.enumerated().map { index, state in
                [index + 1, ["c1": state.c1, "c2": state.c2, "s1": state.s1, "s2": state.s2] as [String: Any]]
            }
            let actions: [[Any]] = encoded.indices.dropFirst().map { index in
                [encoded[index - 1], ["name": "NextParallelGlobalFreeze"], encoded[index]]
            }
            return try JSONSerialization.data(withJSONObject: ["vars": ["c1", "c2", "s1", "s2"],
                "counterexample": ["state": encoded, "action": actions]])
        }
        let states = result.trace.map { $0.state.state }
        let replay = try TLCTraceParser().replayCounterexample(data(states), initialMachines: initial,
            renderedActions: rendered.actions, maximumStates: 100_000, checkingDeadlock: false)
        #expect(replay.trace.steps.count == 7)
        #expect(replay.final.state == states.last)
        let fastCopy = [[0, 0], [1, 0], [1, 0], [0, 0], [0, 3], [1, 2], [1, 2]]
        let delayed = states.enumerated().map { index, state in
            DieHardestGlobalFreezeModel.State(c1: state.c1,
                c2: ["j1": fastCopy[index][0], "j2": fastCopy[index][1]], s1: state.s1, s2: state.s2)
        }
        #expect(throws: TLCTraceError.self) {
            try TLCTraceParser().replayCounterexample(data(delayed), initialMachines: initial,
                renderedActions: rendered.actions, maximumStates: 100_000, checkingDeadlock: false)
        }
    }

    @Test("Global freeze selects the unchanged upstream operator through a local configuration harness")
    func selectsGlobalFreezeReference() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declaration = try #require(manifest.cases.first { $0.id == "die-hardest-global-freeze" })
        #expect(declaration.comparisonMode == .decisiveCounterexample)
        #expect(try declaration.resolveScenario()?.name == "NextParallelGlobalFreeze")
        let root = projectURL("Verification/FiniteGraph/fixtures")
        #expect(SHA256.hex(try Data(contentsOf: root.appendingPathComponent(declaration.module))) == declaration.moduleSHA256)
        #expect(SHA256.hex(try Data(contentsOf: root.appendingPathComponent(declaration.configuration))) == declaration.cfgSHA256)
        let upstream = try Data(contentsOf: root.appendingPathComponent("die-hardest/DieHardest.tla"))
        #expect(SHA256.hex(upstream) == declaration.sourceInput?.sha256)
        let configuration = try String(contentsOf: root.appendingPathComponent(declaration.configuration), encoding: .utf8)
        #expect(configuration.contains("NEXT NextParallelGlobalFreeze"))
        #expect(!configuration.contains("CONSTRAINT"))
    }

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
