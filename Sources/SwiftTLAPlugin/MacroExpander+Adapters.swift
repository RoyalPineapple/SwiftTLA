import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

extension MacroExpander {
    static func generateNestedActorMembers(modelTypeName: String) -> [DeclSyntax] {
        [
            DeclSyntax(stringLiteral: "private let _live: Live"),
            DeclSyntax(stringLiteral: "public typealias State = \(modelTypeName).State"),
            DeclSyntax(stringLiteral: "public typealias Live = \(modelTypeName).Live"),
            DeclSyntax(stringLiteral: "public typealias Action = \(modelTypeName).Action"),
            DeclSyntax(stringLiteral: "public typealias Transition = \(modelTypeName).Transition"),
            DeclSyntax(stringLiteral: "public init() throws { _live = try Live() }"),
            DeclSyntax(stringLiteral: "public var state: State { get async { await _live.state } }"),
            DeclSyntax(stringLiteral: "public func isEnabled(_ action: Action) async throws -> Bool { try await _live.isEnabled(action) }"),
            DeclSyntax(stringLiteral: "public func enabledActions() async throws -> [Action] { try await _live.enabledActions() }"),
            DeclSyntax(stringLiteral: "public func send(_ action: Action) async throws -> Transition { try await _live.send(action) }")
        ]
    }
}
