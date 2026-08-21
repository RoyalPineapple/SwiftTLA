import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

enum NestedAdapterKind { case actor, observable }

extension MacroExpander {
    static func generateNestedAdapterMembers(
        kind: NestedAdapterKind,
        canonicalModelTypeName: String
    ) -> [DeclSyntax] {
        switch kind {
        case .actor: return generateNestedActorMembers(modelTypeName: canonicalModelTypeName)
        case .observable: return generateNestedObservableMembers(modelTypeName: canonicalModelTypeName)
        }
    }

    static func commonAdapterAliases(modelTypeName: String) -> [DeclSyntax] {
        [
            DeclSyntax(stringLiteral: "public typealias State = \(modelTypeName).State"),
            DeclSyntax(stringLiteral: "public typealias Live = \(modelTypeName).Live"),
            DeclSyntax(stringLiteral: "public typealias ActionLabel = \(modelTypeName).ActionLabel"),
            DeclSyntax(stringLiteral: "public typealias Outcome = \(modelTypeName).Live.Outcome")
        ]
    }

    static func generateNestedActorMembers(modelTypeName: String) -> [DeclSyntax] {
        var declarations = commonAdapterAliases(modelTypeName: modelTypeName)
        declarations += [
            DeclSyntax(stringLiteral: "private let _live: Live"),
            DeclSyntax(stringLiteral: "public init(live: Live) { _live = live }"),
            DeclSyntax(stringLiteral: "public var identity: Live.Identity { _live.identity }"),
            DeclSyntax(stringLiteral: "public func current() async throws -> Live.CurrentResult { try await _live.current() }")
        ]
        declarations += typedAdapterExecution(receiver: "_live")
        return declarations
    }

    static func generateNestedObservableMembers(modelTypeName: String) -> [DeclSyntax] {
        let actionType = "ActionLabel"
        var declarations = commonAdapterAliases(modelTypeName: modelTypeName) + observableCallbacks()
        declarations += [
            DeclSyntax(stringLiteral: "@MainActor private let _live: Live"),
            DeclSyntax(stringLiteral: "@MainActor private let _reducer: _GeneratedMachineStorage.LiveObservableReducer<State, \(actionType)>"),
            DeclSyntax(stringLiteral: "@MainActor private let _subscription: _GeneratedMachineStorage.LiveSubscription<\(actionType)>"),
            DeclSyntax(stringLiteral: "@MainActor private var _observationTask: Task<Void, Never>?"),
            DeclSyntax(stringLiteral: """
            @MainActor public init(live: Live) async throws {
                _live = live
                _reducer = _GeneratedMachineStorage.LiveObservableReducer<State, \(actionType)>(
                    identity: live.identity,
                    decode: { try State(storage: live._storage, storageState: $0) }
                )
                let subscription: _GeneratedMachineStorage.LiveSubscription<\(actionType)>
                switch await live._observe() {
                case .attached(let attachment): subscription = attachment
                case .unavailable(let reason): throw GeneratedMachineError.liveMachineUnavailable(String(describing: reason))
                }
                _subscription = subscription
                _observationTask = Task { [weak self, subscription] in
                    var iterator = subscription.makeAsyncIterator()
                    while let event = await iterator.next() {
                        guard let self else { return }
                        await self._reduce(event, subscription: subscription)
                    }
                }
            }
            """),
            DeclSyntax(stringLiteral: "deinit { _observationTask?.cancel() }"),
            DeclSyntax(stringLiteral: "@MainActor public var identity: Live.Identity { _live.identity }"),
            DeclSyntax(stringLiteral: "@MainActor public var status: Status { Self._status(_reducer.status) }"),
            DeclSyntax(stringLiteral: "@MainActor public var current: Snapshot? { _reducer.current.map(Self._snapshot) }"),
            DeclSyntax(stringLiteral: "@MainActor public var state: State? { _reducer.current?.state }"),
            DeclSyntax(stringLiteral: """
            @MainActor public func cancelObservation() async {
                _observationTask?.cancel()
                await _subscription.cancel()
            }
            """),
            DeclSyntax(stringLiteral: observableReducerMethod()),
            DeclSyntax(stringLiteral: observablePublicTypes()),
            DeclSyntax(stringLiteral: observableConversions())
        ]
        declarations += typedAdapterExecution(receiver: "_live", actorIsolated: true)
        return declarations
    }

