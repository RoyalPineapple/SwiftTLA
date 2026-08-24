import Foundation

/// Storage for one generated Swift machine and its compiled specification.
public struct _GeneratedMachineStorage: Sendable {
    /// An opaque state from this storage's compiled specification.
    public struct State: Hashable, Sendable {
        fileprivate let compiled: CompiledState

        fileprivate init(_ compiled: CompiledState) {
            self.compiled = compiled
        }
    }

    /// Opaque action arguments passed between generated members and storage.
    public struct ActionArguments: Sendable {
        fileprivate let values: [TLAValue]

        public var count: Int { values.count }
        public var isEmpty: Bool { values.isEmpty }

        public func value<Value: TLAValueType>(
            at index: Int,
            as _: Value.Type = Value.self
        ) throws -> Value {
            guard values.indices.contains(index) else {
                throw GeneratedMachineError.invalidGeneratedActionOrdinal
            }
            return try _GeneratedMachineStorage.decode(values[index], at: "action argument \(index)")
        }

        public func matches(
            _ value: TLAValue,
            at index: Int
        ) -> Bool {
            values.indices.contains(index) && values[index] == value
        }
    }

    private let compilation: CompiledSpecification

    /// Creates generated-machine storage from one successful compilation.
    public init(compilation: CompiledSpecification) {
        self.compilation = compilation
    }

    /// Returns every initial state from the compiled specification.
    public func initialStates() throws -> [State] {
        try CompiledRuntime(compilation: compilation).initialStates().map(State.init)
    }

    /// Returns the declared initial state matching the generated state's values.
    public func initialState(matching predicate: (State) throws -> Bool) throws -> State {
        let matches = try CompiledRuntime(compilation: compilation).initialStates()
            .map(State.init)
            .filter(predicate)
        guard matches.count == 1 else {
            if matches.isEmpty {
                throw GeneratedMachineError.invalidInitialState
            }
            throw GeneratedMachineError.ambiguousInitialState
        }
        return matches[0]
    }

    /// Resolves one formal projection to a state owned by this storage.
    package func state(from projection: TLAStateProjection) throws -> State {
        State(try CompiledState(projection: projection, compilation: compilation))
    }

    /// Returns the guarded formal projection for one storage state.
    package func projection(of state: State) throws -> TLAStateProjection {
        try state.compiled.projection(using: compilation.layout)
    }

    /// Replaces one generated variable value in a storage state.
    public func replacing<Value: TLAValueConvertible>(
        value: Value,
        at variableOrdinal: Int,
        in state: State
    ) throws -> State {
        guard compilation.layout.variables.indices.contains(variableOrdinal) else {
            throw GeneratedMachineError.invalidGeneratedVariableOrdinal
        }
        let variable = compilation.layout.variables[variableOrdinal]
        let compiledValue = try CompiledValue(formal: value.tlaValue, using: compilation.layout)
        return State(try state.compiled.updating(variable.id, to: compiledValue))
    }

    /// Returns the formal value at one generated variable ordinal.
    public func value<Value: TLAValueType>(
        at variableOrdinal: Int,
        as _: Value.Type = Value.self,
        in state: State
    ) throws -> Value {
        guard compilation.layout.variables.indices.contains(variableOrdinal) else {
            throw GeneratedMachineError.invalidGeneratedVariableOrdinal
        }
        let variable = compilation.layout.variables[variableOrdinal]
        let formalValue = try state.compiled.value(for: variable.id).rendered(using: compilation.layout)
        return try Self.decode(formalValue, at: variable.declaration.name)
    }

    public func collectionValue<Value: TLAValueType, Member: TLAValueConvertible>(
        at variableOrdinal: Int,
        for member: Member,
        as _: Value.Type = Value.self,
        in state: State
    ) throws -> Value? {
        guard let value = try collectionValues(at: variableOrdinal, in: state)?[member.tlaValue] else {
            return nil
        }
        return try Self.decode(value, at: "collection member")
    }

