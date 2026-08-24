import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

extension MacroExpander {
    static func commonAdapterAliases(modelTypeName: String) -> [DeclSyntax] {
        [
            DeclSyntax(stringLiteral: "public typealias State = \(modelTypeName).State"),
            DeclSyntax(stringLiteral: "public typealias Live = \(modelTypeName).Live"),
            DeclSyntax(stringLiteral: "public typealias Action = \(modelTypeName).Action"),
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

    static func typedAdapterExecution(receiver: String) -> [DeclSyntax] {
        return [DeclSyntax(stringLiteral: """
        public func send(_ action: Action, requestID: Foundation.UUID = Foundation.UUID()) async throws -> Outcome {
            try await \(receiver).execute(action, requestID: requestID)
        }
        """)]
    }

}
