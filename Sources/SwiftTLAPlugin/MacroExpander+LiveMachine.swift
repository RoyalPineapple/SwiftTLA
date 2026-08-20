import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateLiveMachineMembers(model: MacroCompilation) -> [DeclSyntax] {
        let typeName = model.typeName
        let hasActions = !model.machineSurface.actions.isEmpty
        let identityRoutedNames = model.machineSurface.collectionActions.keys.sorted()
            .map { "\"\($0)\"" }
            .joined(separator: ", ")

        let typedExecute: [String] = hasActions ? [
            """
                public func execute(_ action: ActionLabel, requestID: Foundation.UUID = Foundation.UUID()) async -> Outcome {
                    switch await _machine.execute(action, requestID: requestID) {
                    case .committed(let commit):
                        return .committed(TransitionResult(
                            action: action,
                            before: try! State(projection: commit.before.state),
                            after: try! State(projection: commit.after.state)
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
                    case rejected(TLALiveActionRejection)
                    case failed(TLALiveActionFailure)
                }
            """
        ] : []

        let liveMembers = ([
            """
                private let _machine: GeneratedLiveMachine<\(typeName)>

                public init(handle: TLALiveMachine) throws {
                    _machine = try GeneratedLiveMachine(handle: handle)
                }

                public var handle: TLALiveMachine { _machine.handle }

                public var identity: TLALiveMachineIdentity { _machine.identity }

                public var schema: MachineSchema { _machine.schema }

                public func current() async -> CurrentResult {
                    switch await _machine.current() {
                    case .snapshot(let snapshot):
                        return .snapshot(.init(
                            identity: snapshot.identity,
                            position: snapshot.position,
                            state: try! State(projection: snapshot.state)
                        ))
                    case .unavailable(let reason):
                        return .unavailable(reason)
                    }
                }

                public func execute(_ invocation: TLAActionInvocation, requestID: Foundation.UUID = Foundation.UUID()) async -> TLALiveActionOutcome {
                    await _machine.execute(invocation, requestID: requestID)
                }
            """,
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
            """,
        ] + outcomeType).joined(separator: "\n\n")

        return [
            DeclSyntax(stringLiteral: """
            public static func decodeState(_ projection: TLAStateProjection) throws {
                _ = try State(projection: projection)
            }
            """),
            DeclSyntax(stringLiteral: """
            public static let identityRoutedActionNames: Set<String> = [\(identityRoutedNames)]
            """),
            DeclSyntax(stringLiteral: """
            public struct Live: Sendable {
            \(liveMembers)
            }
            """)
        ]
    }
}