    public func collectionChangesOnly<Member: TLAValueConvertible>(
        at variableOrdinal: Int,
        selected member: Member,
        from state: State,
        to candidate: State
    ) throws -> Bool {
        guard let original = try collectionValues(at: variableOrdinal, in: state),
              let values = try collectionValues(at: variableOrdinal, in: candidate),
              values[member.tlaValue] != nil else {
            return false
        }
        return values.allSatisfy { key, value in
            key == member.tlaValue || original[key] == value
        }
    }

    /// Returns every successor for one generated action call.
    public func successors(
        actionOrdinal: Int,
        arguments: [any TLAValueConvertible],
        from state: State
    ) throws -> [State] {
        let request = try request(actionOrdinal: actionOrdinal, arguments: arguments)
        return try CompiledRuntime(compilation: compilation)
            .successors(for: request.action, from: state.compiled)
            .filter { compilation.matches($0.arguments, request: request) }
            .map { State($0.state) }
    }

    /// Applies the only compiled successor for one generated action call.
    public func apply(
        actionOrdinal: Int,
        arguments: [any TLAValueConvertible],
        from state: State
    ) throws -> State {
        try Self.onlySuccessor(try successors(
            actionOrdinal: actionOrdinal,
            arguments: arguments,
            from: state
        ))
    }

    /// Resolves the generated actions enabled in one stored state.
    public func availableActions<Action: Hashable>(
        in state: State,
        resolve: (Int, ActionArguments) throws -> Action?
    ) throws -> [Action] {
        var seen = Set<Action>()
        return try CompiledRuntime(compilation: compilation)
            .successors(from: state.compiled)
            .compactMap { successor in
                let request = CompiledActionRequest(
                    action: successor.action,
                    arguments: successor.arguments
                )
                let input = try compilation.generatedActionInput(for: request)
                guard let action = try resolve(input.ordinal, .init(values: input.formalArguments)) else {
                    return nil
                }
                return seen.insert(action).inserted ? action : nil
            }
    }

    private func request(
        actionOrdinal: Int,
        arguments: [any TLAValueConvertible]
    ) throws -> CompiledActionRequest {
        guard compilation.layout.actions.indices.contains(actionOrdinal) else {
            throw GeneratedMachineError.invalidGeneratedActionOrdinal
        }
        return try compilation.actionRequest(
            ordinal: actionOrdinal,
            formalArguments: arguments.map(\.tlaValue)
        )
    }

    package static func onlySuccessor(_ candidates: [State]) throws -> State {
        switch candidates.count {
        case 0: throw GeneratedMachineError.noMatchingSuccessor
        case 1: return candidates[0]
        default: throw GeneratedMachineError.ambiguousAction
        }
    }

    package func successor(
        actionOrdinal: Int,
        arguments: [any TLAValueConvertible],
        from state: State,
        matching predicate: (State) throws -> Bool
    ) throws -> State {
        try Self.onlySuccessor(try successors(
            actionOrdinal: actionOrdinal,
            arguments: arguments,
            from: state
        ).filter(predicate))
    }

    private func collectionValues(
        at variableOrdinal: Int,
        in state: State
    ) throws -> [TLAValue: TLAValue]? {
        guard case .function(let values) = try value(
            at: variableOrdinal,
            as: TLAValue.self,
            in: state
        ) else {
            return nil
        }
        return values
    }

    private static func decode<Value: TLAValueType>(
        _ formalValue: TLAValue,
        at path: String
    ) throws -> Value {
        guard let value = Value(formalValue: formalValue) else {
            throw GeneratedMachineStateDiagnostic.typeMismatch(
                path: path,
                expected: String(reflecting: Value.self),
                actual: String(describing: formalValue)
            )
        }
        return value
    }
}

public extension _GeneratedMachineStorage {
    struct LiveSnapshot: Sendable, Equatable {
        public let identity: TLALiveMachineIdentity
        public let position: TLALiveMachinePosition
        public let state: State
    }

    enum LiveCurrent: Sendable, Equatable {
        case snapshot(LiveSnapshot)
        case unavailable(TLALiveMachineUnavailableReason)
    }

    enum LiveRejectionReason: Sendable, Equatable {
        case runtimeUnavailable(TLALiveMachineUnavailableReason)
        case actionNotEnabled
    }

