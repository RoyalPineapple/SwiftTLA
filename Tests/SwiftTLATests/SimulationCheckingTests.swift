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
}
