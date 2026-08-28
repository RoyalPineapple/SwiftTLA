import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateGeneratedMachineStorageMembers(
        actions: [MachineSurfacePlan.Action]
    ) -> [DeclSyntax] {
        var members: [DeclSyntax] = [
            DeclSyntax(stringLiteral: """
            public var state: State {
                _storage.state
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
                public func isEnabled(_ action: Action) throws -> Bool {
                    try _storage.isEnabled(action)
                }
                """),
                DeclSyntax(stringLiteral: """
                public func enabledActions() throws -> [Action] {
                    try _storage.enabledActions()
                }
                """),
                DeclSyntax(stringLiteral: """
                public mutating func send(_ action: Action) throws -> Transition {
                    let transition = try _storage.send(action)
                    return Transition(action: action, before: transition.before, after: transition.after)
                }
                """),
            ]
        }
        return members
    }
}