    enum LiveFailureCode: String, Sendable, Equatable {
        case evaluationFailed
        case decodeFailed
        case positionExhausted
        case ambiguousAction
    }

    struct LiveRejection<Action: Sendable & Equatable>: Sendable, Equatable {
        public let requestID: UUID
        public let action: Action
        public let reason: LiveRejectionReason
        public let current: LiveSnapshot
    }

    struct LiveFailure<Action: Sendable & Equatable>: Sendable, Equatable {
        public let requestID: UUID
        public let action: Action
        public let code: LiveFailureCode
        public let message: String
        public let current: LiveSnapshot
    }

    struct LiveCommit<Action: Sendable & Equatable>: Sendable, Equatable {
        public let requestID: UUID
        public let action: Action
        public let before: LiveSnapshot
        public let after: LiveSnapshot
    }

    enum LiveOutcome<Action: Sendable & Equatable>: Sendable, Equatable {
        case committed(LiveCommit<Action>)
        case rejected(LiveRejection<Action>)
        case failed(LiveFailure<Action>)
    }

    final class LiveRuntime<Action: Sendable & Equatable>: Sendable {
        public let identity: TLALiveMachineIdentity
        private let owner: TLALiveMachineOwner<Action>
        private let handle: TLALiveMachine<Action>

        fileprivate init(_ owner: TLALiveMachineOwner<Action>) {
            self.owner = owner
            handle = owner.handle
            identity = owner.identity
        }

        public func current() async -> LiveCurrent {
            switch await handle.current() {
            case .snapshot(let snapshot): return .snapshot(Self.convert(snapshot))
            case .unavailable(let reason): return .unavailable(reason)
            }
        }

        public func execute(_ action: Action, requestID: UUID = UUID()) async -> LiveOutcome<Action> {
            switch await handle.execute(action, requestID: requestID) {
            case .committed(let commit): return .committed(Self.convert(commit))
            case .rejected(let rejection): return .rejected(Self.convert(rejection))
            case .failed(let failure): return .failed(Self.convert(failure))
            }
        }

        public func end() async {
            await owner.end()
        }

        fileprivate static func convert(_ snapshot: TLALiveMachineSnapshot) -> LiveSnapshot {
            .init(identity: snapshot.identity, position: snapshot.position, state: snapshot.state)
        }

        fileprivate static func convert(_ commit: TLALiveMachineCommit<Action>) -> LiveCommit<Action> {
            .init(requestID: commit.requestID, action: commit.action, before: convert(commit.before), after: convert(commit.after))
        }

        fileprivate static func convert(_ rejection: TLALiveActionRejection<Action>) -> LiveRejection<Action> {
            .init(requestID: rejection.requestID, action: rejection.action, reason: convert(rejection.reason), current: convert(rejection.current))
        }

        fileprivate static func convert(_ failure: TLALiveActionFailure<Action>) -> LiveFailure<Action> {
            .init(requestID: failure.requestID, action: failure.action, code: convert(failure.code), message: failure.message, current: convert(failure.current))
        }

        fileprivate static func convert(_ reason: TLALiveActionRejection<Action>.Reason) -> LiveRejectionReason {
            switch reason {
            case .runtimeUnavailable(let value): return .runtimeUnavailable(value)
            case .actionNotEnabled: return .actionNotEnabled
            }
        }

        fileprivate static func convert(_ code: TLALiveActionFailure<Action>.Code) -> LiveFailureCode {
            switch code {
            case .evaluationFailed: return .evaluationFailed
            case .decodeFailed: return .decodeFailed
            case .positionExhausted: return .positionExhausted
            case .ambiguousAction: return .ambiguousAction
            }
        }

    }

    func makeLive<Action: Sendable & Equatable>(
        initial: State,
        successors: @escaping @Sendable (State, Action) throws -> [State],
        decodeState: @escaping @Sendable (State) throws -> Void
    ) -> LiveRuntime<Action> {
        .init(.create(
            initial: initial,
            driver: .init(
                successors: successors,
                decodeState: decodeState
            )
        ))
    }
}
