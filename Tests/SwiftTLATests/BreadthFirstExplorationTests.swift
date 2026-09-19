import Testing
import SwiftTLA

struct BreadthFirstExplorationTests {
    @Test("Expanding frontiers preserve every edge and shortest traces from all initial states",
        arguments: [false, true])
    func preservesCompleteGraph(additionalRoot: Bool) throws {
        var initial = [try ConvergingFrontiers.makeMachine(.init(node: 1))]
        if additionalRoot { initial.append(try ConvergingFrontiers.makeMachine(.init(node: 3))) }
        let graph = try ReachabilityGraph(initialMachines: initial, maximumStates: 130)
        #expect(graph.initialStates == Set(initial.map(\.snapshot)))
        #expect(graph.transitions.count == 130)
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 130)
        for (source, edges) in graph.transitions {
            let node = source.state.node
            let expected: Set<Int> = node > 128 ? [] : (node == 3 || node == 128 ? [256] : [node * 2, node * 2 + 1])
            #expect(Set(edges.map { $0.target.state.node }) == expected)
            #expect(edges.allSatisfy { $0.action == .advance })
            #expect(graph.safetyViolations[source] == (expected.isEmpty ? [.deadlock] : nil))
        }
        #expect(graph.deadlockedStates.count == 64)
        let target = try #require(graph.transitions.keys.first { $0.state.node == 256 })
        #expect(try graph.trace(to: target).map { $0.state.state.node } == (additionalRoot ? [3, 256] : [1, 3, 256]))
        #expect(throws: ExplorationError.stateLimitExceeded(129)) {
            try ReachabilityGraph(initialMachines: initial, maximumStates: 129)
        }
    }
}
