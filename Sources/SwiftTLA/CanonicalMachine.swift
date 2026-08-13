public struct CanonicalTransitionEvidence<Snapshot: Equatable>: Equatable {
    public let invocation: TLAActionInvocation
    public let before: Snapshot
    public let after: Snapshot

    public init(invocation: TLAActionInvocation, before: Snapshot, after: Snapshot) {
        self.invocation = invocation
        self.before = before
        self.after = after
    }
}

public enum GeneratedMachineError: Error {
    case runtime(SpecRuntime.RuntimeError)
    case unexpected(any Error)
    case unrepresentableActionLabel(TLAActionInvocation)
}

public struct TLAMachineAvailabilityDiagnostic: Sendable, Equatable {
    public enum Code: String, Sendable, Equatable {
        case evaluationFailed
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

public struct TLAMachineObservation: Sendable, Equatable {
    public enum Availability: Sendable, Equatable {
        case available([TLAActionInvocation])
        case unavailable(TLAMachineAvailabilityDiagnostic)
    }

    public let state: [String: TLAValue]
    public let availability: Availability

    public init(state: [String: TLAValue], availability: Availability) {
        self.state = state
        self.availability = availability
    }

    public var availableInvocations: [TLAActionInvocation]? {
        guard case .available(let invocations) = availability else { return nil }
        return invocations
    }

    public var availabilityDiagnostic: TLAMachineAvailabilityDiagnostic? {
        guard case .unavailable(let diagnostic) = availability else { return nil }
        return diagnostic
    }
}

public protocol TLAMachineObserving: Sendable {
    func machineObservation() async -> TLAMachineObservation
}

public extension TLAMachineObserving {
    func machineState() async -> [String: TLAValue] {
        await machineObservation().state
    }

    func machineAvailability() async -> TLAMachineObservation.Availability {
        await machineObservation().availability
    }
}

public protocol TLAMachineExecuting: TLAMachineObserving {
    associatedtype TransitionEvidence: Sendable

    mutating func execute(_ invocation: TLAActionInvocation) async throws -> TransitionEvidence
}

public protocol TLAMachineAdapterAccess: AnyObject, TLAMachineExecuting {
    associatedtype CanonicalModel: TLAMachineExecuting

    func withCanonicalMachine<Result: Sendable>(
        _ operation: @escaping @Sendable (inout CanonicalModel) async throws -> Result
    ) async rethrows -> Result
}

public extension TLAMachineAdapterAccess where TransitionEvidence == CanonicalModel.TransitionEvidence {
    func machineObservation() async -> TLAMachineObservation {
        await withCanonicalMachine { canonical in
            await canonical.machineObservation()
        }
    }

    func execute(_ invocation: TLAActionInvocation) async throws -> TransitionEvidence {
        try await withCanonicalMachine { canonical in
            try await canonical.execute(invocation)
        }
    }
}

public struct CanonicalMachine<Snapshot: Equatable> {
    public let runtime: SpecRuntime
    private let stateDictionary: (Snapshot) -> [String: TLAValue]
    private let snapshotFromDictionary: ([String: TLAValue]) -> Snapshot
    public private(set) var snapshot: Snapshot

    public init(
        runtime: SpecRuntime,
        initial: Snapshot,
        stateDictionary: @escaping (Snapshot) -> [String: TLAValue],
        snapshotFromDictionary: @escaping ([String: TLAValue]) -> Snapshot
    ) {
        self.runtime = runtime
        self.snapshot = initial
        self.stateDictionary = stateDictionary
        self.snapshotFromDictionary = snapshotFromDictionary
    }

    public func tlaSnapshot() -> [String: TLAValue] {
        stateDictionary(snapshot)
    }

    public func availableInvocations() throws -> [TLAActionInvocation] {
        try availableInvocations(in: tlaSnapshot())
    }

    public func availableInvocations(in state: [String: TLAValue]) throws -> [TLAActionInvocation] {
        do {
            return try runtime.availableInvocations(in: state)
        } catch let error as SpecRuntime.RuntimeError {
            throw GeneratedMachineError.runtime(error)
        } catch {
            throw GeneratedMachineError.unexpected(error)
        }
    }

    public func machineObservation() -> TLAMachineObservation {
        let state = tlaSnapshot()
        do {
            return .init(state: state, availability: .available(try availableInvocations(in: state)))
        } catch {
            return .init(
                state: state,
                availability: .unavailable(
                    .init(code: .evaluationFailed, message: String(describing: error))
                )
            )
        }
    }

    public mutating func apply(_ invocation: TLAActionInvocation) throws -> CanonicalTransitionEvidence<Snapshot> {
        try apply(invocation, from: tlaSnapshot()) { _ in true }
    }

    public mutating func apply(
        _ invocation: TLAActionInvocation,
        from state: [String: TLAValue],
        selecting successor: ([String: TLAValue]) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot> {
        let before = snapshotFromDictionary(state)
        let successors: [[String: TLAValue]]
        do {
            successors = try runtime.successors(invocation, from: state)
        } catch let error as SpecRuntime.RuntimeError {
            throw GeneratedMachineError.runtime(error)
        } catch {
            throw GeneratedMachineError.unexpected(error)
        }
        guard let next = successors.first(where: successor) else {
            let available = try availableInvocations(in: state)
            throw GeneratedMachineError.runtime(.actionNotEnabled(invocation, available: available))
        }
        let after = snapshotFromDictionary(next)
        snapshot = after
        return CanonicalTransitionEvidence(invocation: invocation, before: before, after: after)
    }
}
