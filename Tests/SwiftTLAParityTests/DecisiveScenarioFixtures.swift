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
            let infinite = Validation(label: "Infinite") {}.expect(BelowThree, .violated)
            infinite
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
            let initialFailure = Validation(label: "Initial failure") {}.expect(BelowThree, .violated)
            initialFailure
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
            let deadlock = Validation(label: "Deadlock") {}.expectDeadlock(.violated)
            deadlock
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
            let mixedQueries = Validation(label: "Mixed queries") {}.expect(BelowThree, .violated)
            mixedQueries
        }
    }
}

func decisiveTraceData() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/FiniteGraph/TLCTrace/violation-counterexample.json"))
}
