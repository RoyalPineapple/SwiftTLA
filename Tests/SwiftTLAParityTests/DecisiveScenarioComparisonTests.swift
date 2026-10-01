import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct DecisiveScenarioComparisonTests {
    @Test("targeted reachability shares BFS transitions and retains witnesses before the state limit")
    func boundsReachabilitySearch() throws {
        let initial = try TraceReplayQueries.initialMachines()
        let first = try #require(try ReachabilityGraph<TraceReplayQueries>.reachabilityWitness(
            initialMachines: initial, property: .Started, maximumStates: 1))
        #expect(first.map { $0.state.state.x } == [0])
        let later = try #require(try ReachabilityGraph<TraceReplayQueries>.reachabilityWitness(
            initialMachines: initial, property: .Later, maximumStates: 4))
        #expect(later.map { $0.state.state.x } == [0, 1, 2, 3, 4])
        #expect(throws: ExplorationError.stateLimitExceeded(3)) {
            try ReachabilityGraph<TraceReplayQueries>.reachabilityWitness(
                initialMachines: initial, property: .Later, maximumStates: 3)
        }
        #expect(throws: ExplorationError.self) {
            try ReachabilityGraph<TraceReplayQueries>.reachabilityWitness(
                initialMachines: initial, property: .BelowThree, maximumStates: 4)
        }
    }

    @Test("initial invariant failures use the pinned TLC diagnostic and retain the full one-state witness")
    func comparesInitialFailure() throws {
        let scenario = try #require(TraceReplayInitialFailure.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 1)
        guard case .counterexample(let native) = run.native else {
            Issue.record("Expected an initial counterexample")
            return
        }
        let data = Data(#"{"vars":["x"],"counterexample":{"state":[[1,{"x":3}]],"action":[]}}"#.utf8)
        let comparison = try native.compare(data: data, outcome: .safetyViolation,
            stdout: "Error: Invariant BelowThree is violated by the initial state:\n")
        try run.validateCounterexample(comparison)
        #expect(run.native.graph == nil)
    }

    @Test("a decisive deadlock comparison checks the final state's generated successors")
    func comparesDeadlock() throws {
        let scenario = try #require(TraceReplayDeadlock.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 1)
        guard case .counterexample(let native) = run.native else {
            Issue.record("Expected a deadlock counterexample")
            return
        }
        let data = Data(#"{"vars":["x"],"counterexample":{"state":[[1,{"x":0}]],"action":[]}}"#.utf8)
        let comparison = try native.compare(data: data, outcome: .deadlock, stdout: "Error: Deadlock reached.\n")
        try run.validateCounterexample(comparison)
        #expect(comparison.check == .deadlock)
        #expect(run.native.graph == nil)
    }

    @Test("an infinite scenario compares a complete counterexample without requiring a graph")
    func comparesDecisiveTrace() throws {
        let scenario = try #require(TraceReplayCounter.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 3)
        guard case .counterexample(let native) = run.native else {
            Issue.record("Expected decisive checking")
            return
        }
        #expect(run.native.graph == nil)
        #expect(native.checks.deadlock == .unavailable)
        let comparison = try native.compare(data: decisiveTraceData(), outcome: .safetyViolation,
            stdout: "Error: Invariant BelowThree is violated.\n")
        try run.validateCounterexample(comparison)
        guard case .violated(let trace) = comparison.tlcResult else {
            Issue.record("Missing full TLC witness")
            return
        }
        #expect(trace.steps.count == 4)
        #expect(trace.steps.last?.state == CanonicalState(bindings: ["x": .integer(3)]).key)
        for outcome in [TLCExecutionOutcome.completed, .failed(exitStatus: 255), .deadlock, .livenessViolation] {
            #expect(throws: EvidenceFormatError.self) {
                try native.compare(data: decisiveTraceData(), outcome: outcome,
                    stdout: "Error: Invariant BelowThree is violated.\n")
            }
        }
        #expect(throws: EvidenceFormatError.self) {
            try native.compare(data: decisiveTraceData(), outcome: .safetyViolation,
                stdout: "Error: Invariant Different is violated.\n")
        }
    }

    @Test("trace replay rejects noninitial states, invalid transitions, labels, and incomplete witnesses")
    func rejectsInvalidTraces() throws {
        let initial = try TraceReplayCounter.initialMachines()
        let actions = try TraceReplayCounter.render().actions
        let original = String(decoding: try decisiveTraceData(), as: UTF8.self)
        for text in [original.replacingOccurrences(of: "\"x\":0", with: "\"x\":1"),
                     original.replacingOccurrences(of: "\"x\":2", with: "\"x\":9"),
                     original.replacingOccurrences(of: "\"Next\"", with: "\"Unknown\""),
                     String(original.dropLast(2))] {
            #expect(throws: TLCTraceError.self) {
                try TLCTraceParser().replayCounterexample(Data(text.utf8), initialMachines: initial,
                    renderedActions: actions, maximumStates: 100, checkingDeadlock: false)
            }
        }
    }
}
