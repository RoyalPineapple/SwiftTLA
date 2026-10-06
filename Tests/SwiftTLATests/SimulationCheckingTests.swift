import Testing
@testable import SwiftTLA

struct SimulationCheckingTests {
    @Test("Simulation revisits complete states and never treats a depth cutoff as success")
    func checksEachBehaviorLevel() throws {
        let initial = try RevisitedStateCheckingLevelModel.makeMachine()
        let checking = ModelChecks<RevisitedStateCheckingLevelModel.Property>(
            properties: [.BeforeThirdState], checkDeadlock: false)
        var generator = SystemRandomNumberGenerator()

        let bounded = try MachineSimulator.run(
            initialMachines: [initial], maximumDepth: 1, checking: checking, using: &generator)
        guard case .inconclusive(let prefix, let reason) = bounded else {
            Issue.record("A depth cutoff cannot establish satisfaction")
            return
        }
        #expect(reason == .maximumDepth)
        #expect(prefix.count == 2)
        #expect(prefix[0].state == prefix[1].state)

        let violating = try MachineSimulator.run(
            initialMachines: [initial], maximumDepth: 2, checking: checking, using: &generator)
        guard case .counterexample(let witness) = violating else {
            Issue.record("The third visit must violate the level-dependent invariant")
            return
        }
        #expect(witness.violations == [.invariant(.BeforeThirdState)])
        #expect(witness.trace.count == 3)
        #expect(witness.trace.allSatisfy { $0.state == initial.snapshot })
        #expect(witness.trace.compactMap { $0.action } == [.loop, .loop])
    }

    @Test("Simulation checks every successor of its chosen action before sampling")
    func checksUnchosenCandidate() throws {
        let initial = try CandidateSafetySimulationModel.makeMachine()
        let candidates = try initial.successors(for: .choose)
        #expect(Set(candidates.map { $0.state.value }) == [0, 1])
        var generator = LastCandidateGenerator()

        let result = try MachineSimulator.run(initialMachines: [initial], maximumDepth: 1,
            checking: .init(properties: [.NonZero], checkDeadlock: false), using: &generator)
        guard case .counterexample(let witness) = result else {
            Issue.record("The invalid candidate must fail before a safe successor is sampled")
            return
        }
        #expect(witness.violations == [.invariant(.NonZero)])
        #expect(witness.trace.map { $0.state.state.value } == [2, 0])
    }

    @Test("Simulation checks initial invariants before excluding constrained states")
    func checksConstrainedInitialCandidate() throws {
        let initial = try ConstrainedInitialSafetySimulationModel.initialMachines()
        #expect(initial.map { $0.state.value } == [0, 1])
        var selectedIndex = FirstCandidateGenerator()
        #expect(Int.random(in: 0..<initial.count, using: &selectedIndex) == 0)
        var generator = FirstCandidateGenerator()

        let result = try MachineSimulator.run(initialMachines: initial, maximumDepth: 1,
            checking: .init(properties: [.OnlyZero], checkDeadlock: false), using: &generator)
        guard case .counterexample(let witness) = result else {
            Issue.record("A constrained-out initial state still has to satisfy invariants")
            return
        }
        #expect(witness.violations == [.invariant(.OnlyZero)])
        #expect(witness.trace.map { $0.state.state.value } == [1])
    }

    @Test("Simulation checks later traces before reporting inconclusive")
    func checksRequestedTraceCount() throws {
        let initial = try LaterTraceSafetySimulationModel.initialMachines()
        let checking = ModelChecks<LaterTraceSafetySimulationModel.Property>(
            properties: [.NonNegative], checkDeadlock: false)
        var firstOnly = LaterTraceCandidateGenerator()
        let one = try MachineSimulator.run(initialMachines: initial, maximumDepth: 2,
            checking: checking, using: &firstOnly)
        guard case .inconclusive(_, .deadEnd) = one else {
            Issue.record("The first safe trace must end without proving the invariant")
            return
        }

        var both = LaterTraceCandidateGenerator()
        let two = try MachineSimulator.run(initialMachines: initial, maximumDepth: 2,
            traceCount: 2, checking: checking, using: &both)
        guard case .counterexample(let witness) = two else {
            Issue.record("A later sampled trace must expose its counterexample")
            return
        }
        #expect(witness.violations == [.invariant(.NonNegative)])
        #expect(witness.trace.map { $0.state.state.value } == [2, 1, -1])

        #expect(throws: ExplorationError.invalidSimulationTraceCount(0)) {
            var generator = LaterTraceCandidateGenerator()
            _ = try MachineSimulator.run(initialMachines: initial, maximumDepth: 2,
                traceCount: 0, checking: checking, using: &generator)
        }
    }
}
