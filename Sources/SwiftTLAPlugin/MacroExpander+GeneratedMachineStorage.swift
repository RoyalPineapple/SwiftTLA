import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateGeneratedMachineStorageMembers(
        actions: [MachineSurfacePlan.Action],
        symmetricCollections: [MachineSurfacePlan.SymmetricCollection]
    ) -> [DeclSyntax] {
        let collectionArguments = symmetricCollections.map {
            ", \($0.formalName): _\($0.formalName)Members"
        }.joined()
        let successorCases = actions.map { action -> String in
            let pattern: String
            if action.symmetricCollection == nil {
                let bindings = action.bindings.filter(\.isPublic)
                pattern = bindings.isEmpty
                    ? ".\(action.swiftIdentifier)"
                    : ".\(action.swiftIdentifier)(\(bindings.map { "\($0.formalName): _" }.joined(separator: ", ")))"
            } else {
                pattern = ".\(action.swiftIdentifier)(member: _)"
            }
            return """
            case \(pattern):
                return try _storage.successors(
                    actionOrdinal: Self._actionOrdinal(for: action),
                    arguments: try _actionArguments(for: action),
                    from: storageState
                )
            """
        }.joined(separator: "\n                ")
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
        if actions.isEmpty == false {
            members += [
                DeclSyntax(stringLiteral: """
                private func _successors(
                    for action: Action,
                    from storageState: _GeneratedMachineStorage.State
                ) throws -> [_GeneratedMachineStorage.State] {
                    switch action {
                    \(successorCases)
                    }
                }
                """),
                DeclSyntax(stringLiteral: """
                public func isEnabled(_ action: Action) throws -> Bool {
                    try _successors(for: action, from: _storageState).isEmpty == false
                }
                """),
                DeclSyntax(stringLiteral: """
                public func enabledActions() throws -> [Action] {
                    try _storage.availableActions(in: _storageState) { ordinal, arguments in
                        _action(actionAt: ordinal, arguments: arguments)
                    }
                }
                """),
                DeclSyntax(stringLiteral: """
                public mutating func send(_ action: Action) throws -> Transition {
                    let before = _state
                    let candidates = try _successors(for: action, from: _storageState)
                    let afterStorageState: _GeneratedMachineStorage.State
                    switch candidates.count {
                    case 0: throw GeneratedMachineError.noMatchingSuccessor
                    case 1: afterStorageState = candidates[0]
                    default: throw GeneratedMachineError.ambiguousAction
                    }
                    let after = try State(
                        storage: _storage,
                        storageState: afterStorageState\(collectionArguments)
                    )
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
