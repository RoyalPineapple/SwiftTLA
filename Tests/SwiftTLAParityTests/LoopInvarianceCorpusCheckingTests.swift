import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct LoopInvarianceCorpusCheckingTests {
    @Test("LoopInvariance references resolve model-owned scenarios and preserve pinned inputs")
    func resolvesPinnedReferences() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let registered = try modelValidationScenarios()
        for (id, name) in [("binary-search", "MCBinarySearch"), ("quicksort", "MCQuicksort")] {
            let reference = try #require(manifest.cases.first { $0.id == id })
            #expect(reference.comparisonMode == .exhaustive)
            let scenario = try #require(try reference.resolveScenario())
            #expect(scenario.name == name)
            #expect(registered.contains { $0.id == id + "-0" && $0.scenario.name == name })
            let rendered = try scenario.render()
            #expect(rendered.checksDeadlock)
            #expect(rendered.checkNames.count == 4)
        }
        let expectedHashes = [
            "BinarySearch.tla": "fa56deb7c8d1cce2e5b9c4559ab7a1ced1fea5098edc46eb8d99c257e8eaecec",
            "MCBinarySearch.tla": "807264a6cb748cd4e36100c170f805840efe33ed39c7a0297d869250acb32cdb",
            "MCBinarySearch.cfg": "87ddb2c392f287e2d505890b54603147ecb899b826bbc124e5108a416b8ab6d6",
            "Quicksort.tla": "65c70e42eb28bef01e7754cffe66d87ac1d00b4cd27b107ce389da3f31ad7672",
            "MCQuicksort.tla": "1c1cb71fcd1a1cef070cff835516a1db57ed572bee83ea680bf186c4f57b9286",
            "MCQuicksort.cfg": "6d67c7f71645514928c26e204edfc3d56a7ccd529dd6f5e8b66254008c269dd7",
            "SequenceTheorems.tla": "1fdbed9077bba9db329e499535be29f8d2e6fba3a2b338e364c3b0ec56596bf9",
            "FiniteSetTheorems.tla": "484bf0f9ab6a69ef45f7282f7f92dcf1e6ae139e44117b0d5a4427635818e773",
            "NaturalsInduction.tla": "08f52420cdaaf11292ed366782b5ce5b596bb7cbe789526a1cfd8806dbf98624",
            "WellFoundedInduction.tla": "6f2f274c2e987d1edcf004d8e37b053f1f82b912e66d6a51bae0af8012ddcbec"
        ]
        for (name, hash) in expectedHashes {
            let file = projectURL("Verification/FiniteGraph/fixtures/loop-invariance/" + name)
            #expect(SHA256.hex(try Data(contentsOf: file)) == hash)
        }
    }

    @Test("MCQuicksort exhausts its native graph with every upstream property satisfied")
    func completeQuicksortGraph() throws {
        let scenario = try #require(QuicksortModel.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 10_000)
        try run.validateExpectations()
        let graph = try #require(run.native.graph)
        #expect(graph.isComparable)
        #expect(graph.graph.states.count == 4_548)
        #expect(run.coverage.omittedProperties.isEmpty)
        #expect(run.native.checks.properties == [
            "PCorrect": .satisfied, "TypeOK": .satisfied, "Inv": .satisfied, "Termination": .satisfied
        ])
        #expect(run.native.checks.deadlock == .satisfied)
    }

    @Test("MCBinarySearch exhausts its native graph with every upstream property satisfied")
    func completeBinarySearchGraph() throws {
        let scenario = try #require(BinarySearchModel.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 100_000)
        try run.validateExpectations()
        let graph = try #require(run.native.graph)
        #expect(graph.isComparable)
        #expect(graph.graph.states.count == 27_953)
        #expect(run.coverage.omittedProperties.isEmpty)
        #expect(run.native.checks.properties == [
            "resultCorrect": .satisfied, "TypeOK": .satisfied, "Inv": .satisfied, "Termination": .satisfied
        ])
        #expect(run.native.checks.deadlock == .satisfied)
    }

    @Test("MCQuicksort retains every pivot and duplicate-preserving partition")
    func preservesQuicksortChoices() throws {
        let scenario = try #require(QuicksortModel.validationScenarios().first)
        #expect(scenario.name == "MCQuicksort")
        let initial = try scenario.initialMachines()
        #expect(initial.count == 120)
        #expect(initial.allSatisfy { machine in
            let state = machine.state
            return (1...4).contains(state.seq.count) && state.seq == state.seq0
                && state.U == Set([Set(1...state.seq.count)])
                && state.seq.allSatisfy { (1...3).contains($0) }
        })
        let machine = try #require(initial.first { $0.state.seq == [2, 1, 2] })
        let successors = try machine.successors()
        #expect(successors.count == 3)
        #expect(successors.allSatisfy { $0.machine.state.seq0 == [2, 1, 2] })
        for (sequence, intervals) in [
            ([1, 2, 2], Set([Set([1]), Set([2, 3])])),
            ([1, 2, 2], Set([Set([1, 2]), Set([3])])),
            ([2, 1, 2], Set([Set([1, 2]), Set([3])]))
        ] {
            #expect(successors.contains { $0.machine.state.seq == sequence && $0.machine.state.U == intervals })
        }
        let rendered = try scenario.render()
        #expect(Set(rendered.checkNames) == Set(["PCorrect", "TypeOK", "Inv", "Termination"]))
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.tla.contains("WF_<<pc, seq, seq0, U>>(Next)"))
    }

    @Test("MCBinarySearch preserves positive sorted inputs and every selected property")
    func preservesBinarySearchConfiguration() throws {
        let scenario = try #require(BinarySearchModel.validationScenarios().first)
        #expect(scenario.name == "MCBinarySearch")
        let initial = try scenario.initialMachines()
        #expect(initial.count == 6_430)
        #expect(initial.allSatisfy { machine in
            let state = machine.state
            return (1...8).contains(state.seq.count)
                && state.seq == state.seq.sorted()
                && state.seq.allSatisfy { (1...5).contains($0) }
                && (1...5).contains(state.val)
                && state.low == 1 && state.high == state.seq.count && state.result == 0
        })
        let rendered = try scenario.render()
        #expect(Set(rendered.checkNames) == Set(["resultCorrect", "TypeOK", "Inv", "Termination"]))
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.tla.contains("WF_<<pc, seq, val, low, high, result>>(Next)"))
        #expect(rendered.tlaBundle.cfg.contains("PROPERTY Termination"))
    }
}
