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
            DeclSyntax(stringLiteral: "public typealias CanonicalModel = \(modelTypeName)"),
            DeclSyntax(stringLiteral: "public typealias State = \(modelTypeName).State"),
            DeclSyntax(stringLiteral: "public typealias Live = \(modelTypeName).Live"),
            DeclSyntax(stringLiteral: "public typealias ActionLabel = \(modelTypeName).ActionLabel"),
            DeclSyntax(stringLiteral: "public typealias Outcome = \(modelTypeName).Live.Outcome"),
            DeclSyntax(stringLiteral: "public static var machineSchema: MachineSchema { CanonicalModel.machineSchema }"),
            DeclSyntax(stringLiteral: "public static var generatedMachineMetadata: GeneratedMachineMetadata { CanonicalModel.generatedMachineMetadata }")
        ]
    }

    static func generateNestedActorMembers(modelTypeName: String) -> [DeclSyntax] {
        var declarations = commonAdapterAliases(modelTypeName: modelTypeName)
        declarations += [
            DeclSyntax(stringLiteral: "private let _live: Live"),
            DeclSyntax(stringLiteral: "public init(live: Live) { _live = live }"),
            DeclSyntax(stringLiteral: "public var identity: TLALiveMachineIdentity { _live.identity }"),
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
            DeclSyntax(stringLiteral: "@MainActor private let _reducer: TLALiveMachineObservableReducer<State, \(actionType)>"),
            DeclSyntax(stringLiteral: "@MainActor private let _subscription: TLALiveMachineObservationSubscription<\(actionType)>"),
            DeclSyntax(stringLiteral: "@MainActor private var _observationTask: Task<Void, Never>?"),
            DeclSyntax(stringLiteral: """
            @MainActor public init(live: Live) async throws {
                _live = live
                _reducer = TLALiveMachineObservableReducer<State, \(actionType)>(
                    identity: live.identity,
                    decode: { try State(projection: $0) }
                )
                let subscription: TLALiveMachineObservationSubscription<\(actionType)>
                switch await live._observe() {
                case .attached(let attachment): subscription = attachment
                case .unavailable(let reason): throw GeneratedMachineError.liveMachineUnavailable(reason)
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
            DeclSyntax(stringLiteral: "@MainActor public var identity: TLALiveMachineIdentity { _live.identity }"),
            DeclSyntax(stringLiteral: "@MainActor public var status: TLALiveMachineAdapterStatus { _reducer.status }"),
            DeclSyntax(stringLiteral: "@MainActor public var current: TLALiveMachineAdapterSnapshot<State>? { _reducer.current }"),
            DeclSyntax(stringLiteral: "@MainActor public var state: State? { _reducer.current?.state }"),
            DeclSyntax(stringLiteral: """
            @MainActor public func cancelObservation() async {
                _observationTask?.cancel()
                await _subscription.cancel()
            }
            """),
            DeclSyntax(stringLiteral: observableReducerMethod())
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
        @MainActor private func _reduce(_ event: TLALiveMachineObservationEvent<ActionLabel>, subscription: TLALiveMachineObservationSubscription<ActionLabel>) async {
            let contiguousCommit = _reducer.reduce(event)
            if case .loss = event { _ = await subscription.resynchronize() }
            guard let commit = contiguousCommit,
                  let before = try? State(projection: commit.before.state),
                  let after = try? State(projection: commit.after.state) else { return }
            if let onTransition { await onTransition(commit.action, before, after) }
        }
        """
    }
}
