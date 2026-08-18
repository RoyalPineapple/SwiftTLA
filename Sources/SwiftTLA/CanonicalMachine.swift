import os

/// Describes why the formal state cannot cross the guarded application boundary.
public enum TLAStateProjectionDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidKey(path: String)
    case invalidConstant(path: String)
    case missingValue(path: String)
    case invalidValue(path: String)
    case projectionUnavailable(path: String, reason: String)
    /// A generated typed state field was absent.  Unlike the legacy
    /// `missingValue` spelling, this retains the Swift shape that the
    /// generated machine expected to decode.
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

    fileprivate let values: [String: TLAValue]

    public init(validating entries: [Entry]) throws {
        var values: [String: TLAValue] = [:]
        for entry in entries {
            guard values[entry.token.identifier] == nil else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: entry.token.identifier)
            }
            try Self.validate(entry.value, at: entry.token.identifier)
            values[entry.token.identifier] = entry.value
        }
        self.values = values
    }

    public func value(for token: Token) -> TLAValue? {
        values[token.identifier]
    }

    public func replacing(_ value: TLAValue, for token: Token) throws -> TLAStateProjection {
        var entries = entries.filter { $0.token != token }
        entries.append(.init(token: token, value: value))
        return try .init(validating: entries)
    }

    public var entries: [Entry] {
        values.keys.sorted().compactMap { identifier in
            guard let token = Token(validating: identifier), let value = values[identifier] else { return nil }
            return Entry(token: token, value: value)
        }
    }

    public var description: String {
        entries.map { "\($0.token) = \($0.value)" }.joined(separator: ", ")
    }

    package init(formalValues: [String: TLAValue]) throws {
        var entries: [Entry] = []
        for (identifier, value) in formalValues {
            guard let token = Token(validating: identifier) else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: identifier)
            }
            entries.append(.init(token: token, value: value))
        }
        try self.init(validating: entries)
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

/// An internal generic transition record for canonical machine implementations.
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

/// Reports a generated-machine execution failure.
public enum GeneratedMachineError: Error {
    case runtime(SpecRuntime.RuntimeError)
    /// The formal successor could not be decoded into the generated Swift
    /// state. The canonical snapshot remains unchanged.
    case stateDecodingFailed(TLAStateProjectionDiagnostic)
    case unexpected(any Error)
    case unrepresentableActionLabel(TLAActionInvocation)
    /// This action selects a live identified collection member and must use
    /// the generated `action(id:)` API rather than generic execution.
    case identityRoutedActionRequiresID(TLAActionInvocation)
}

/// Explains why a machine cannot report its currently available actions.
public struct TLAMachineAvailabilityDiagnostic: Sendable, Equatable {
    public enum Code: String, Sendable, Equatable {
        case evaluationFailed
        case stateProjectionFailed
    }

    public let code: Code
    public let message: String
    public let projectionDiagnostic: TLAStateProjectionDiagnostic?

    public init(
        code: Code,
        message: String,
        projectionDiagnostic: TLAStateProjectionDiagnostic? = nil
    ) {
        self.code = code
        self.message = message
        self.projectionDiagnostic = projectionDiagnostic
    }
}

/// Combines a guarded state result with action availability for one observation.
public struct TLAMachineObservation: Sendable, Equatable {
    public enum Availability: Sendable, Equatable {
        case available([TLAActionInvocation])
        case unavailable(TLAMachineAvailabilityDiagnostic)
    }

    public let state: TLAStateProjectionResult
    public let availability: Availability

    public init(state: TLAStateProjection, availability: Availability) {
        self.state = .projected(state)
        self.availability = availability
    }

    public init(state: TLAStateProjectionResult, availability: Availability) {
        self.state = state
        self.availability = availability
    }

    package init(state formalState: [String: TLAValue], availability: Availability) {
        do {
            self.init(state: try .init(formalValues: formalState), availability: availability)
        } catch let diagnostic as TLAStateProjectionDiagnostic {
            self.init(
                state: .unavailable(diagnostic),
                availability: .unavailable(
                    .init(
                        code: .stateProjectionFailed,
                        message: diagnostic.description,
                        projectionDiagnostic: diagnostic
                    )
                )
            )
        } catch {
            let diagnostic = TLAStateProjectionDiagnostic.projectionUnavailable(
                path: "state",
                reason: String(describing: error)
            )
            self.init(
                state: .unavailable(diagnostic),
                availability: .unavailable(
                    .init(
                        code: .stateProjectionFailed,
                        message: diagnostic.description,
                        projectionDiagnostic: diagnostic
                    )
                )
            )
        }
    }

