import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

extension MacroExpander {
    static func generateNestedActorMembers(modelTypeName: String) -> [DeclSyntax] {
        [
            DeclSyntax(stringLiteral: "private var _machine: \(modelTypeName)"),
            DeclSyntax(stringLiteral: "public typealias State = \(modelTypeName).State"),
            DeclSyntax(stringLiteral: "public typealias Action = \(modelTypeName).Action"),
            DeclSyntax(stringLiteral: "public typealias Transition = \(modelTypeName).Transition"),
            DeclSyntax(stringLiteral: "public init() throws { _machine = try \(modelTypeName).makeMachine() }"),
            DeclSyntax(stringLiteral: "public var state: State { _machine.state }"),
            DeclSyntax(stringLiteral: "public func isEnabled(_ action: Action) throws -> Bool { try _machine.isEnabled(action) }"),
            DeclSyntax(stringLiteral: "public func enabledActions() throws -> [Action] { try _machine.enabledActions() }"),
            DeclSyntax(stringLiteral: "public func send(_ action: Action) throws -> Transition { try _machine.send(action) }")
        ]
    }
}
