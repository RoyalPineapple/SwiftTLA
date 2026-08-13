import os

public struct CanonicalTransitionEvidence<Snapshot: Equatable & Sendable>: Equatable, Sendable {
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

public protocol TLAMachineAdapterCanonicalModel: TLAMachineExecuting, Sendable {
    func synchronousMachineObservation() -> TLAMachineObservation

    mutating func executeSynchronously(
        _ invocation: TLAActionInvocation
    ) throws -> TransitionEvidence
}

public protocol TLAMachineAdapterAccess: AnyObject, TLAMachineExecuting {
    associatedtype CanonicalModel: TLAMachineAdapterCanonicalModel

    func withCanonicalMachine<Result: Sendable>(
        _ operation: @escaping @Sendable (inout CanonicalModel) throws -> Result
    ) async rethrows -> Result
}

public extension TLAMachineAdapterAccess where TransitionEvidence == CanonicalModel.TransitionEvidence {
    func canonicalMachineObservation() async -> TLAMachineObservation {
        await withCanonicalMachine { canonical in
            canonical.synchronousMachineObservation()
        }
    }

    func executeCanonical(_ invocation: TLAActionInvocation) async throws -> TransitionEvidence {
        try await withCanonicalMachine { canonical in
            try canonical.executeSynchronously(invocation)
        }
    }

    func machineObservation() async -> TLAMachineObservation {
        await canonicalMachineObservation()
    }

    func execute(_ invocation: TLAActionInvocation) async throws -> TransitionEvidence {
        try await executeCanonical(invocation)
    }
}

public struct CanonicalMachine<Snapshot: Equatable & Sendable>: Sendable {
    public let runtime: SpecRuntime
    private let stateDictionary: @Sendable (Snapshot) -> [String: TLAValue]
    private let snapshotFromDictionary: @Sendable ([String: TLAValue]) -> Snapshot
    public private(set) var snapshot: Snapshot

    public init(
        runtime: SpecRuntime,
        initial: Snapshot,
        stateDictionary: @escaping @Sendable (Snapshot) -> [String: TLAValue],
        snapshotFromDictionary: @escaping @Sendable ([String: TLAValue]) -> Snapshot
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

public final class LockedValue<Value: Sendable>: Sendable {
    private let storage: OSAllocatedUnfairLock<Value>

    public init(_ value: Value) {
        storage = OSAllocatedUnfairLock(initialState: value)
    }

    public var value: Value {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }
}

public final class CanonicalMachineStorage<Snapshot: Equatable & Sendable>: Sendable {
    private let storage: OSAllocatedUnfairLock<CanonicalMachine<Snapshot>>

    public init(_ machine: CanonicalMachine<Snapshot>) {
        storage = OSAllocatedUnfairLock(initialState: machine)
    }

    public var snapshot: Snapshot {
        storage.withLock { $0.snapshot }
    }

    public func tlaSnapshot() -> [String: TLAValue] {
        storage.withLock { $0.tlaSnapshot() }
    }

    public func availableInvocations() throws -> [TLAActionInvocation] {
        try storage.withLock { try $0.availableInvocations() }
    }

    public func availableInvocations(in state: [String: TLAValue]) throws -> [TLAActionInvocation] {
        try storage.withLock { try $0.availableInvocations(in: state) }
    }

    public func apply(
        _ invocation: TLAActionInvocation,
        from state: [String: TLAValue],
        selecting successor: @Sendable ([String: TLAValue]) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot> {
        try storage.withLock { try $0.apply(invocation, from: state, selecting: successor) }
    }
}
