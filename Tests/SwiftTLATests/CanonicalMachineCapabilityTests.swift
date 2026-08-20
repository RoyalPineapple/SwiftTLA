import Testing
import SwiftTLA

private let countToken = TLAStateProjection.Token(validating: "count")!

private func countProjection(_ count: Int) -> TLAStateProjection {
    try! .init(validating: [.init(token: countToken, value: .int(count))])
}

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

struct CanonicalMachineCapabilityTests {
    @Test("State projections require validated tokens and safely enumerate entries")
    func stateProjectionGuardsFormalKeys() throws {
        let count = TLAStateProjection.Token(validating: "count")!
        let mode = TLAStateProjection.Token(validating: "mode")!
        let state = try TLAStateProjection(validating: [
            .init(token: mode, value: .string("idle")),
            .init(token: count, value: .int(2))
        ])

        #expect(TLAStateProjection.Token(validating: "") == nil)
        #expect(TLAStateProjection.Token(validating: "2count") == nil)
        #expect(TLAStateProjection.Token(validating: "invalid-key") == nil)
        #expect(state.value(for: count) == .int(2))
        let missing = TLAStateProjection.Token(validating: "missing")!
        #expect(state.value(for: missing) == nil)
        #expect(state.entries.map(\.token.description) == ["count", "mode"])
        #expect(state.description == "count = 2, mode = \"idle\"")

        let unavailable = TLAStateProjectionResult.unavailable(.invalidKey(path: "missing"))
        #expect(unavailable.projection == nil)
        #expect(unavailable.diagnostic == .invalidKey(path: "missing"))
        #expect(throws: TLAStateProjectionDiagnostic.invalidKey(path: "missing")) {
            try unavailable.requireProjection()
        }
    }

    @Test("Protocol-generic observation retains atomic state and ordered availability")
    func protocolGenericObservationProjectsStateAndAvailability() async {
        let invocations = [
            TLAActionInvocation(name: "advance", arguments: [.int(1)]),
            TLAActionInvocation(name: "advance", arguments: [.int(2)])
        ]
        let machine = ObservationFixture(observation: .init(
            state: countProjection(0),
            availability: .available(invocations)
        ))

        let observation = await observe(machine)

        #expect(observation.state.projection?.value(for: countToken) == .int(0))
        #expect(observation.availableInvocations == invocations)
        #expect(observation.availabilityDiagnostic == nil)
        #expect(await machine.machineState().projection?.value(for: countToken) == .int(0))
        #expect(await machine.machineAvailability() == .available(invocations))
    }

    @Test("Protocol-generic observation retains state when availability evaluation fails")
    func protocolGenericObservationRetainsAvailabilityDiagnostic() async {
        let machine = ObservationFixture(observation: .init(
            state: countProjection(3),
            availability: .unavailable(.init(code: .evaluationFailed, message: "action enumeration failed"))
        ))

        let observation = await observe(machine)

        #expect(observation.state.projection?.value(for: countToken) == .int(3))
        #expect(observation.availableInvocations == nil)
        #expect(observation.availabilityDiagnostic == .init(
            code: .evaluationFailed,
            message: "action enumeration failed"
        ))
    }

    @Test("Canonical machine reports availability evaluation failures without losing its snapshot")
    func canonicalMachineObservationRetainsStateWhenAvailabilityFails() throws {
        let count = Var<Int>("count")
        let spec = TLASpec("UnavailableAvailability") {
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1) }
        }
        let runtime = try SpecRuntime(spec: spec) { _, _, _ in
            throw ActionEvaluationFailure.unavailable
        }
        let machine = CanonicalMachine(
            runtime: runtime,
            initial: ["count": .int(0)],
            stateDictionary: { $0 },
            snapshotFromDictionary: { $0 }
        )

        let observation = machine.machineObservation()

        #expect(observation.state.projection?.value(for: countToken) == .int(0))
        #expect(observation.availableInvocations == nil)
        #expect(observation.availabilityDiagnostic?.code == .evaluationFailed)
        #expect(observation.availabilityDiagnostic?.message.contains("unavailable") == true)
    }

    @Test("Canonical observation rejects invalid formal state without a projection")
    func canonicalMachineObservationReportsProjectionFailure() throws {
        let count = Var<Int>("count")
        let spec = TLASpec("InvalidProjection") {
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1) }
        }
        let invalidKeyMachine = CanonicalMachine(
            runtime: try SpecRuntime(spec: spec),
            initial: 0,
            stateDictionary: { _ in ["invalid-key": .constant("valid")] },
            snapshotFromDictionary: { _ in 0 }
        )
        let invalidValueMachine = CanonicalMachine(
            runtime: try SpecRuntime(spec: spec),
            initial: 0,
            stateDictionary: { _ in ["count": .constant("invalid-constant")] },
            snapshotFromDictionary: { _ in 0 }
        )

        let observation = invalidKeyMachine.machineObservation()
        let invalidValueObservation = invalidValueMachine.machineObservation()

        #expect(observation.state.projection == nil)
        #expect(observation.projectionDiagnostic == .invalidKey(path: "invalid-key"))
        #expect(observation.availableInvocations == nil)
        #expect(observation.availabilityDiagnostic?.code == .stateProjectionFailed)
        #expect(observation.availabilityDiagnostic?.projectionDiagnostic == .invalidKey(path: "invalid-key"))
        #expect(invalidKeyMachine.stateProjection().projection == nil)
        #expect(invalidValueObservation.state.projection == nil)
        #expect(invalidValueObservation.projectionDiagnostic == .invalidConstant(path: "count"))
    }

    private func observe<Machine: TLAMachineObserving>(_ machine: Machine) async -> TLAMachineObservation {
        await machine.machineObservation()
    }
}
