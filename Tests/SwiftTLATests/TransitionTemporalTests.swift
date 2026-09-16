import Testing
@testable import SwiftTLA

struct TransitionTemporalTests {
    private enum PredicateError: Error { case evaluated }

    private func checker() -> LivenessChecker<Int, Int, Int> {
        .init(states: [0, 1, 2, 10, 11, 99], transitions: [
            0: [.init(source: 0, action: 0, target: 1)],
            1: [.init(source: 1, action: 1, target: 2)],
            10: [.init(source: 10, action: 0, target: 11)]
        ], fairness: [(1, false)], matches: { $0 == $1 },
            actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    }

    @Test("Transition predicates retain a violating edge and its fair continuation")
    func retainsEdgeWitness() throws {
        let result = try checker().analyzeAlwaysTransition({ before, after in
            before == after || before != 0
        }, initialStates: [0], renderScope: String.init)
        #expect(result.status == .violated)
        let witness = try #require(result.witness)
        #expect(witness.prefix == [0, 1, 2])
        #expect(witness.prefixActions == [0, 1])
        #expect(witness.cycle == [2, 2])
        #expect(witness.cycleActions == [nil])
    }

    @Test("Implicit stuttering remains subject to the declared transition predicate")
    func checksStuttering() throws {
        let result = try checker().analyzeAlwaysTransition({ before, after in before != after },
            initialStates: [1], renderScope: String.init)
        #expect(result.status == .violated)
        let witness = try #require(result.witness)
        #expect(zip(witness.prefix, witness.prefix.dropFirst()).contains { $0 == $1 })
        #expect(witness.prefixActions.contains(nil))
        #expect(witness.prefix.contains(2))
    }

    @Test("Transition properties preserve each initial root and ignore unreachable states")
    func preservesReachability() throws {
        let result = try checker().analyzeAlwaysTransition({ before, after in
            if before == 99 { throw PredicateError.evaluated }
            return before == after || before != 10
        }, initialStates: [0, 10], renderScope: String.init)
        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [10, 11])
        #expect(result.witness?.prefixActions == [0])
        #expect(try checker().analyzeAlwaysTransition({ before, after in before <= after },
            initialStates: [0, 10], renderScope: String.init).status == .satisfied)
    }

    @Test("Incomplete transition graphs stay unavailable and predicate failures propagate")
    func preservesFailures() throws {
        let result = try checker().analyzeAlwaysTransition({ _, _ in throw PredicateError.evaluated },
            initialStates: [0], isComplete: false, renderScope: String.init)
        #expect(result.status == .unavailable)
        #expect(result.reason == .incompleteExploration)
        #expect(throws: PredicateError.self) {
            try checker().analyzeAlwaysTransition({ _, _ in throw PredicateError.evaluated },
                initialStates: [0], renderScope: String.init)
        }
    }
}
