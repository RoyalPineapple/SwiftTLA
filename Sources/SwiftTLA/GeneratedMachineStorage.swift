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

        public func matches<Value: TLAValueConvertible>(
            _ value: Value,
            at index: Int
        ) -> Bool {
            values.indices.contains(index) && values[index] == value.tlaValue
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

    /// Applies the first compiled successor for one generated action call.
    public func apply(
        actionOrdinal: Int,
        arguments: [any TLAValueConvertible],
        from state: State,
        selecting successor: (State) throws -> Bool = { _ in true }
    ) throws -> State {
        for after in try successors(
            actionOrdinal: actionOrdinal,
            arguments: arguments,
            from: state
        ) {
            guard try successor(after) else { continue }
            return after
        }
        throw GeneratedMachineError.noMatchingSuccessor
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
                let input = try compilation.generatedActionLabelInput(for: request)
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
        case identityRoutedActionRequiresID
    }

    enum LiveFailureCode: String, Sendable, Equatable {
        case evaluationFailed
        case decodeFailed
        case positionExhausted
        case ambiguousSuccessors
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

    enum LiveEvent<Action: Sendable & Equatable>: Sendable, Equatable {
        case snapshot(LiveSnapshot, attached: Bool)
        case update(LiveCommit<Action>)
        case loss(LiveObservationLoss)
        case terminated(LiveTermination)
    }

    enum LiveAttachment<Action: Sendable & Equatable>: Sendable {
        case attached(LiveSubscription<Action>)
        case unavailable(TLALiveMachineUnavailableReason)
    }

    struct LiveObservationLoss: Sendable, Equatable {
        public let identity: TLALiveMachineIdentity
        public let lastContiguousPosition: TLALiveMachinePosition
        public let latestKnownPosition: TLALiveMachinePosition
    }

    struct LiveTermination: Sendable, Equatable {
        public let identity: TLALiveMachineIdentity
        public let finalPosition: TLALiveMachinePosition
        public let reason: TLALiveMachineUnavailableReason
    }

    enum LiveResynchronization: Sendable, Equatable {
        case resumed(at: TLALiveMachinePosition)
        case terminated(LiveTermination)
        case cancelled
    }

    final class LiveSubscription<Action: Sendable & Equatable>: AsyncSequence, Sendable {
        public typealias Element = LiveEvent<Action>

        private let base: TLALiveMachineObservationSubscription<Action>

        fileprivate init(_ base: TLALiveMachineObservationSubscription<Action>) {
            self.base = base
        }

        public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
            private var base: TLALiveMachineObservationSubscription<Action>.AsyncIterator

            fileprivate init(_ base: TLALiveMachineObservationSubscription<Action>.AsyncIterator) {
                self.base = base
            }

            public mutating func next() async -> LiveEvent<Action>? {
                guard let event = await base.next() else { return nil }
                return LiveRuntime<Action>.convert(event)
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            .init(base.makeAsyncIterator())
        }

        public func resynchronize() async -> LiveResynchronization {
            switch await base.resynchronize() {
            case .resumed(let position): return .resumed(at: position)
            case .terminated(let termination): return .terminated(LiveRuntime<Action>.convert(termination))
            case .cancelled: return .cancelled
            }
        }

        public func cancel() async {
            await base.cancel()
        }
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

        public func observe() async -> LiveAttachment<Action> {
            switch await handle.observe() {
            case .attached(let subscription): return .attached(.init(subscription))
            case .unavailable(let reason): return .unavailable(reason)
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

        fileprivate static func convert(_ event: TLALiveMachineObservationEvent<Action>) -> LiveEvent<Action> {
            switch event {
            case .snapshot(let snapshot, let reason):
                return .snapshot(convert(snapshot), attached: reason == .attached)
            case .update(let commit): return .update(convert(commit))
            case .loss(let loss): return .loss(convert(loss))
            case .terminated(let termination): return .terminated(convert(termination))
            }
        }

        fileprivate static func convert(_ reason: TLALiveActionRejection<Action>.Reason) -> LiveRejectionReason {
            switch reason {
            case .runtimeUnavailable(let value): return .runtimeUnavailable(value)
            case .actionNotEnabled: return .actionNotEnabled
            case .identityRoutedActionRequiresID: return .identityRoutedActionRequiresID
            }
        }

        fileprivate static func convert(_ code: TLALiveActionFailure<Action>.Code) -> LiveFailureCode {
            switch code {
            case .evaluationFailed: return .evaluationFailed
            case .decodeFailed: return .decodeFailed
            case .positionExhausted: return .positionExhausted
            case .ambiguousSuccessors: return .ambiguousSuccessors
            }
        }

        fileprivate static func convert(_ loss: TLALiveMachineObservationLoss) -> LiveObservationLoss {
            .init(identity: loss.identity, lastContiguousPosition: loss.lastContiguousPosition, latestKnownPosition: loss.latestKnownPosition)
        }

        fileprivate static func convert(_ termination: TLALiveMachineTermination) -> LiveTermination {
            .init(identity: termination.identity, finalPosition: termination.finalPosition, reason: termination.reason)
        }
    }

    enum LiveAdapterStatus: Sendable, Equatable {
        case attaching
        case current(TLALiveMachinePosition)
        case recovering(LiveObservationLoss)
        case terminated(LiveTermination)
        case invalidEvent(String)
    }

    struct LiveAdapterSnapshot<Value: Sendable & Equatable>: Sendable, Equatable {
        public let identity: TLALiveMachineIdentity
        public let position: TLALiveMachinePosition
        public let state: Value
    }

    @MainActor
    final class LiveObservableReducer<Value: Sendable & Equatable, Action: Sendable & Equatable>: Sendable {
        public private(set) var status: LiveAdapterStatus = .attaching
        public private(set) var current: LiveAdapterSnapshot<Value>?

        private let identity: TLALiveMachineIdentity
        private let decode: @Sendable (State) throws -> Value

        public init(
            identity: TLALiveMachineIdentity,
            decode: @escaping @Sendable (State) throws -> Value
        ) {
            self.identity = identity
            self.decode = decode
        }

        @discardableResult
        public func reduce(_ event: LiveEvent<Action>) -> LiveCommit<Action>? {
            switch event {
            case .snapshot(let snapshot, _):
                guard validate(snapshot) else { return nil }
                do {
                    current = .init(identity: identity, position: snapshot.position, state: try decode(snapshot.state))
                    status = .current(snapshot.position)
                } catch {
                    current = nil
                    status = .invalidEvent("The runtime snapshot could not decode as generated State: \(error)")
                }
                return nil
            case .update(let commit):
                guard validate(commit.before), validate(commit.after) else { return nil }
                guard case .current(let position) = status, position == commit.before.position,
                      commit.after.position == commit.before.position.next else {
                    current = nil
                    status = .invalidEvent("The runtime update was not contiguous with the adapter cache.")
                    return nil
                }
                do {
                    current = .init(identity: identity, position: commit.after.position, state: try decode(commit.after.state))
                    status = .current(commit.after.position)
                    return commit
                } catch {
                    current = nil
                    status = .invalidEvent("The committed runtime state could not decode as generated State: \(error)")
                    return nil
                }
            case .loss(let loss):
                guard loss.identity == identity else {
                    current = nil
                    status = .invalidEvent("The observation loss belongs to a different runtime identity.")
                    return nil
                }
                current = nil
                status = .recovering(loss)
                return nil
            case .terminated(let termination):
                guard termination.identity == identity else {
                    current = nil
                    status = .invalidEvent("The termination belongs to a different runtime identity.")
                    return nil
                }
                current = nil
                status = .terminated(termination)
                return nil
            }
        }

        private func validate(_ snapshot: LiveSnapshot) -> Bool {
            guard snapshot.identity == identity else {
                current = nil
                status = .invalidEvent("The observation belongs to a different runtime identity.")
                return false
            }
            return true
        }
    }

    func makeLive<Action: Sendable & Equatable>(
        initial: State,
        successors: @escaping @Sendable (State, Action) throws -> [State],
        validateAction: @escaping @Sendable (Action) -> LiveRejectionReason?,
        decodeState: @escaping @Sendable (State) throws -> Void
    ) -> LiveRuntime<Action> {
        .init(.create(
            initial: initial,
            driver: .init(
                successors: successors,
                validateAction: { action in
                    guard let reason = validateAction(action) else { return nil }
                    switch reason {
                    case .runtimeUnavailable(let value): return .runtimeUnavailable(value)
                    case .actionNotEnabled: return .actionNotEnabled
                    case .identityRoutedActionRequiresID: return .identityRoutedActionRequiresID
                    }
                },
                decodeState: decodeState
            )
        ))
    }
}
