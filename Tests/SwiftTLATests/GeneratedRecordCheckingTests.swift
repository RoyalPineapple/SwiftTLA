import Testing
import SwiftTLA

struct GeneratedRecordCheckingTests {
    @Test("record-state checking preserves distinct choices and reached failures")
    func replaysCompleteGraph() throws {
        let machines = try GeneratedSwiftRecord.initialMachines()
        let initial = try #require(machines.first)
        #expect(machines.count == 1)
        let successors = try initial.successors().map(\.machine)
        #expect(successors.map { $0.state.packet.count }.sorted() == [1, 1, 2, 2])
        #expect(Set(successors.map(\.state)).count == 2)
        #expect(Set(successors.map(\.snapshot)).count == 4)
        let local = try #require(TLAStateProjection.Token(validating: "localPacket"))
        let expectedHidden: Set<TLAValue> = [
            .function([.int(0): .record(["count": .int(1), "ready": .bool(false)])]),
            .function([.int(0): .record(["count": .int(2), "ready": .bool(false)])])
        ]
        for count in [1, 2] {
            let samePublicState = successors.filter { $0.state.packet.count == count }
            #expect(Set(samePublicState.map(\.state)).count == 1)
            #expect(Set(samePublicState.map(\.snapshot)).count == 2)
            #expect(Set(try samePublicState.map {
                try initial.formalProjection(of: $0.snapshot).value(for: local)
            }) == expectedHidden)
        }
        let initialState = initial.state
        let changedHistory = GeneratedSwiftRecord.State(packet: initialState.packet,
            previousCount: initialState.previousCount,
            history: [GeneratedSwiftRecord.Packet(count: 9, ready: false)], archive: initialState.archive)
        let changedArchive = GeneratedSwiftRecord.State(packet: initialState.packet,
            previousCount: initialState.previousCount, history: initialState.history,
            archive: [GeneratedSwiftRecord.Packet(count: 9, ready: false), .init(count: 1, ready: true)])
        let sameState = GeneratedSwiftRecord.State(packet: initialState.packet,
            previousCount: initialState.previousCount, history: initialState.history,
            archive: [.init(count: 1, ready: true), .init(count: 0, ready: false)])
        #expect(initialState == sameState)
        for changed in [changedHistory, changedArchive] {
            #expect(initialState != changed)
            #expect(Set([initialState, sameState, changed, changed]).count == 2)
        }
        let graph = try ReachabilityGraph(initialMachines: machines, maximumStates: 5)
        #expect(graph.initialStates == [initial.snapshot])
        #expect(graph.transitions.count == 5)
        #expect(graph.transitions.keys.map { $0.state.packet.count }.sorted() == [0, 1, 1, 2, 2])
        #expect(Set(graph.safetyViolations.keys.map { $0.state.packet.count }) == [2])
        #expect(graph.deadlockedStates.isEmpty)

        for (source, edges) in graph.transitions {
            var machine = initial
            for step in try graph.trace(to: source).dropFirst() {
                let options = try machine.successors(for: #require(step.action))
                let expected = try initial.formalProjection(of: step.state)
                machine = try #require(try options.first { try initial.formalProjection(of: $0.snapshot) == expected })
            }
            #expect(try machine.formalProjection(of: machine.snapshot) == initial.formalProjection(of: source))
            #expect(try Set(machine.enabledActions()) == Set(edges.map(\.action)))
            for edge in edges {
                let expected = try initial.formalProjection(of: edge.target)
                #expect(try machine.successors(for: edge.action).contains {
                    try initial.formalProjection(of: $0.snapshot) == expected
                })
            }
        }

        var streamedCounts: [Int] = []
        let summary = try MachineValidator.run(initialMachines: machines, maximumStates: 5,
            checking: .init(properties: [.Bounded], checkDeadlock: false), stopOnViolation: false) { event in
            if case .state(_, let snapshot, _, _, _) = event {
                streamedCounts.append(snapshot.state.packet.count)
            }
        }
        #expect(summary.states == 5)
        #expect(streamedCounts.sorted() == [0, 1, 1, 2, 2])
        #expect(summary.violatedInvariants == [.Bounded])

        #expect(throws: ExplorationError.stateLimitExceeded(1)) {
            try ReachabilityGraph(initialMachines: machines, maximumStates: 1)
        }
    }
}
