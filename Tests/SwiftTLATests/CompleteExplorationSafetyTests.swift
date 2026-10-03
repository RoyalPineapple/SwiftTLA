import Testing
import SwiftTLA

struct CompleteExplorationSafetyTests {
    @Test("complete native exploration retains every initial branch and safety failure")
    func preservesGraphAndAllSafetyChecks() throws {
        let scenario = try #require(CompleteExplorationSafetyModel.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 10)

        #expect(Set(graph.initialStates.map { $0.state.value }) == [0, 10])
        #expect(Set(graph.transitions.keys.map { $0.state.value }) == [0, 10, 11, 12, 13])
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 3)

        let failures = Dictionary(uniqueKeysWithValues: graph.safetyViolations.map {
            ($0.key.state.value, Set($0.value))
        })
        #expect(failures[0] == [.deadlock])
        #expect(failures[11] == [.invariant(.belowEleven)])
        #expect(failures[12] == [.invariant(.belowEleven)])
        #expect(failures[13] == [.invariant(.belowEleven), .invariant(.belowThirteen), .deadlock])

        let deadlockedRoot = try #require(graph.transitions.keys.first { $0.state.value == 0 })
        #expect(try graph.trace(to: deadlockedRoot).map { $0.state.state.value } == [0])
        let firstViolation = try #require(graph.transitions.keys.first { $0.state.value == 11 })
        let firstTrace = try graph.trace(to: firstViolation)
        #expect(firstTrace.map { $0.state.state.value } == [10, 11])
        #expect(firstTrace.map(\.action) == [nil, .advance])

        let last = try #require(graph.transitions.keys.first { $0.state.value == 13 })
        #expect(try graph.trace(to: last).map { $0.state.state.value } == [10, 11, 12, 13])
        #expect(throws: ExplorationError.stateLimitExceeded(4)) {
            _ = try scenario.explore(maximumStates: 4)
        }
    }
}
