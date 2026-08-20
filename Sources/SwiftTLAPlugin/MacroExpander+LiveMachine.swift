import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateLiveMachineMembers(model: MacroCompilation) -> [DeclSyntax] {
        let typeName = model.typeName
        let hasActions = model.machineSurface.actions.isEmpty == false

        let typedExecute: [String] = hasActions ? [
            """
                public func execute(_ action: ActionLabel, requestID: Foundation.UUID = Foundation.UUID()) async throws -> Outcome {
                    switch await _handle.execute(\(typeName)._liveInvocation(for: action), requestID: requestID) {
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
                    case rejected(TLALiveActionRejection)
                    case failed(TLALiveActionFailure)
                }
            """
        ] : []

        let liveMembers = ([
            """
                private let _owner: TLALiveMachineOwner
                private let _handle: TLALiveMachine

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

                fileprivate func _observe() async -> TLALiveMachineAttachmentOutcome {
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
            DeclSyntax(stringLiteral: """
            private static func _liveDriver(_ runtime: SpecRuntime) -> TLALiveMachineTransitionDriver {
                let actions = Dictionary(uniqueKeysWithValues: runtime.spec.actions.map { ($0.name, $0) })
                let identityRouted = _identityRoutedActionOrdinals
                let actionOrdinal = { invocation in
                    _machineSurfacePlan.actions.firstIndex(where: { $0.formalName == invocation.name })
                }
                return TLALiveMachineTransitionDriver(
                    successors: { state, invocation in
                        try runtime.successors(invocation, from: state)
                    },
                    availableInvocations: { state in
                        try runtime.availableInvocations(in: state).filter { invocation in
                            actionOrdinal(invocation).map { identityRouted.contains($0) } == false
                        }
                    },
                    validateInvocation: { invocation in
                        guard let ordinal = actionOrdinal(invocation),
                              let action = actions[invocation.name] else { return .unknownAction }
                        guard action.bindings.count == invocation.arguments.count else { return .invalidArity }
                        for (binding, argument) in zip(action.bindings, invocation.arguments)
                        where binding.values.contains(argument) == false {
                            return .actionArgumentOutOfDomain
                        }
                        return identityRouted.contains(ordinal)
                            ? .identityRoutedActionRequiresID
                            : nil
                    },
                    decodeState: { state in
                        _ = try State(projection: state)
                    }
                )
            }
            """),
            DeclSyntax(stringLiteral: """
            private static func _makeLiveOwner() throws -> TLALiveMachineOwner {
                let runtime = try _runtime()
                guard let initial = try runtime.initialStateProjections().first else {
                    throw GeneratedMachineError.noInitialState
                }
                _ = try State(projection: initial)
                return TLALiveMachineOwner.create(
                    schema: machineSchema,
                    initial: initial,
                    driver: _liveDriver(runtime)
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
