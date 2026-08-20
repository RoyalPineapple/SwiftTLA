import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateLiveMachineMembers(model: MacroCompilation) -> [DeclSyntax] {
        let typeName = model.typeName
        let hasActions = model.machineSurface.actions.isEmpty == false
        let actionType = hasActions ? "ActionLabel" : "Never"

        let typedExecute: [String] = hasActions ? [
            """
                public func execute(_ action: ActionLabel, requestID: Foundation.UUID = Foundation.UUID()) async throws -> Outcome {
                    switch await _handle.execute(action, requestID: requestID) {
                    case .committed(let commit):
                        return .committed(TransitionResult(
                            action: action,
                            before: try State(projection: commit.before.state),
                            after: try State(projection: commit.after.state)
                        ))
                    case .rejected(let rejection):
                        return .rejected(rejection)
                    case .failed(let failure):
                        return .failed(failure)
                    }
                }
            """
        ] : []

        let outcomeType: [String] = hasActions ? [
            """
                public enum Outcome: Sendable, Equatable {
                    case committed(TransitionResult)
                    case rejected(TLALiveActionRejection<ActionLabel>)
                    case failed(TLALiveActionFailure<ActionLabel>)
                }
            """
        ] : []

        let liveDriver = hasActions ? """
            private static func _liveDriver() throws -> TLALiveMachineTransitionDriver<ActionLabel> {
                let executor = CompiledActionExecutor(
                    compilation: try Self.compiledSpecification(),
                    actionOrdinal: { Self._actionOrdinal(for: $0) },
                    arguments: { Self._actionArguments(for: $0) },
                    label: { Self._actionLabel(actionAt: $0, arguments: $1) }
                )
                return TLALiveMachineTransitionDriver(
                    successors: { state, action in
                        try executor.successors(for: action, from: state)
                    },
                    validateAction: { action in
                        Self._identityRoutedActionOrdinals.contains(Self._actionOrdinal(for: action))
                            ? .identityRoutedActionRequiresID
                            : nil
                    },
                    decodeState: { state in
                        _ = try State(projection: state)
                    }
                )
            }
            """ : """
            private static func _liveDriver() throws -> TLALiveMachineTransitionDriver<Never> {
                .init(
                    successors: { _, action in switch action {} },
                    validateAction: { action in switch action {} },
                    decodeState: { state in _ = try State(projection: state) }
                )
            }
            """

        let liveMembers = ([
            """
                private let _owner: TLALiveMachineOwner<\(actionType)>
                private let _handle: TLALiveMachine<\(actionType)>

                private init() throws {
                    let owner = try \(typeName)._makeLiveOwner()
                    _owner = owner
                    _handle = owner.handle
                }

                public var identity: TLALiveMachineIdentity { _handle.identity }

                public var schema: MachineSchema { _handle.schema }

                public func end() async {
                    await _owner.end()
                }

                fileprivate func _observe() async -> TLALiveMachineAttachmentOutcome<\(actionType)> {
                    await _handle.observe()
                }

                public func current() async throws -> CurrentResult {
                    switch await _handle.current() {
                    case .snapshot(let snapshot):
                        return .snapshot(.init(
                            identity: snapshot.identity,
                            position: snapshot.position,
                            state: try State(projection: snapshot.state)
                        ))
                    case .unavailable(let reason):
                        return .unavailable(reason)
                    }
                }
            """
        ] + typedExecute + [
            """
                public enum CurrentResult: Sendable, Equatable {
                    case snapshot(Snapshot)
                    case unavailable(TLALiveMachineUnavailableReason)

                    public struct Snapshot: Sendable, Equatable {
                        public let identity: TLALiveMachineIdentity
                        public let position: TLALiveMachinePosition
                        public let state: State

                        public init(
                            identity: TLALiveMachineIdentity,
                            position: TLALiveMachinePosition,
                            state: State
                        ) {
                            self.identity = identity
                            self.position = position
                            self.state = state
                        }
                    }
                }
            """
        ] + outcomeType).joined(separator: "\n\n")

        return [
            DeclSyntax(stringLiteral: liveDriver),
            DeclSyntax(stringLiteral: """
                private static func _makeLiveOwner() throws -> TLALiveMachineOwner<\(actionType)> {
                    let compilation = try compiledSpecification()
                    guard let initial = try compilation.initialStateProjections().first else {
                    throw GeneratedMachineError.noInitialState
                }
                _ = try State(projection: initial)
                return TLALiveMachineOwner.create(
                    schema: machineSchema,
                    initial: initial,
                    driver: try _liveDriver()
                )
            }
            """),
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