    public var availableInvocations: [TLAActionInvocation]? {
        guard case .available(let invocations) = availability else { return nil }
        return invocations
    }

    public var availabilityDiagnostic: TLAMachineAvailabilityDiagnostic? {
        guard case .unavailable(let diagnostic) = availability else { return nil }
        return diagnostic
    }

    public var projection: TLAStateProjection? { state.projection }

    public var projectionDiagnostic: TLAStateProjectionDiagnostic? { state.diagnostic }
}

/// An asynchronous source of guarded machine observations.
public protocol TLAMachineObserving: Sendable {
    func machineObservation() async -> TLAMachineObservation
}

public extension TLAMachineObserving {
    func machineState() async -> TLAStateProjectionResult {
        await machineObservation().state
    }

    func machineAvailability() async -> TLAMachineObservation.Availability {
        await machineObservation().availability
    }
}

/// A machine that executes formal action invocations asynchronously.
public protocol TLAMachineExecuting: TLAMachineObserving {
    associatedtype TransitionResult: Sendable

    mutating func execute(_ invocation: TLAActionInvocation) async throws -> TransitionResult
}

/// The synchronous canonical model that backs a generated adapter.
public protocol TLAMachineAdapterCanonicalModel: TLAMachineExecuting, Sendable {
    func synchronousMachineObservation() -> TLAMachineObservation

    mutating func executeSynchronously(
        _ invocation: TLAActionInvocation
    ) throws -> TransitionResult
}

/// An adapter that provides serialized access to its canonical generated model.
public protocol TLAMachineAdapterAccess: AnyObject, TLAMachineExecuting {
    associatedtype CanonicalModel: TLAMachineAdapterCanonicalModel

    func withCanonicalMachine<Result: Sendable>(
        _ operation: @escaping @Sendable (inout CanonicalModel) throws -> Result
    ) async rethrows -> Result
}

public extension TLAMachineAdapterAccess where TransitionResult == CanonicalModel.TransitionResult {
    func canonicalMachineObservation() async -> TLAMachineObservation {
        await withCanonicalMachine { canonical in
            canonical.synchronousMachineObservation()
        }
    }

    func executeCanonical(_ invocation: TLAActionInvocation) async throws -> TransitionResult {
        try await withCanonicalMachine { canonical in
            try canonical.executeSynchronously(invocation)
        }
    }

    func machineObservation() async -> TLAMachineObservation {
        await canonicalMachineObservation()
    }

    func execute(_ invocation: TLAActionInvocation) async throws -> TransitionResult {
        try await executeCanonical(invocation)
    }
}

public struct CanonicalMachine<Snapshot: Equatable & Sendable>: Sendable {
    public let runtime: SpecRuntime
    private let stateDictionary: @Sendable (Snapshot) -> [String: TLAValue]
    private let snapshotFromDictionary: @Sendable ([String: TLAValue]) throws -> Snapshot
    public private(set) var snapshot: Snapshot

    public init(
        runtime: SpecRuntime,
        initial: Snapshot,
        stateDictionary: @escaping @Sendable (Snapshot) -> [String: TLAValue],
        snapshotFromDictionary: @escaping @Sendable ([String: TLAValue]) throws -> Snapshot
    ) {
        self.runtime = runtime
        self.snapshot = initial
        self.stateDictionary = stateDictionary
        self.snapshotFromDictionary = snapshotFromDictionary
    }

    package func tlaSnapshot() -> [String: TLAValue] {
        stateDictionary(snapshot)
    }

    public func stateProjection() -> TLAStateProjectionResult {
        do {
            return .projected(try .init(formalValues: tlaSnapshot()))
        } catch let diagnostic as TLAStateProjectionDiagnostic {
            return .unavailable(diagnostic)
        } catch {
            return .unavailable(.projectionUnavailable(
                path: "state",
                reason: String(describing: error)
            ))
        }
    }

    public func availableInvocations() throws -> [TLAActionInvocation] {
        try availableInvocations(in: tlaSnapshot())
    }

    public func availableInvocations(in state: TLAStateProjection) throws -> [TLAActionInvocation] {
        try availableInvocations(in: state.values)
    }

