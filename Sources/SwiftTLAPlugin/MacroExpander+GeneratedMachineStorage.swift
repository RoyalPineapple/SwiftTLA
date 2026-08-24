import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateGeneratedMachineStorageMembers(
        isActor: Bool,
        hasActions: Bool,
        actions: [MachineSurfacePlan.Action],
        variables: [MachineSurfacePlan.Variable],
        symmetricCollections: [MachineSurfacePlan.SymmetricCollection] = []
    ) -> [DeclSyntax] {
        let modifier = isActor ? "" : "mutating "
        let liveProjection = symmetricCollections.compactMap { collection in
            guard let ordinal = variables.first(where: { $0.formalName == collection.formalName })?.storageOrdinal else {
                return nil
            }
            return """
            state = try _storage.replacing(
                value: \(collection.formalName).tlaValue,
                at: \(ordinal),
                in: state
            )
            """
        }.joined(separator: "\n                ")
        let stateWithLiveCollections = symmetricCollections.isEmpty
            ? "_storageState"
            : """
            var state = _storageState
                            \(liveProjection)
                            return state
            """
        let successorCases = actions.map { action -> String in
            let actionCase: String
            let arguments: String
            let selection: String
            if let collection = action.symmetricCollection {
                actionCase = ".\(action.swiftIdentifier)(member: let member)"
                arguments = "[]"
                selection = """
                .filter { candidate in
                    try storage.collectionChangesOnly(
                        at: \(collection.storageOrdinal),
                        selected: member,
                        from: storageState,
                        to: candidate
                    )
                }
                """
            } else {
                let bindings = action.bindings.filter(\.isPublic)
                actionCase = bindings.isEmpty
                    ? ".\(action.swiftIdentifier)"
                    : ".\(action.swiftIdentifier)(\(bindings.map { "\($0.formalName): _" }.joined(separator: ", ")))"
                arguments = "Self._actionArguments(for: action)"
                selection = ""
            }
            return """
            case \(actionCase):
                return try storage.successors(
                    actionOrdinal: Self._actionOrdinal(for: action),
                    arguments: \(arguments),
                    from: storageState
                )\(selection)
            """
        }.joined(separator: "\n                ")
        let collectionUpdates = actions.compactMap { action -> String? in
            guard let collection = action.symmetricCollection else { return nil }
            return """
            case .\(action.swiftIdentifier)(member: let member):
                guard let value: \(collection.valueType) = try _storage.collectionValue(
                    at: \(collection.storageOrdinal),
                    for: member,
                    as: \(collection.valueType).self,
                    in: state
                ) else {
                    throw GeneratedMachineStateDiagnostic.typeMismatch(
                        path: \(String(reflecting: collection.formalName)),
                        expected: "\(collection.valueType)",
                        actual: "no matching collection member"
                    )
                }
                try \(collection.formalName).update(id: member, to: value)
            """
        }.joined(separator: "\n                ")
        let collectionActions = actions.compactMap { action -> String? in
            guard let collection = action.symmetricCollection else { return nil }
            return """
            for member in \(collection.formalName).ids {
                let action: Action = .\(action.swiftIdentifier)(member: member)
                if try isEnabled(action) { actions.append(action) }
            }
            """
        }.joined(separator: "\n                ")
        let enabledActionsBinding = collectionActions.isEmpty ? "let" : "var"
        var members: [DeclSyntax] = [
            DeclSyntax(stringLiteral: """
            public var state: State {
                _state
            }
            """),
            DeclSyntax(stringLiteral: """
            public struct Transition: Sendable, Equatable {
                public let action: Action
                public let before: State
                public let after: State
            }
            """),
        ]
        if hasActions {
            members += [
                DeclSyntax(stringLiteral: """
                private func _stateWithLiveCollections() throws -> _GeneratedMachineStorage.State {
                    \(stateWithLiveCollections)
                }
                """),
                DeclSyntax(stringLiteral: """
                private static func _successors(
                    for action: Action,
                    from storageState: _GeneratedMachineStorage.State,
                    storage: _GeneratedMachineStorage
                ) throws -> [_GeneratedMachineStorage.State] {
                    switch action {
                    \(successorCases)
                    }
                }
                """),
                DeclSyntax(stringLiteral: """
                public func isEnabled(_ action: Action) throws -> Bool {
                    try Self._successors(
                        for: action,
                        from: _stateWithLiveCollections(),
                        storage: _storage
                    ).isEmpty == false
                }
                """),
                DeclSyntax(stringLiteral: """
                public func enabledActions() throws -> [Action] {
                    \(enabledActionsBinding) actions = try _storage.availableActions(in: _stateWithLiveCollections()) { ordinal, arguments in
                        Self._action(actionAt: ordinal, arguments: arguments)
                    }
                    \(collectionActions)
                    return actions
                }
                """),
                DeclSyntax(stringLiteral: """
                public \(modifier)func send(_ action: Action) throws -> Transition {
                    let before = _state
                    let candidates = try Self._successors(
                        for: action,
                        from: _stateWithLiveCollections(),
                        storage: _storage
                    )
                    let afterStorageState: _GeneratedMachineStorage.State
                    switch candidates.count {
                    case 0: throw GeneratedMachineError.noMatchingSuccessor
                    case 1: afterStorageState = candidates[0]
                    default: throw GeneratedMachineError.ambiguousAction
                    }
                    let after = try State(storage: _storage, storageState: afterStorageState)
                    switch action {
                    \(collectionUpdates)
                    default: break
                    }
                    _storageState = afterStorageState
                    _state = after
                    return Transition(action: action, before: before, after: after)
                }
                """),
            ]
        }
        return members
    }
}
