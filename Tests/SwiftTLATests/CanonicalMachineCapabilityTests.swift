import Testing
import SwiftTLA

private actor ObservationFixture: TLAMachineObserving {
    private let observation: TLAMachineObservation

    init(observation: TLAMachineObservation) {
        self.observation = observation
    }

    func machineObservation() -> TLAMachineObservation {
        observation
    }
}

private enum ActionEvaluationFailure: Error {
    case unavailable
}

private enum AdapterExecutionFailure: Error {
    case rejected
}

private struct AdapterTransitionEvidence: Sendable, Equatable {
    let before: Int
    let after: Int
}

private struct MutableCanonicalMachine: TLAMachineAdapterCanonicalModel {
    private var count = 0

    func machineObservation() async -> TLAMachineObservation {
        .init(
            state: ["count": .int(count)],
            availability: .available(
                count == 0
                    ? [TLAActionInvocation(name: "advance")]
                    : []
            )
        )
    }

    mutating func execute(_ invocation: TLAActionInvocation) async throws -> AdapterTransitionEvidence {
        try executeSynchronously(invocation)
    }

    func synchronousMachineObservation() -> TLAMachineObservation {
        .init(
            state: ["count": .int(count)],
            availability: .available(
                count == 0
                    ? [TLAActionInvocation(name: "advance")]
                    : []
            )
        )
    }

    mutating func executeSynchronously(_ invocation: TLAActionInvocation) throws -> AdapterTransitionEvidence {
        guard invocation == TLAActionInvocation(name: "advance"), count == 0 else {
            throw AdapterExecutionFailure.rejected
        }

        let evidence = AdapterTransitionEvidence(before: count, after: count + 1)
        count += 1
        return evidence
    }
}

@MainActor
private final class ClassMachineAdapter: TLAMachineAdapterAccess {
    typealias CanonicalModel = MutableCanonicalMachine
    typealias TransitionEvidence = AdapterTransitionEvidence

    private var canonical = MutableCanonicalMachine()

    func withCanonicalMachine<Result: Sendable>(
        _ operation: @escaping @Sendable (inout MutableCanonicalMachine) throws -> Result
    ) async rethrows -> Result {
        try operation(&canonical)
    }
}

private actor ActorMachineAdapter: TLAMachineAdapterAccess {
    typealias CanonicalModel = MutableCanonicalMachine
    typealias TransitionEvidence = AdapterTransitionEvidence

    private var canonical = MutableCanonicalMachine()

    func withCanonicalMachine<Result: Sendable>(
        _ operation: @escaping @Sendable (inout MutableCanonicalMachine) throws -> Result
    ) async rethrows -> Result {
        try operation(&canonical)
    }
}

struct CanonicalMachineCapabilityTests {
    @Test("Protocol-generic observation retains atomic state and ordered availability")
    func protocolGenericObservationProjectsStateAndAvailability() async {
        let invocations = [
            TLAActionInvocation(name: "advance", arguments: [.int(1)]),
            TLAActionInvocation(name: "advance", arguments: [.int(2)])
        ]
        let machine = ObservationFixture(observation: .init(
            state: ["count": .int(0)],
            availability: .available(invocations)
        ))

        let observation = await observe(machine)

        #expect(observation.state == ["count": .int(0)])
        #expect(observation.availableInvocations == invocations)
        #expect(observation.availabilityDiagnostic == nil)
        #expect(await machine.machineState() == ["count": .int(0)])
        #expect(await machine.machineAvailability() == .available(invocations))
    }

    @Test("Protocol-generic observation retains state when availability evaluation fails")
    func protocolGenericObservationRetainsAvailabilityDiagnostic() async {
        let machine = ObservationFixture(observation: .init(
            state: ["count": .int(3)],
            availability: .unavailable(.init(code: .evaluationFailed, message: "action enumeration failed"))
        ))

        let observation = await observe(machine)

        #expect(observation.state == ["count": .int(3)])
        #expect(observation.availableInvocations == nil)
        #expect(observation.availabilityDiagnostic == .init(
            code: .evaluationFailed,
            message: "action enumeration failed"
        ))
    }

    @Test("Canonical machine reports availability evaluation failures without losing its snapshot")
    func canonicalMachineObservationRetainsStateWhenAvailabilityFails() {
        let count = Var<Int>("count")
        let spec = TLASpec("UnavailableAvailability") {
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1) }
        }
        let runtime = SpecRuntime(spec: spec) { _, _, _ in
            throw ActionEvaluationFailure.unavailable
        }
        let machine = CanonicalMachine(
            runtime: runtime,
            initial: ["count": .int(0)],
            stateDictionary: { $0 },
            snapshotFromDictionary: { $0 }
        )

        let observation = machine.machineObservation()

        #expect(observation.state == ["count": .int(0)])
        #expect(observation.availableInvocations == nil)
        #expect(observation.availabilityDiagnostic?.code == .evaluationFailed)
        #expect(observation.availabilityDiagnostic?.message.contains("unavailable") == true)
    }

    @Test("Class adapters forward mutable canonical storage and preserve it on failure")
    @MainActor
    func classAdapterForwardsMutableCanonicalStorage() async {
        let adapter = ClassMachineAdapter()

        let before = await observe(adapter)
        let evidence = try! await adapter.execute(.init(name: "advance"))
        let after = await observe(adapter)
        await #expect(throws: AdapterExecutionFailure.rejected) {
            try await adapter.execute(.init(name: "advance"))
        }
        let rejected = await observe(adapter)

        #expect(before.state == ["count": .int(0)])
        #expect(before.availableInvocations == [.init(name: "advance")])
        #expect(evidence == .init(before: 0, after: 1))
        #expect(after.state == ["count": .int(1)])
        #expect(after.availableInvocations == [])
        #expect(rejected == after)
    }

    @Test("Actor adapters forward mutable canonical storage atomically")
    func actorAdapterForwardsMutableCanonicalStorage() async {
        let adapter = ActorMachineAdapter()

        let before = await observe(adapter)
        let evidence = try! await adapter.execute(.init(name: "advance"))
        let after = await observe(adapter)
        await #expect(throws: AdapterExecutionFailure.rejected) {
            try await adapter.execute(.init(name: "advance"))
        }
        let rejected = await observe(adapter)

        #expect(before.state == ["count": .int(0)])
        #expect(before.availableInvocations == [.init(name: "advance")])
        #expect(evidence == .init(before: 0, after: 1))
        #expect(after.state == ["count": .int(1)])
        #expect(after.availableInvocations == [])
        #expect(rejected == after)
    }

    private func observe<Machine: TLAMachineObserving>(_ machine: Machine) async -> TLAMachineObservation {
        await machine.machineObservation()
    }
}
