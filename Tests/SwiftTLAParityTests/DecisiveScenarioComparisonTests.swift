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

    @Test("reachability witnesses do not mask a later safety counterexample or establish unanswered queries",
        arguments: ReachabilityTraceExecutor.Fault.allCases)
    func retainsMixedQueryResults(fault: ReachabilityTraceExecutor.Fault) throws {
        let scenario = try #require(TraceReplayQueries.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 3)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let bundle = run.native.rendered.tlaBundle
        let launch = try FiniteGraphCase(id: "mixed-queries",
            exploration: .init(maximumStateLimit: 3, symmetryReduction: .disabled),
            moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)), cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
            arguments: ["-workers", "1", "-fp", "1"], environment: [:], pin: testReferencePin(),
            renderedActions: run.native.rendered.actions)
        let request = TLCProcessRequest(javaExecutable: root.appendingPathComponent("java"),
            jar: root.appendingPathComponent("tlc.jar"), bridgeJar: root.appendingPathComponent("bridge.jar"),
            bundle: bundle, graphEvents: work.appendingPathComponent("events.jsonl"),
            traceOutput: work.appendingPathComponent("counterexample.json"), workingDirectory: work,
            finiteGraphCase: launch, runID: UUID(), timeout: 1, invocation: .propertyCheck)
        let output = root.appendingPathComponent("evidence")
        let checker = TLCScenarioCheck(processAdapter: .init(executor: ReachabilityTraceExecutor(fault: fault)))
        if fault == .none {
            try checker.run(run, request: request, in: output)
            let data = try Data(contentsOf: output.appendingPathComponent("native-checks.json"))
            let checks = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let properties = try #require(checks["properties"] as? [String: [String: Any]])
            #expect(properties["Started"]?["status"] as? String == "reached")
            #expect(properties["ReachedTwo"]?["status"] as? String == "reached")
            #expect(properties["Later"]?["status"] as? String == "unavailable")
            #expect(properties["BelowThree"]?["status"] as? String == "violated")
            let queries = try #require(JSONSerialization.jsonObject(with:
                Data(contentsOf: output.appendingPathComponent("reachability-comparisons.json"))) as? [[String: Any]])
            #expect(queries.count == 2)
            #expect(try String(contentsOf: output.appendingPathComponent("result.txt"), encoding: .utf8) == "exact\n")
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("decisive-check-2/counterexample.json").path))
        } else {
            #expect(throws: (any Error).self) { try checker.run(run, request: request, in: output) }
            #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("result.txt").path))
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("reachability-comparisons.json").path))
        }
        #expect(run.native.graph == nil)
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("swift-graph.jsonl").path))
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
                    renderedActions: actions)
            }
        }
    }

    @Test("the scenario runner retains decisive evidence and rejects process failure", arguments: [Int32(12), 255])
    func retainsRunnerEvidence(exitStatus: Int32) throws {
        let scenario = try #require(TraceReplayCounter.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 3)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let output = root.appendingPathComponent("evidence")
        let bundle = run.native.rendered.tlaBundle
        let launch = try FiniteGraphCase(id: "decisive",
            exploration: .init(maximumStateLimit: 3, symmetryReduction: .disabled),
            moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)), cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
            arguments: ["-workers", "1", "-fp", "1"], environment: [:], pin: testReferencePin(),
            renderedActions: run.native.rendered.actions)
        let request = TLCProcessRequest(javaExecutable: root.appendingPathComponent("java"),
            jar: root.appendingPathComponent("tlc.jar"), bridgeJar: root.appendingPathComponent("bridge.jar"),
            bundle: bundle, graphEvents: work.appendingPathComponent("events.jsonl"),
            traceOutput: work.appendingPathComponent("counterexample.json"), workingDirectory: work,
            finiteGraphCase: launch, runID: UUID(), timeout: 1, invocation: .propertyCheck)
        let checker = TLCScenarioCheck(processAdapter: .init(executor: DecisiveTraceExecutor(exitStatus: exitStatus)))
        if exitStatus == 12 {
            try checker.run(run, request: request, in: output)
            #expect(try String(contentsOf: output.appendingPathComponent("completion.txt"), encoding: .utf8)
                == "decisive-counterexample\n")
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("counterexample-comparison.json").path))
        } else {
            #expect(throws: EvidenceFormatError.self) { try checker.run(run, request: request, in: output) }
            #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("result.txt").path))
        }
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("swift-graph.jsonl").path))
        #expect(try Data(contentsOf: output.appendingPathComponent("decisive-check/counterexample.json")) == decisiveTraceData())
    }
}
