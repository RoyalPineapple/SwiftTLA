import Foundation
import SwiftTLA
import SwiftTLAMacros
import UpstreamParity

@TLAModel
struct TraceReplayCounter {
    enum Step: String, CaseIterable { case Next }
    static var spec: TLASpec {
        #spec("TraceReplayCounter") { scope in
            let x = scope.sharedVar(initial: 0)
            Do(Step.Next) { Assign(x, to: x + 1) }
            let BelowThree = Invariant()
            BelowThree { x < 3 }
            Validation("Infinite") {}.expect(BelowThree, .violated)
        }
    }
}

@TLAModel
struct TraceReplayInitialFailure {
    enum Step: String, CaseIterable { case Next }
    static var spec: TLASpec {
        #spec("TraceReplayInitialFailure") { scope in
            let x = scope.sharedVar(initial: 3)
            Do(Step.Next) { Assign(x, to: x + 1) }
            let BelowThree = Invariant()
            BelowThree { x < 3 }
            Validation("Initial failure") {}.expect(BelowThree, .violated)
        }
    }
}

@TLAModel
struct TraceReplayDeadlock {
    enum Step: String, CaseIterable { case Next }
    static var spec: TLASpec {
        #spec("TraceReplayDeadlock") { scope in
            let x = scope.sharedVar(initial: 0)
            Do(Step.Next, when: x < 0) { Assign(x, to: x + 1) }
            Validation("Deadlock") {}.expectDeadlock(.violated)
        }
    }
}

@TLAModel
struct TraceReplayQueries {
    enum Step: String, CaseIterable { case Next }
    static var spec: TLASpec {
        #spec("TraceReplayQueries") { scope in
            let x = scope.sharedVar(initial: 0)
            Do(Step.Next) { Assign(x, to: x + 1) }
            let BelowThree = Invariant()
            BelowThree { x < 3 }
            let Started = Reachable()
            Started { x == 0 }
            let ReachedTwo = Reachable()
            ReachedTwo { x == 2 }
            let Later = Reachable()
            Later { x == 4 }
            Validation("Mixed queries") {}.expect(BelowThree, .violated)
        }
    }
}

func decisiveTraceData() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/FiniteGraph/TLCTrace/violation-counterexample.json"))
}

struct DecisiveTraceExecutor: TLCProcessExecuting {
    let exitStatus: Int32
    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
        try decisiveTraceData().write(to: request.traceOutput)
        return .init(status: exitStatus, stdout: "Error: Invariant BelowThree is violated.\n", stderr: "")
    }
}

struct ReachabilityTraceExecutor: TLCProcessExecuting {
    enum Fault: CaseIterable, Sendable { case none, repeatedQuery, failedProcess }
    let fault: Fault

    func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
        let cfg = request.bundle.cfg
        guard cfg.contains("INVARIANT BelowThree\n"), cfg.contains("INVARIANT Later\n"),
              cfg.contains("CHECK_DEADLOCK TRUE\n") else { throw TLCPropertyCheckError.requestMismatch }
        let isInitial = cfg.contains("INVARIANT Started\n")
        if !isInitial && fault == .failedProcess {
            return .init(status: 255, stdout: "failed", stderr: "failed")
        }
        let name: String
        let transitions: Int
        if isInitial || fault == .repeatedQuery {
            name = "Started"
            transitions = 0
        } else if cfg.contains("INVARIANT ReachedTwo\n") {
            name = "ReachedTwo"
            transitions = 2
        } else {
            name = "BelowThree"
            transitions = 3
        }
        guard var source = try JSONSerialization.jsonObject(with: decisiveTraceData()) as? [String: Any],
              var counterexample = source["counterexample"] as? [String: Any],
              let states = counterexample["state"] as? [Any],
              let actions = counterexample["action"] as? [Any] else { throw TLCTraceError.malformedJSON }
        counterexample["state"] = Array(states.prefix(transitions + 1))
        counterexample["action"] = Array(actions.prefix(transitions))
        source["counterexample"] = counterexample
        try JSONSerialization.data(withJSONObject: source).write(to: request.traceOutput)
        let message = transitions == 0 ? "is violated by the initial state:" : "is violated."
        return .init(status: 12, stdout: "Error: Invariant \(name) \(message)\n", stderr: "")
    }
}
