import Testing
import SwiftTLA

struct DecisiveCheckingTests {
    @Test("an infinite native graph yields a complete shortest invariant counterexample")
    func stopsAtInvariant() throws {
        let scenario = try #require(DecisiveCounter.validationScenarios().first { $0.name == "Infinite" })
        guard case .counterexample(let result) = try scenario.check(maximumStates: 3) else {
            Issue.record("Expected a decisive invariant result, not graph exhaustion")
            return
        }
        #expect(result.violations == [.invariant(.belowThree)])
        #expect(result.trace.map { $0.state.state.value } == [0, 2, 3])
        #expect(result.trace.map(\.action) == [nil, .jump, .advance])
        #expect(result.unevaluatedProperties == [.nonnegative])
        #expect(throws: ExplorationError.stateLimitExceeded(3)) {
            _ = try scenario.explore(maximumStates: 3)
        }
    }

    @Test("an initial violation requires no successor exploration")
    func stopsAtInitialState() throws {
        let scenario = try #require(DecisiveCounter.validationScenarios().first { $0.name == "Initial violation" })
        guard case .counterexample(let result) = try scenario.check(maximumStates: 1) else {
            Issue.record("Expected an initial-state counterexample")
            return
        }
        #expect(result.violations == [.invariant(.belowThree)])
        #expect(result.trace.count == 1)
        #expect(result.trace.first?.action == nil)
        #expect(result.trace.first?.state.state.value == 3)
    }

    @Test("deadlock selection distinguishes a decisive failure from graph exhaustion")
    func preservesDeadlockSelection() throws {
        let scenarios = try DecisiveCounter.validationScenarios()
        let deadlock = try #require(scenarios.first { $0.name == "Deadlock" })
        guard case .counterexample(let result) = try deadlock.check(maximumStates: 3) else {
            Issue.record("Expected a deadlock counterexample")
            return
        }
        #expect(result.violations == [.deadlock])
        #expect(result.trace.map { $0.state.state.value } == [0, 2])
        #expect(result.unevaluatedProperties == deadlock.checking.properties)
        let exhaustive = try #require(scenarios.first { $0.name == "Exhaustive" })
        guard case .exhausted(let graph) = try exhaustive.check(maximumStates: 3) else {
            Issue.record("Disabled deadlock checking must permit exhaustion")
            return
        }
        #expect(graph.transitions.count == 3)
        #expect(graph.safetyViolations.isEmpty)
        #expect(graph.temporalResults[.nonnegative] != nil)
    }

    @Test("disabled invariants and resource cutoffs cannot produce counterexample success")
    func preservesIncompleteResults() throws {
        let scenario = try #require(DecisiveCounter.validationScenarios().first { $0.name == "Infinite" })
        #expect(throws: ExplorationError.stateLimitExceeded(3)) {
            _ = try ReachabilityGraph.check(initialMachines: scenario.initialMachines(), maximumStates: 3,
                                            checking: .init(properties: [], checkDeadlock: false))
        }
        #expect(throws: ExplorationError.invalidStateLimit(0)) {
            _ = try scenario.check(maximumStates: 0)
        }
    }

    @Test("a constraint-excluded violation retains its complete incoming trace")
    func preservesBoundaryWitness() throws {
        let scenario = try #require(DecisiveConstraintCounter.validationScenarios().first)
        guard case .counterexample(let result) = try scenario.check(maximumStates: 2) else {
            Issue.record("A state constraint must not hide an invariant violation")
            return
        }
        #expect(result.violations == [.invariant(.belowTwo)])
        #expect(result.trace.map { $0.state.state.value } == [0, 1, 2])
    }
}
