import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

enum NestedAdapterKind { case actor, observable }

extension MacroExpander {
    static func generateNestedAdapterMembers(
        kind: NestedAdapterKind,
        canonicalModel: MacroCompilation
    ) -> [DeclSyntax] {
        switch kind {
        case .actor: return generateNestedActorMembers(model: canonicalModel)
        case .observable: return generateNestedObservableMembers(model: canonicalModel)
        }
    }

    static func commonAdapterAliases(model: MacroCompilation) -> [DeclSyntax] {
        var declarations: [DeclSyntax] = [
            DeclSyntax(stringLiteral: "public typealias CanonicalModel = \(model.typeName)"),
            DeclSyntax(stringLiteral: "public typealias State = \(model.typeName).State"),
            DeclSyntax(stringLiteral: "public typealias Live = \(model.typeName).Live"),
            DeclSyntax(stringLiteral: "public static var machineSchema: MachineSchema { CanonicalModel.machineSchema }"),
            DeclSyntax(stringLiteral: "public static var generatedMachineMetadata: GeneratedMachineMetadata { CanonicalModel.generatedMachineMetadata }")
        ]
        if model.machineSurface.actions.isEmpty == false {
            declarations.insert(DeclSyntax(stringLiteral: "public typealias ActionLabel = \(model.typeName).ActionLabel"), at: 3)
            declarations.insert(DeclSyntax(stringLiteral: "public typealias Outcome = \(model.typeName).Live.Outcome"), at: 4)
        }
        return declarations
    }

    static func generateNestedActorMembers(model: MacroCompilation) -> [DeclSyntax] {
        var declarations = commonAdapterAliases(model: model)
        declarations += [
            DeclSyntax(stringLiteral: "private let _live: Live"),
            DeclSyntax(stringLiteral: "public init(live: Live) { _live = live }"),
            DeclSyntax(stringLiteral: "public var identity: TLALiveMachineIdentity { _live.identity }"),
            DeclSyntax(stringLiteral: "public func current() async throws -> Live.CurrentResult { try await _live.current() }")
        ]
        declarations += typedAdapterExecution(model: model, receiver: "_live")
        return declarations
    }

    static func generateNestedObservableMembers(model: MacroCompilation) -> [DeclSyntax] {
        let actionType = model.machineSurface.actions.isEmpty ? "Never" : "ActionLabel"
        var declarations = commonAdapterAliases(model: model) + observableCallbacks(model: model)
        declarations += [
            DeclSyntax(stringLiteral: "private let _live: Live"),
            DeclSyntax(stringLiteral: "private let _reducer: TLALiveMachineObservableReducer<State, \(actionType)>"),
            DeclSyntax(stringLiteral: "private let _subscription: TLALiveMachineObservationSubscription<\(actionType)>"),
            DeclSyntax(stringLiteral: "private var _observationTask: Task<Void, Never>?"),
            DeclSyntax(stringLiteral: """
            @MainActor public init(live: Live) async throws {
                _live = live
                _reducer = TLALiveMachineObservableReducer<State, \(actionType)>(
                    identity: live.identity,
                    schemaIdentifier: live.schema.identifier,
                    decode: { try State(projection: $0) }
                )
                switch await live._observe() {
                case .attached(let subscription): _subscription = subscription
                case .unavailable(let reason): throw GeneratedMachineError.liveMachineUnavailable(reason)
                }
                _observationTask = Task { [weak self, subscription = _subscription] in
                    var iterator = subscription.makeAsyncIterator()
                    while let event = await iterator.next() {
                        guard let self else { return }
                        await self._reduce(event, subscription: subscription)
                    }
                }
            }
            """),
            DeclSyntax(stringLiteral: "deinit { _observationTask?.cancel() }"),
            DeclSyntax(stringLiteral: "public var identity: TLALiveMachineIdentity { _live.identity }"),
            DeclSyntax(stringLiteral: "public var status: TLALiveMachineAdapterStatus { _reducer.status }"),
            DeclSyntax(stringLiteral: "public var current: TLALiveMachineAdapterSnapshot<State>? { _reducer.current }"),
            DeclSyntax(stringLiteral: "public var state: State? { _reducer.current?.state }"),
            DeclSyntax(stringLiteral: """
            public func cancelObservation() async {
                _observationTask?.cancel()
                await _subscription.cancel()
            }
            """),
            DeclSyntax(stringLiteral: observableReducerMethod(model: model))
        ]
        declarations += typedAdapterExecution(model: model, receiver: "_live")
        return declarations
    }

    static func typedAdapterExecution(model: MacroCompilation, receiver: String) -> [DeclSyntax] {
        guard model.machineSurface.actions.isEmpty == false else { return [] }
        return [DeclSyntax(stringLiteral: """
        public func apply(_ action: ActionLabel, requestID: Foundation.UUID = Foundation.UUID()) async throws -> Outcome {
            try await \(receiver).execute(action, requestID: requestID)
        }
        """)]
    }

    static func observableCallbacks(model: MacroCompilation) -> [DeclSyntax] {
        model.machineSurface.actions.map { action in
            let callbackName = "on" + action.swiftIdentifier.prefix(1).capitalized + action.swiftIdentifier.dropFirst()
            let parameterTypes = action.bindings.filter(\.isPublic).map(\.swiftType)
            let parameters = (parameterTypes + ["State", "State"]).joined(separator: ", ")
            return DeclSyntax(stringLiteral: "@MainActor public var \(callbackName): ((\(parameters)) async -> Void)?")
        }
    }

    static func observableReducerMethod(model: MacroCompilation) -> String {
        guard model.machineSurface.actions.isEmpty == false else {
            return """
            private func _reduce(_ event: TLALiveMachineObservationEvent<Never>, subscription: TLALiveMachineObservationSubscription<Never>) async {
                _ = _reducer.reduce(event)
                if case .loss = event { _ = await subscription.resynchronize() }
            }
            """
        }
        let notifications = model.machineSurface.actions.map { action -> String in
            let callbackName = "on" + action.swiftIdentifier.prefix(1).capitalized + action.swiftIdentifier.dropFirst()
            let bindings = action.bindings.filter(\.isPublic)
            let pattern = bindings.isEmpty ? ".\(action.swiftIdentifier)" : ".\(action.swiftIdentifier)(\(bindings.map { "let \($0.formalName)" }.joined(separator: ", ")))"
            let arguments = (bindings.map(\.formalName) + ["before", "after"]).joined(separator: ", ")
            return "case \(pattern): if let \(callbackName) { await \(callbackName)(\(arguments)) }"
        }.joined(separator: "\n")
        return """
        private func _reduce(_ event: TLALiveMachineObservationEvent<ActionLabel>, subscription: TLALiveMachineObservationSubscription<ActionLabel>) async {
            let contiguousCommit = _reducer.reduce(event)
            if case .loss = event { _ = await subscription.resynchronize() }
            guard let commit = contiguousCommit,
                  let action = commit.action,
                  let before = try? State(projection: commit.before.state),
                  let after = try? State(projection: commit.after.state) else { return }
            switch action {
            \(notifications)
            }
        }
        """
    }
}
