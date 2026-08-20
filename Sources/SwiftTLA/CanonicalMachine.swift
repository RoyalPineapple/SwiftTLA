import os

/// Describes why the formal state cannot cross the guarded application boundary.
public enum TLAStateProjectionDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidKey(path: String)
    case invalidConstant(path: String)
    case missingValue(path: String)
    case invalidValue(path: String)
    case projectionUnavailable(path: String, reason: String)
    /// A generated typed state field was absent. This retains the Swift shape
    /// that the generated machine expected to decode.
    case missingRequiredValue(path: String, expected: String)
    /// A generated typed state field had a formal value of the wrong kind.
    /// The formal value is retained so callers can inspect it without
    /// reaching back into the engine's raw state dictionary.
    case typeMismatch(path: String, expected: String, actual: TLAValue)

    public var description: String {
        switch self {
        case .invalidKey(let path):
            return "Invalid TLA state key at \(path)"
        case .invalidConstant(let path):
            return "Invalid TLA constant at \(path)"
        case .missingValue(let path):
            return "Missing TLA state value at \(path)"
        case .invalidValue(let path):
            return "Invalid TLA state value at \(path)"
        case .projectionUnavailable(let path, let reason):
            return "Cannot project formal state at \(path): \(reason). No state changed. Inspect the reported boundary before retrying."
        case .missingRequiredValue(let path, let expected):
            return "Cannot decode \(path): expected \(expected), but the formal state has no value; state was not committed. Supply \(expected) for \(path) before retrying."
        case .typeMismatch(let path, let expected, let actual):
            return "Cannot decode \(path): expected \(expected), found formal \(actual); state was not committed. Correct \(path) or its formal declaration before retrying."
        }
    }
}

/// An opaque, safe view of formal-engine state for application-facing APIs.
public struct TLAStateProjection: Sendable, Equatable, CustomStringConvertible {
    /// A validated identifier for a value in a formal state projection.
    public struct Token: Sendable, Hashable, CustomStringConvertible {
        fileprivate let identifier: String

        public init?(validating identifier: String) {
            guard let first = identifier.unicodeScalars.first,
                  first.properties.isAlphabetic || first == "_",
                  identifier.unicodeScalars.dropFirst().allSatisfy({
                      $0.properties.isAlphabetic || $0.properties.isIDContinue
                  }) else {
                return nil
            }
            self.identifier = identifier
        }

        public var description: String { identifier }
    }

    /// One validated value in a state projection.
    public struct Entry: Sendable, Equatable {
        public let token: Token
        public let value: TLAValue

        public init(token: Token, value: TLAValue) {
            self.token = token
            self.value = value
        }
    }

    private let storedEntries: [Entry]

    public init(validating entries: [Entry]) throws {
        var tokens = Set<Token>()
        for entry in entries {
            guard tokens.insert(entry.token).inserted else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: entry.token.identifier)
            }
            try Self.validate(entry.value, at: entry.token.identifier)
        }
        storedEntries = entries.sorted { $0.token.identifier < $1.token.identifier }
    }

    public func value(for token: Token) -> TLAValue? {
        storedEntries.first { $0.token == token }?.value
    }

    public func replacing(_ value: TLAValue, for token: Token) throws -> TLAStateProjection {
        var entries = entries.filter { $0.token != token }
        entries.append(.init(token: token, value: value))
        return try .init(validating: entries)
    }

    public var entries: [Entry] {
        storedEntries
    }

    public var description: String {
        entries.map { "\($0.token) = \($0.value)" }.joined(separator: ", ")
    }

    private static func validate(_ value: TLAValue, at path: String) throws {
        switch value {
        case .int, .bool, .string:
            return
        case .constant(let name):
            guard Token(validating: name) != nil else {
                throw TLAStateProjectionDiagnostic.invalidConstant(path: path)
            }
        case .set(let values):
            for (index, value) in values.sorted().enumerated() {
                try validate(value, at: "\(path){\(index)}")
            }
        case .tuple(let values):
            for (index, value) in values.enumerated() {
                try validate(value, at: "\(path)[\(index)]")
            }
        case .record(let fields):
            for (name, value) in fields {
                guard Token(validating: name) != nil else {
                    throw TLAStateProjectionDiagnostic.invalidKey(path: "\(path).\(name)")
                }
                try validate(value, at: "\(path).\(name)")
            }
        case .function(let mapping):
            for (key, value) in mapping {
                try validate(key, at: "\(path).key")
                try validate(value, at: "\(path).value")
            }
        }
    }
}