    package func availableInvocations(in state: [String: TLAValue]) throws -> [TLAActionInvocation] {
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
        let projection: TLAStateProjectionResult
        do {
            projection = .projected(try .init(formalValues: state))
        } catch let diagnostic as TLAStateProjectionDiagnostic {
            return .init(
                state: .unavailable(diagnostic),
                availability: .unavailable(
                    .init(
                        code: .stateProjectionFailed,
                        message: diagnostic.description,
                        projectionDiagnostic: diagnostic
                    )
                )
            )
        } catch {
            let diagnostic = TLAStateProjectionDiagnostic.projectionUnavailable(
                path: "state",
                reason: String(describing: error)
            )
            return .init(
                state: .unavailable(diagnostic),
                availability: .unavailable(
                    .init(
                        code: .stateProjectionFailed,
                        message: diagnostic.description,
                        projectionDiagnostic: diagnostic
                    )
                )
            )
        }
        do {
            return .init(state: projection, availability: .available(try availableInvocations(in: state)))
        } catch {
            return .init(
                state: projection,
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
        from state: TLAStateProjection,
        selecting successor: (TLAStateProjection) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot> {
        let before: Snapshot
        do {
            before = try snapshotFromDictionary(state.values)
        } catch {
            throw GeneratedMachineError.unexpected(error)
        }
        let successors: [[String: TLAValue]]
        do {
            successors = try runtime.successors(invocation, from: state.values)
        } catch let error as SpecRuntime.RuntimeError {
            throw GeneratedMachineError.runtime(error)
        } catch {
            throw GeneratedMachineError.unexpected(error)
        }
        for candidate in successors {
            let projection: TLAStateProjection
            do {
                projection = try .init(formalValues: candidate)
            } catch let diagnostic as TLAStateProjectionDiagnostic {
                throw GeneratedMachineError.stateDecodingFailed(diagnostic)
            }
            guard successor(projection) else { continue }
            let after: Snapshot
            do {
                after = try snapshotFromDictionary(candidate)
            } catch let diagnostic as TLAStateProjectionDiagnostic {
                throw GeneratedMachineError.stateDecodingFailed(diagnostic)
            } catch {
                throw GeneratedMachineError.unexpected(error)
            }
            snapshot = after
            return CanonicalTransitionEvidence(invocation: invocation, before: before, after: after)
        }
        let available = try availableInvocations(in: state)
        throw GeneratedMachineError.runtime(.actionNotEnabled(invocation, available: available))
    }

    package mutating func apply(
        _ invocation: TLAActionInvocation,
        from state: [String: TLAValue],
        selecting successor: ([String: TLAValue]) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot> {
        let before: Snapshot
        do {
            before = try snapshotFromDictionary(state)
        } catch {
            throw GeneratedMachineError.unexpected(error)
        }
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
        let after: Snapshot
        do {
            after = try snapshotFromDictionary(next)
        } catch let diagnostic as TLAStateProjectionDiagnostic {
            throw GeneratedMachineError.stateDecodingFailed(diagnostic)
        } catch {
            throw GeneratedMachineError.unexpected(error)
        }
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

    package func tlaSnapshot() -> [String: TLAValue] {
        storage.withLock { $0.tlaSnapshot() }
    }

    public func stateProjection() -> TLAStateProjectionResult {
        storage.withLock { $0.stateProjection() }
    }

    public func availableInvocations() throws -> [TLAActionInvocation] {
        try storage.withLock { try $0.availableInvocations() }
    }

    public func availableInvocations(in state: TLAStateProjection) throws -> [TLAActionInvocation] {
        try storage.withLock { try $0.availableInvocations(in: state) }
    }

    package func availableInvocations(in state: [String: TLAValue]) throws -> [TLAActionInvocation] {
        try storage.withLock { try $0.availableInvocations(in: state) }
    }

    package func apply(
        _ invocation: TLAActionInvocation,
        from state: [String: TLAValue],
        selecting successor: @Sendable ([String: TLAValue]) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot> {
        try storage.withLock { try $0.apply(invocation, from: state, selecting: successor) }
    }

    public func apply(
        _ invocation: TLAActionInvocation,
        from state: TLAStateProjection,
        selecting successor: @Sendable (TLAStateProjection) -> Bool
    ) throws -> CanonicalTransitionEvidence<Snapshot> {
        try storage.withLock { try $0.apply(invocation, from: state, selecting: successor) }
    }
}
