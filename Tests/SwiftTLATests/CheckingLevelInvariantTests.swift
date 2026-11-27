import Testing
@testable import SwiftTLA

struct CheckingLevelInvariantTests {
    @Test("A snapshot that passed as an initial state can violate the same invariant at a later level")
    func rechecksAnInitialSnapshotReachedAtALaterLevel() throws {
        let initial = try CheckingLevelInvariantModel.makeMachine()
        var otherInitial = initial
        _ = try otherInitial.send(.advance)
        _ = try otherInitial.send(.advance)

        let result = try ReachabilityGraph.check(initialMachines: [initial, otherInitial], maximumStates: 3,
            checking: .init(properties: [.BeforeThirdState], checkDeadlock: false))
        guard case .counterexample(let failure) = result else {
            Issue.record("The third level must violate BeforeThirdState")
            return
        }
        #expect(failure.violations == [.invariant(.BeforeThirdState)])
        #expect(failure.trace.last?.state == otherInitial.snapshot)
    }

    @Test("Native invariant evaluation uses the discovered state's BFS level")
    func evaluatesDiscoveredLevel() throws {
        let initial = try CheckingLevelInvariantModel.makeMachine()
        #expect(try initial.violatedInvariants(atLevel: 1).isEmpty)
        var failures: [Int] = []
        let result = try MachineValidator.run(
            initialMachines: [initial], maximumStates: 3,
            checking: .init(properties: [.BeforeThirdState], checkDeadlock: false),
            stopOnViolation: false
        ) { event in
            if case .invariantFailure(_, let snapshot, _, _) = event {
                failures.append(snapshot.state.value)
            }
        }
        #expect(result.completion == .exhausted)
        #expect(result.states == 3)
        #expect(failures == [2])
    }

    @Test("Retained native graphs report the same level-dependent violation")
    func graphUsesDiscoveredLevel() throws {
        let initial = try CheckingLevelInvariantModel.makeMachine()
        let graph = try ReachabilityGraph(
            initialMachines: [initial], maximumStates: 3,
            checking: .init(properties: [.BeforeThirdState], checkDeadlock: false)
        )
        #expect(graph.transitions.count == 3)
        #expect(graph.safetyViolations.count == 1)
        #expect(graph.safetyViolations.first?.key.state.value == 2)
        #expect(graph.safetyViolations.first?.value == [.invariant(.BeforeThirdState)])
    }
}