/// Contains a valid projection or the typed reason why one is unavailable.
public enum TLAStateProjectionResult: Sendable, Equatable {
    case projected(TLAStateProjection)
    case unavailable(TLAStateProjectionDiagnostic)

    public var projection: TLAStateProjection? {
        guard case .projected(let projection) = self else { return nil }
        return projection
    }

    public var diagnostic: TLAStateProjectionDiagnostic? {
        guard case .unavailable(let diagnostic) = self else { return nil }
        return diagnostic
    }

    public func requireProjection() throws -> TLAStateProjection {
        switch self {
        case .projected(let projection):
            return projection
        case .unavailable(let diagnostic):
            throw diagnostic
        }
    }
}

public struct CanonicalTransitionEvidence<Snapshot: Equatable & Sendable, Action: Equatable & Sendable>: Equatable, Sendable {
    public let action: Action
    public let before: Snapshot
    public let after: Snapshot

    public init(action: Action, before: Snapshot, after: Snapshot) {
        self.action = action
        self.before = before
        self.after = after
    }
}

/// Reports a generated-machine execution failure.
public enum GeneratedMachineError: Error {
    case noInitialState
    case noMatchingSuccessor
    case liveMachineSchemaMismatch(expected: String, actual: String)
    case liveMachineUnavailable(TLALiveMachineUnavailableReason)
    /// The formal successor could not be decoded into the generated Swift
    /// state. The canonical snapshot remains unchanged.
    case stateDecodingFailed(TLAStateProjectionDiagnostic)
    case unexpected(any Error)
    /// This action selects a live identified collection member and must use
    /// the generated `action(id:)` API rather than generic execution.
    case identityRoutedActionRequiresID
}

public struct CanonicalMachine<Snapshot: Equatable & Sendable>: Sendable {
    public let compilation: CompiledSpecification
    private let projectionForSnapshot: @Sendable (Snapshot) throws -> TLAStateProjection
    private let snapshotFromProjection: @Sendable (TLAStateProjection) throws -> Snapshot
    public private(set) var snapshot: Snapshot

    public init(
        compilation: CompiledSpecification,
        initial: Snapshot,
        projectionForSnapshot: @escaping @Sendable (Snapshot) throws -> TLAStateProjection,
        snapshotFromProjection: @escaping @Sendable (TLAStateProjection) throws -> Snapshot
    ) {
        self.compilation = compilation
        self.snapshot = initial
        self.projectionForSnapshot = projectionForSnapshot
        self.snapshotFromProjection = snapshotFromProjection
    }

    package func tlaSnapshot() throws -> TLAStateProjection {
        try projectionForSnapshot(snapshot)
    }

    public func stateProjection() -> TLAStateProjectionResult {
        do {
            return .projected(try tlaSnapshot())
        } catch let diagnostic as TLAStateProjectionDiagnostic {
            return .unavailable(diagnostic)
        } catch {
            return .unavailable(.projectionUnavailable(
                path: "state",
                reason: String(describing: error)
            ))
        }
    }

    public mutating func apply<Label>(
        _ action: Label,
        using executor: CompiledActionExecutor<Label>,
        from state: TLAStateProjection,
        selecting successor: (TLAStateProjection) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot, Label>
    where Label: Hashable & Sendable {
        let successors = try executor.successors(for: action, from: state)
        return try apply(
            successors,
            action: action,
            from: state,
            selecting: successor
        )
    }

    private mutating func apply<Action>(
        _ successors: [TLAStateProjection],
        action: Action,
        from state: TLAStateProjection,
        selecting successor: (TLAStateProjection) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot, Action>
    where Action: Equatable & Sendable {
        let before: Snapshot
        do {
            before = try snapshotFromProjection(state)
        } catch {
            throw GeneratedMachineError.unexpected(error)
        }
        for projection in successors {
            guard successor(projection) else { continue }
            let after: Snapshot
            do {
                after = try snapshotFromProjection(projection)
            } catch let diagnostic as TLAStateProjectionDiagnostic {
                throw GeneratedMachineError.stateDecodingFailed(diagnostic)
            } catch {
                throw GeneratedMachineError.unexpected(error)
            }
            snapshot = after
            return CanonicalTransitionEvidence(action: action, before: before, after: after)
        }
        throw GeneratedMachineError.noMatchingSuccessor
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