    static func typedAdapterExecution(
        receiver: String,
        actorIsolated: Bool = false
    ) -> [DeclSyntax] {
        let isolation = actorIsolated ? "@MainActor " : ""
        return [DeclSyntax(stringLiteral: """
        \(isolation)public func apply(_ action: ActionLabel, requestID: Foundation.UUID = Foundation.UUID()) async throws -> Outcome {
            try await \(receiver).execute(action, requestID: requestID)
        }
        """)]
    }

    static func observableCallbacks() -> [DeclSyntax] {
        [DeclSyntax(stringLiteral: "@MainActor public var onTransition: ((ActionLabel, State, State) async -> Void)?")]
    }

    static func observableReducerMethod() -> String {
        return """
        @MainActor private func _reduce(_ event: _GeneratedMachineStorage.LiveEvent<ActionLabel>, subscription: _GeneratedMachineStorage.LiveSubscription<ActionLabel>) async {
            let contiguousCommit = _reducer.reduce(event)
            if case .loss = event { _ = await subscription.resynchronize() }
            guard let commit = contiguousCommit,
                  let before = try? State(storage: _live._storage, storageState: commit.before.state),
                  let after = try? State(storage: _live._storage, storageState: commit.after.state) else { return }
            if let onTransition { await onTransition(commit.action, before, after) }
        }
        """
    }

    static func observablePublicTypes() -> String {
        """
        public struct Snapshot: Sendable, Equatable {
            public let identity: Live.Identity
            public let position: Live.Position
            public let state: State

            public init(identity: Live.Identity, position: Live.Position, state: State) {
                self.identity = identity
                self.position = position
                self.state = state
            }
        }

        public struct ObservationLoss: Sendable, Equatable {
            public let identity: Live.Identity
            public let lastContiguousPosition: Live.Position
            public let latestKnownPosition: Live.Position

            public init(
                identity: Live.Identity,
                lastContiguousPosition: Live.Position,
                latestKnownPosition: Live.Position
            ) {
                self.identity = identity
                self.lastContiguousPosition = lastContiguousPosition
                self.latestKnownPosition = latestKnownPosition
            }
        }

        public struct Termination: Sendable, Equatable {
            public let identity: Live.Identity
            public let finalPosition: Live.Position
            public let reason: Live.Unavailability

            public init(identity: Live.Identity, finalPosition: Live.Position, reason: Live.Unavailability) {
                self.identity = identity
                self.finalPosition = finalPosition
                self.reason = reason
            }
        }

        public enum Status: Sendable, Equatable {
            case attaching
            case current(Live.Position)
            case recovering(ObservationLoss)
            case terminated(Termination)
            case invalidEvent(String)
        }
        """
    }

    static func observableConversions() -> String {
        """
        @MainActor private static func _snapshot(
            _ value: _GeneratedMachineStorage.LiveAdapterSnapshot<State>
        ) -> Snapshot {
            .init(
                identity: .init(value: value.identity.value),
                position: .init(value: value.position.value),
                state: value.state
            )
        }

        @MainActor private static func _loss(
            _ value: _GeneratedMachineStorage.LiveObservationLoss
        ) -> ObservationLoss {
            .init(
                identity: .init(value: value.identity.value),
                lastContiguousPosition: .init(value: value.lastContiguousPosition.value),
                latestKnownPosition: .init(value: value.latestKnownPosition.value)
            )
        }

        @MainActor private static func _termination(
            _ value: _GeneratedMachineStorage.LiveTermination
        ) -> Termination {
            let reason: Live.Unavailability
            switch value.reason {
            case .endedByOwner: reason = .endedByOwner
            }
            return .init(
                identity: .init(value: value.identity.value),
                finalPosition: .init(value: value.finalPosition.value),
                reason: reason
            )
        }

        @MainActor private static func _status(
            _ value: _GeneratedMachineStorage.LiveAdapterStatus
        ) -> Status {
            switch value {
            case .attaching: return .attaching
            case .current(let position): return .current(.init(value: position.value))
            case .recovering(let loss): return .recovering(_loss(loss))
            case .terminated(let termination): return .terminated(_termination(termination))
            case .invalidEvent(let message): return .invalidEvent(message)
            }
        }
        """
    }
}
