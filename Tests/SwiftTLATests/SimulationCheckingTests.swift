import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

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

        let fairness: [MachineFairnessCondition<CandidateSafetySimulationModel.Snapshot,
            CandidateSafetySimulationModel.Action>] = [
                (name: "choose", isStrong: false, matches: { _ in true },
                 changes: { _, _ in throw NativeMachineEvaluationError.noMatchingCase })
            ]
        let partial = try MachineValidator.run(initialMachines: [initial], maximumStates: 4,
            checking: .init(properties: [.NonZero], checkDeadlock: false),
            stopOnViolation: true, fairness: fairness) { _ in }
        #expect(partial.completion == .decisiveViolation)
        #expect(partial.fairnessEnabledness == nil)
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            _ = try MachineValidator.run(initialMachines: [initial], maximumStates: 4,
                checking: .init(properties: [.NonZero], checkDeadlock: false),
                stopOnViolation: false, fairness: fairness) { _ in }
        }
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

    @Test("model-owned simulation settings drive generated-machine sampling")
    func configuredScenarioSamplesRequestedTraces() throws {
        let scenario = try #require(LaterTraceSafetySimulationModel.validationScenarios().first)
        #expect(scenario.checkingMode == .simulation(traces: 2, maximumDepth: 2))
        var generator = LaterTraceCandidateGenerator()
        let result = try scenario.simulate(using: &generator)
        guard case .counterexample(let witness) = result else {
            Issue.record("The configured second trace must expose its counterexample")
            return
        }
        #expect(witness.violations == [.invariant(.NonNegative)])
        #expect(witness.trace.map { $0.state.state.value } == [2, 1, -1])
    }

    @Test("a sampled trace reports a temporal counterexample with a lasso")
    func sampledTemporalWitness() throws {
        let scenario = try #require(SampledTemporalViolationModel.validationScenarios().first)
        var generator = FirstCandidateGenerator()
        let result = try scenario.simulate(using: &generator)
        guard case .temporalCounterexample(let property, let witness, let trace) = result else {
            Issue.record("The sampled trace must expose a violating lasso")
            return
        }
        #expect(property == .EventuallyThree)
        #expect(trace.map { $0.state.state.value } == [0, 1, 2])
        #expect(!witness.cycle.isEmpty)
    }

    @Test("a sampled trace without a temporal violation is inconclusive")
    func sampledTemporalNonproof() throws {
        let scenario = try #require(SampledTemporalNonproofModel.validationScenarios().first)
        var generator = FirstCandidateGenerator()
        let result = try scenario.simulate(using: &generator)
        guard case .inconclusive(let trace, let reason) = result else {
            Issue.record("The sampled trace must not establish temporal satisfaction")
            return
        }
        #expect(trace.map { $0.state.state.value } == [0, 1])
        #expect(reason == .maximumDepth)
    }

    @Test("constraints and sampling cannot treat an omitted fair action as disabled")
    func fairnessUsesRawEnablednessAcrossConstraintsAndSampling() throws {
        let scenario = try #require(SampledFairTemporalModel.validationScenarios().first)
        let initial = try scenario.initialMachines()
        var raw = try #require(initial.first)
        #expect(try raw.isEnabled(.advance))
        _ = try raw.send(.advance)
        #expect(raw.state.value == 1)
        #expect(try !raw.satisfiesStateConstraint())

        var generator = LastCandidateGenerator()
        let result = try MachineSimulator.run(initialMachines: initial,
            maximumDepth: 1, checking: scenario.checking, using: &generator)
        guard case .inconclusive(let trace, _) = result else {
            Issue.record("An unvisited fair action cannot be treated as disabled")
            return
        }
        #expect(trace.map { $0.state.state.value } == [0, 0])

        let retained = try ReachabilityGraph(initialMachines: initial, maximumStates: 4,
            checking: scenario.checking)
        #expect(Set(retained.transitions.keys.map { $0.state.value }) == [0])
        #expect(retained.temporalResults[.EventuallyOne]?.status == .satisfied)

        let captured = try MachineValidationGraph(initialMachines: initial, maximumStates: 4)
        #expect(Set(captured.transitions.keys.map { $0.state.value }) == [0])
        let capturedResults = try captured.temporalResults(checking: [.EventuallyOne])
        #expect(capturedResults[.EventuallyOne]?.status == .satisfied)

        let exhaustive = SampledFairTemporalModel.ValidationScenario(
            name: scenario.name, displayName: scenario.displayName, checking: scenario.checking,
            checkingMode: .exhaustive, behavior: scenario.behavior,
            selectedSymmetry: scenario.selectedSymmetry,
            selectedFairnessProfile: scenario.selectedFairnessProfile,
            selectedFairnessProfileName: scenario.selectedFairnessProfileName,
            selectedView: scenario.selectedView, selectedPostcondition: scenario.selectedPostcondition,
            postconditionName: scenario.postconditionName,
            postconditionExpectation: scenario.postconditionExpectation,
            expectations: scenario.expectations, deadlockExpectation: scenario.deadlockExpectation)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: output) }
        let report = try NativeValidationRunner.run(scenario: exhaustive,
            caseID: "constrained-fairness", maximumStates: 4, to: output)
        #expect(report.graphComplete && report.states == 1)
        #expect(report.properties["EventuallyOne"] == .satisfied)
    }

    @Test("a sampled trace reports a fair counterexample when the fair action becomes disabled")
    func sampledFairTemporalWitness() throws {
        let scenario = try #require(SampledFairTemporalViolationModel.validationScenarios().first)
        var generator = FirstCandidateGenerator()
        let result = try scenario.simulate(using: &generator)
        guard case .temporalCounterexample(let property, let witness, let trace) = result else {
            Issue.record("The final stutter is fair because advance is disabled")
            return
        }
        #expect(property == .EventuallyTwo)
        #expect(trace.map { $0.state.state.value } == [0, 1])
        #expect(!witness.cycle.isEmpty && witness.cycle.allSatisfy { $0.state.value == 1 })
    }
}
