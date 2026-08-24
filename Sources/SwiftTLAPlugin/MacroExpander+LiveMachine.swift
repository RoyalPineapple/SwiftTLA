import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateLiveMachineMembers(model: MacroCompilation) -> [DeclSyntax] {
        let typeName = model.typeName
        let hasActions = model.machineSurface.actions.isEmpty == false
        let actionType = "Action"

        let typedExecute = """
                public func send(_ action: Action, requestID: Foundation.UUID = Foundation.UUID()) async throws -> Outcome {
                    switch await _runtime.execute(action, requestID: requestID) {
                    case .committed(let commit):
                        return .committed(Transition(
                            action: action,
                            before: try State(storage: _storage, storageState: commit.before.state),
                            after: try State(storage: _storage, storageState: commit.after.state)
                        ))
                    case .rejected(let rejection): return .rejected(try Self._rejection(rejection, storage: _storage))
                    case .failed(let failure): return .failed(try Self._failure(failure, storage: _storage))
                    }
                }
            """

        let outcomeType = """
                public struct Identity: Sendable, Equatable {
                    public let value: Foundation.UUID

                    public init(value: Foundation.UUID) {
                        self.value = value
                    }
                }

                public struct Position: Sendable, Equatable, Comparable {
                    public let value: UInt64

                    public init(value: UInt64) {
                        self.value = value
                    }

                    public static func < (lhs: Self, rhs: Self) -> Bool {
                        lhs.value < rhs.value
                    }
                }

                public enum Unavailability: Sendable, Equatable, CustomStringConvertible {
                    case endedByOwner

                    public var description: String {
                        switch self {
                        case .endedByOwner: return "The live machine was ended by its owner."
                        }
                    }
                }

                public struct Snapshot: Sendable, Equatable {
                    public let identity: Identity
                    public let position: Position
                    public let state: State

                    public init(identity: Identity, position: Position, state: State) {
                        self.identity = identity
                        self.position = position
                        self.state = state
                    }
                }

                public enum RejectionReason: Sendable, Equatable, CustomStringConvertible {
                    case runtimeUnavailable(Unavailability)
                    case actionNotEnabled

                    public var description: String {
                        switch self {
                        case .runtimeUnavailable(let reason): return "The live machine cannot execute the request: \\(reason)"
                        case .actionNotEnabled: return "The requested action is not enabled in the current state."
                        }
                    }
                }

                public enum FailureCode: String, Sendable, Equatable {
                    case evaluationFailed
                    case decodeFailed
                    case positionExhausted
                    case ambiguousAction
                }

                public struct Rejection: Sendable, Equatable {
                    public let requestID: Foundation.UUID
                    public let action: Action
                    public let reason: RejectionReason
                    public let current: Snapshot
                }

                public struct Failure: Sendable, Equatable {
                    public let requestID: Foundation.UUID
                    public let action: Action
                    public let code: FailureCode
                    public let message: String
                    public let current: Snapshot
                }

                public enum Outcome: Sendable, Equatable {
                    case committed(Transition)
                    case rejected(Rejection)
                    case failed(Failure)
                }
            """

        let liveConversions = """
                private static func _identity(_ value: TLALiveMachineIdentity) -> Identity {
                    .init(value: value.value)
                }

                private static func _position(_ value: TLALiveMachinePosition) -> Position {
                    .init(value: value.value)
                }

                private static func _unavailability(_ value: TLALiveMachineUnavailableReason) -> Unavailability {
                    switch value {
                    case .endedByOwner: return .endedByOwner
                    }
                }

                private static func _snapshot(
                    _ value: _GeneratedMachineStorage.LiveSnapshot,
                    storage: _GeneratedMachineStorage
                ) throws -> Snapshot {
                    try .init(
                        identity: _identity(value.identity),
                        position: _position(value.position),
                        state: State(storage: storage, storageState: value.state)
                    )
                }

                private static func _rejection(
                    _ value: _GeneratedMachineStorage.LiveRejection<Action>,
                    storage: _GeneratedMachineStorage
                ) throws -> Rejection {
                    let reason: RejectionReason
                    switch value.reason {
                    case .runtimeUnavailable(let unavailability): reason = .runtimeUnavailable(Self._unavailability(unavailability))
                    case .actionNotEnabled: reason = .actionNotEnabled
                    }
                    return try .init(
                        requestID: value.requestID,
                        action: value.action,
                        reason: reason,
                        current: _snapshot(value.current, storage: storage)
                    )
                }

                private static func _failure(
                    _ value: _GeneratedMachineStorage.LiveFailure<Action>,
                    storage: _GeneratedMachineStorage
                ) throws -> Failure {
                    let code: FailureCode
                    switch value.code {
                    case .evaluationFailed: code = .evaluationFailed
                    case .decodeFailed: code = .decodeFailed
                    case .positionExhausted: code = .positionExhausted
                    case .ambiguousAction: code = .ambiguousAction
                    }
                    return try .init(
                        requestID: value.requestID,
                        action: value.action,
                        code: code,
                        message: value.message,
                        current: _snapshot(value.current, storage: storage)
                    )
                }
            """

        let liveDriver = hasActions ? """
            private static func _makeLiveRuntime(
                storage: _GeneratedMachineStorage
            ) throws -> _GeneratedMachineStorage.LiveRuntime<Action> {
                guard let initial = try storage.initialStates().first else {
                    throw GeneratedMachineError.noInitialState
                }
                return storage.makeLive(
                    initial: initial,
                    successors: { state, action in
                        try Self._successors(for: action, from: state, storage: storage)
                    },
                    decodeState: { state in
                        _ = try State(storage: storage, storageState: state)
                    }
                )
            }
            """ : """
            private static func _makeLiveRuntime(
                storage: _GeneratedMachineStorage
            ) throws -> _GeneratedMachineStorage.LiveRuntime<Action> {
                guard let initial = try storage.initialStates().first else {
                    throw GeneratedMachineError.noInitialState
                }
                return storage.makeLive(
                    initial: initial,
                    successors: { _, action in switch action {} },
                    decodeState: { _ in }
                )
            }
            """

        let liveMembers = ([
            """
                private let _runtime: _GeneratedMachineStorage.LiveRuntime<\(actionType)>
                fileprivate let _storage: _GeneratedMachineStorage

                fileprivate init() throws {
                    let storage = _GeneratedMachineStorage(compilation: try \(typeName)._compiledSpecification())
                    _runtime = try \(typeName)._makeLiveRuntime(storage: storage)
                    _storage = storage
                }

                public var identity: Identity { Self._identity(_runtime.identity) }

                public func end() async {
                    await _runtime.end()
                }

                public func current() async throws -> CurrentResult {
                    switch await _runtime.current() {
                    case .snapshot(let snapshot):
                        return .snapshot(.init(
                            identity: Self._identity(snapshot.identity),
                            position: Self._position(snapshot.position),
                            state: try State(storage: _storage, storageState: snapshot.state)
                        ))
                    case .unavailable(let reason):
                        return .unavailable(Self._unavailability(reason))
                    }
                }
            """
        ] + [typedExecute, liveConversions, """
                public enum CurrentResult: Sendable, Equatable {
                    case snapshot(Snapshot)
                    case unavailable(Unavailability)
                }
            """, outcomeType]).joined(separator: "\n\n")

        return [
            DeclSyntax(stringLiteral: liveDriver),
            DeclSyntax(stringLiteral: """
            public static func makeLive() throws -> Live {
                try Live()
            }
            """),
            DeclSyntax(stringLiteral: """
            public struct Live: Sendable {
            \(liveMembers)
            }
            """)
        ]
    }
}
