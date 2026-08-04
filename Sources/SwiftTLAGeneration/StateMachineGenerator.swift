import Foundation
import SwiftParser
import SwiftSyntax
import SwiftBasicFormat
import SwiftSyntaxBuilder
import SwiftTLA

public struct StateMachineGenerator {
    public let graph: StateGraph
    public init(graph: StateGraph) { self.graph = graph }

    public func generate() throws -> String {
        let source = try SourceFileSyntax { try singleStruct() }
        return BasicFormat().rewrite(source).description
    }

    private var typeName: String { graph.specName.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "_") }
    private var variables: [String] { graph.variableNames }
    private var sortedIDs: [StateGraph.StateID] { graph.states.keys.sorted { $0.id < $1.id } }

    // MARK: - Top-level struct

    private func singleStruct() throws -> StructDeclSyntax {
        let firstState = graph.states[sortedIDs.first!]!
        let actions = uniqueActions()
        return try StructDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: .identifier(typeName),
            inheritanceClause: inherited("Equatable", "Hashable", "Codable", "Sendable", "TLAMachine")
        ) {
            for v in variables { "public var \(raw: v): Int" }
            try memberwiseInit()
            "public static let initial = \(raw: typeName)(\(raw: initializerArguments(for: firstState)))"
            actionEnum(actions)
            try transitionsProperty()
            "public var availableActions: [Action] { transitions.map(\\.action) }"
            "public var enabledActions: [Action] { availableActions }"
            try applyMethod()
        }
    }

    // MARK: - Init

    private func memberwiseInit() throws -> InitializerDeclSyntax {
        try InitializerDeclSyntax("public init(\(raw: variables.map { "\($0): Int" }.joined(separator: ", ")))") {
            for v in variables { ExprSyntax("self.\(raw: v) = \(raw: v)") }
        }
    }

    private func initializerArguments(for state: [String: TLAValue]) -> String {
        variables.map { v -> String in
            if case .int(let n) = state[v] { return "\(v): \(n)" }
            return "\(v): 0"
        }.joined(separator: ", ")
    }

    // MARK: - Action enum

    private func uniqueActions() -> [String] {
        Set(graph.transitions.values.flatMap { entries in entries.map(\.action) }).sorted()
    }

    private func actionEnum(_ actions: [String]) -> EnumDeclSyntax {
        EnumDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            name: .identifier("Action"),
            inheritanceClause: inherited("String", "CaseIterable", "Identifiable", "Codable", "Sendable")
        ) {
            for act in actions { "case \(raw: escapedCase(act))" }
            "public var id: Self { self }"
        }
    }

    // MARK: - Transitions

    private func transitionsProperty() throws -> VariableDeclSyntax {
        try VariableDeclSyntax("public var transitions: [(action: Action, target: Self)]") {
            try SwitchExprSyntax("switch (\(raw: variables.map { "self.\($0)" }.joined(separator: ", ")))") {
                for stateID in sortedIDs {
                    let state = graph.states[stateID]!
                    let pattern = variables.map { v in
                        if case .int(let n) = state[v] { return "\(n)" } else { return "_" }
                    }.joined(separator: ", ")
                    let meaningful = (graph.transitions[stateID] ?? []).filter { act, targetID in
                        !statesEqual(graph.states[targetID]!, state)
                    }
                    SwitchCaseSyntax("case (\(raw: pattern)):") {
                        if meaningful.isEmpty {
                            StmtSyntax("return []")
                        } else {
                            StmtSyntax("return [")
                            for (act, targetID) in meaningful {
                                let args = initializerArguments(for: graph.states[targetID]!)
                                StmtSyntax("(.\(raw: escapedCase(act)), Self(\(raw: args))),")
                            }
                            StmtSyntax("]")
                        }
                    }
                }
                SwitchCaseSyntax("default:") { StmtSyntax("return []") }
            }
        }
    }

    // MARK: - Apply

    private func applyMethod() throws -> FunctionDeclSyntax {
        try FunctionDeclSyntax("public mutating func apply(_ action: Action)") {
            StmtSyntax("guard let next = transitions.first(where: { $0.action == action })?.target else { return }")
            StmtSyntax("self = next")
        }
    }

    // MARK: - Helpers

    private func inherited(_ names: String...) -> InheritanceClauseSyntax {
        InheritanceClauseSyntax {
            for n in names { InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier(n))) }
        }
    }

    private func swiftCase(_ name: String) -> String {
        if name.isEmpty { return "noop" }
        let lower = name.prefix(1).lowercased() + name.dropFirst()
        let cleaned = lower.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "_")
        return cleaned
    }

    private let swiftKeywords: Set<String> = ["next", "default", "case", "switch", "break", "return", "if", "else", "for", "in", "while", "repeat", "do", "catch", "throw", "where", "guard", "let", "var", "as", "is", "try", "self", "Self", "super", "nil", "true", "false", "import", "class", "struct", "enum", "protocol", "extension", "func", "init", "deinit", "subscript", "operator", "precedencegroup", "associatedtype", "typealias"]

    private func escapedCase(_ name: String) -> String {
        let cleaned = swiftCase(name)
        if swiftKeywords.contains(cleaned) { return "action_" + cleaned }
        return cleaned
    }

    private func statesEqual(_ a: [String: TLAValue], _ b: [String: TLAValue]) -> Bool {
        variables.allSatisfy { a[$0] == b[$0] }
    }
}
