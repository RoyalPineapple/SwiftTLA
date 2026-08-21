import os

/// Describes why the formal state cannot cross the guarded application boundary.
public enum TLAStateProjectionDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidKey(path: String)
    case invalidConstant(path: String)
    case missingValue(path: String)
    case invalidValue(path: String)
    case projectionUnavailable(path: String, reason: String)
    /// A generated typed state field was absent.
    case missingRequiredValue(path: String, expected: String)
    /// A generated typed state field had a formal value of the wrong kind.
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
            return "Cannot project formal state at \(path): \(reason). Inspect the reported boundary before retrying."
        case .missingRequiredValue(let path, let expected):
            return "Cannot decode \(path): expected \(expected), but the formal state has no value. Supply \(expected) for \(path) before retrying."
        case .typeMismatch(let path, let expected, let actual):
            return "Cannot decode \(path): expected \(expected), found formal \(actual). Correct \(path) or its formal declaration before retrying."
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
            for field in fields.fields {
                guard Token(validating: field.name) != nil else {
                    throw TLAStateProjectionDiagnostic.invalidKey(path: "\(path).\(field.name)")
                }
                try validate(field.value, at: "\(path).\(field.name)")
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

package struct CanonicalTransitionEvidence<Snapshot: Equatable & Sendable, Action: Equatable & Sendable>: Equatable, Sendable {
    package let action: Action
    package let before: Snapshot
    package let after: Snapshot

    package init(action: Action, before: Snapshot, after: Snapshot) {
        self.action = action
        self.before = before
        self.after = after
    }
}

/// Reports a generated-machine execution failure.
public enum GeneratedMachineError: Error, Sendable {
    case noInitialState
    case ambiguousInitialState
    case invalidInitialState
    case noMatchingSuccessor
    case liveMachineSchemaMismatch(expected: String, actual: String)
    case liveMachineUnavailable(TLALiveMachineUnavailableReason)
    /// This action selects a live identified collection member through the
    /// generated `action(id:)` API.
    case identityRoutedActionRequiresID
}

package struct CompiledActionRequest: Sendable {
    let action: ActionID
    let arguments: [CompiledValue]

    init(action: ActionID, arguments: [CompiledValue]) {
        self.action = action
        self.arguments = arguments
    }
}

package struct CanonicalMachine<Snapshot: Equatable & Sendable, Label: Hashable & Sendable>: Sendable {
    private let compilation: CompiledSpecification
    private let snapshotFromProjection: @Sendable (TLAStateProjection) throws -> Snapshot
    private let actionRequest: @Sendable (Label) throws -> CompiledActionRequest
    private let labelFromRequest: @Sendable (CompiledActionRequest) throws -> Label?
    private var formalState: TLAStateProjection
    package private(set) var snapshot: Snapshot

    package init(
        compilation: CompiledSpecification,
        initial: Snapshot,
        formalState: TLAStateProjection,
        snapshotFromProjection: @escaping @Sendable (TLAStateProjection) throws -> Snapshot,
        actionRequest: @escaping @Sendable (Label) throws -> CompiledActionRequest,
        labelFromRequest: @escaping @Sendable (CompiledActionRequest) throws -> Label?
    ) {
        self.compilation = compilation
        self.snapshot = initial
        self.formalState = formalState
        self.snapshotFromProjection = snapshotFromProjection
        self.actionRequest = actionRequest
        self.labelFromRequest = labelFromRequest
    }

    package func stateProjection() -> TLAStateProjectionResult {
        .projected(formalState)
    }

    package mutating func apply(
        _ action: Label,
        from state: TLAStateProjection? = nil,
        selecting successor: (Snapshot) -> Bool = { _ in true }
    ) throws -> CanonicalTransitionEvidence<Snapshot, Label> {
        let state = state ?? formalState
        let successors = try successors(for: action, from: state)
        return try apply(
            successors,
            action: action,
            from: state,
            selecting: successor
        )
    }

    package func successors(
        for action: Label,
        from state: TLAStateProjection
    ) throws -> [TLAStateProjection] {
        let formalState = try CompiledState(projection: state, compilation: compilation)
        let request = try actionRequest(action)
        return try CompiledRuntime(compilation: compilation)
            .successors(for: request.action, from: formalState)
            .filter { try compilation.matches($0.arguments, request: request) }
            .map { try $0.state.projection(using: compilation.layout) }
    }

    package func successors(for action: Label) throws -> [TLAStateProjection] {
        try successors(for: action, from: formalState)
    }

    package func availableActions(in state: TLAStateProjection) throws -> [Label] {
        let formalState = try CompiledState(projection: state, compilation: compilation)
        return try CompiledRuntime(compilation: compilation).successors(from: formalState).reduce(into: []) { labels, successor in
            let request = try compilation.actionRequest(
                action: successor.action,
                formalArguments: successor.arguments
            )
            guard let value = try labelFromRequest(request) else {
                throw GeneratedMachineError.noMatchingSuccessor
            }
            if labels.last != value { labels.append(value) }
        }
    }

    private mutating func apply<Action>(
        _ successors: [TLAStateProjection],
        action: Action,
        from state: TLAStateProjection,
        selecting successor: (Snapshot) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot, Action>
    where Action: Equatable & Sendable {
        let before = try snapshotFromProjection(state)
        for projection in successors {
            let after = try snapshotFromProjection(projection)
            guard successor(after) else { continue }
            snapshot = after
            formalState = projection
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
