import Testing
@testable import SwiftTLA

struct TemporalConjunctionTests {
    private var checker: LivenessChecker<Int, Int, Int> {
        LivenessChecker(states: [0, 1], transitions: [
            0: [.init(source: 0, action: 0, target: 1)],
            1: [.init(source: 1, action: 0, target: 0)]
        ], fairness: [(scope: 0, isStrong: false)], matches: { $0 == $1 },
            actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    }

    @Test("recurring progress for each member does not require simultaneous progress")
    func independentRecurrence() throws {
        let property: TemporalCondition<@Sendable (Int, Int) throws -> Bool> = .all([
            .alwaysEventually { state, _ in state == 0 }, .all([.alwaysEventually { state, _ in state == 1 }])
        ])
        let result = try checker.analyze(property, initialStates: [0], renderScope: { _ in "advance" })
        #expect(result.status == .satisfied)
        #expect(result.enabledActions["advance"] == [0: true, 1: true])
        let simultaneous = try checker.analyze(.alwaysEventually { state, _ in state == 0 && state == 1 },
            initialStates: [0], renderScope: { _ in "advance" })
        #expect(simultaneous.status == .violated)
    }

    @Test("one false conjunct retains a counterexample for the complete property")
    func counterexample() throws {
        let result = try checker.analyze(.all([.eventually { state, _ in state == 1 }, .eventually { state, _ in state == 2 }]),
            initialStates: [0], renderScope: { _ in "advance" })
        #expect(result.status == .violated)
        let witness = try #require(result.witness)
        #expect(witness.prefix.first == 0)
        #expect(witness.cycle.first == witness.cycle.last)
        #expect(witness.cycle.allSatisfy { $0 != 2 })
    }

    @Test("empty conjunction is true only after complete valid exploration")
    func emptyConjunction() throws {
        #expect(try checker.analyze(.all([]), initialStates: [0], renderScope: { _ in "advance" }).status == .satisfied)
        let incomplete = try checker.analyze(.all([]), initialStates: [0], isComplete: false, renderScope: { _ in "advance" })
        #expect(incomplete.status == .unavailable)
        #expect(incomplete.reason == .incompleteExploration)
    }
}
