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
