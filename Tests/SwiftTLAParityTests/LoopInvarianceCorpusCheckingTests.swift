import Testing
import SwiftTLA
import UpstreamParity

struct LoopInvarianceCorpusCheckingTests {
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
