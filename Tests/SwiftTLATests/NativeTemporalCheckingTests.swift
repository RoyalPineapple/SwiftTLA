import SwiftTLA
import SwiftTLAMacros
import Testing

struct NativeTemporalCheckingTests {
    @Test("Native temporal counterexamples retain replayable typed states and actions")
    func counterexampleRetainsTypedTransitions() throws {
        let machine = try UnreachableCounter.makeMachine()
        let graph = try ReachabilityGraph(initialMachines: [machine], maximumStates: 10)
        let results = graph.temporalResults
        let result = try #require(results[.ReachesTwo])
        #expect(result.status == .violated)
        #expect(result.reason == .violatingFairLasso)
        let trace = try #require(result.witness)
        #expect(graph.initialStates.contains(try #require(trace.prefix.first)))
        #expect(trace.cycle.first == trace.cycle.last)
        #expect(trace.cycleActions.contains(.advance))
        for (states, actions) in [(trace.prefix, trace.prefixActions), (trace.cycle, trace.cycleActions)] {
            #expect(states.count == actions.count + 1)
            for (source, step) in zip(states, zip(actions, states.dropFirst())) {
                let (action, target) = step
                if let action {
                    #expect(graph.transitions[source]?.contains { $0.action == action && $0.target == target } == true)
                } else {
                    #expect(source == target)
                }
            }
        }
    }
}

@TLAModel
private struct UnreachableCounter {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("UnreachableCounter") {
            Algorithm("Counter", fairness: .weak, scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                While(Step.advance, true) {
                    Assign(count, to: 1 - count)
                }
                Eventually("ReachesTwo", count == 2)
            })
        }
    }
}
