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
        let source = try SourceFileSyntax { try structDeclaration() }
        return BasicFormat().rewrite(source).description
    }

    private var specName: String { graph.specName.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "_") }
    private var variableNames: [String] { graph.variableNames }
    private var orderedIDs: [StateGraph.StateID] { graph.states.keys.sorted { $0.id < $1.id } }

    private var initialState: [String: TLAValue] {
        guard let first = orderedIDs.first, let state = graph.states[first] else { return [:] }
        return state
    }

    private var actionNames: [String] { Set(graph.transitions.values.flatMap { $0.map(\.action) }).sorted() }

    // MARK: - Struct

    private func structDeclaration() throws -> StructDeclSyntax {
        try StructDeclSyntax(
            modifiers: publicModifier,
            name: .identifier(specName),
            inheritanceClause: InheritanceClauseSyntax {
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("Equatable")))
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("Hashable")))
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("Codable")))
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("Sendable")))
                InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier("TLAMachine")))
            }
        ) {
            variableDeclarations()
            try memberwiseInit()
            DeclSyntax(stringLiteral: "public static let initial = " + specName + "(" + initArgs(initialState) + ")")
            try actionEnum()
            try transitionsProperty()
            DeclSyntax(stringLiteral: "public var availableActions: [Action] { transitions.map { $0.action } }")
            DeclSyntax(stringLiteral: "public var enabledActions: [Action] { availableActions }")
            try applyMethod()
        }
    }

    // MARK: - Variables

    private func variableDeclarations() -> [DeclSyntax] {
        variableNames.map { name in
            DeclSyntax(stringLiteral: "public var " + name + ": Int")
        }
    }

    // MARK: - Init

    private func memberwiseInit() throws -> DeclSyntax {
        let parameters = variableNames.map { $0 + ": Int" }.joined(separator: ", ")
        let body = variableNames.map { "self." + $0 + " = " + $0 }.joined(separator: "\n")
        return DeclSyntax(stringLiteral: "public init(" + parameters + ") {\n" + body + "\n}")
    }

    private func initArgs(_ state: [String: TLAValue]) -> String {
        variableNames.map { name in
            let value: Int = extractInt(state[name])
            return name + ": " + String(value)
        }.joined(separator: ", ")
    }

    private func extractInt(_ value: TLAValue?) -> Int {
        guard let value, case .int(let number) = value else { return 0 }
        return number
    }

    // MARK: - Action enum

    private func actionEnum() throws -> DeclSyntax {
        let cases = actionNames.map { name in
            let caseName = identifier(named: name)
            return "case " + caseName
        }.joined(separator: "\n")
        return DeclSyntax(stringLiteral: "public enum Action: String, CaseIterable, Identifiable, Codable, Sendable {\n" + cases + "\npublic var id: Self { self }\n}")
    }

    // MARK: - Transitions

    private func transitionsProperty() throws -> DeclSyntax {
        let pattern = variableNames.joined(separator: ", ")
        let cases = orderedIDs.compactMap { stateID -> String? in
            guard let state = graph.states[stateID] else { return nil }
            let values = variableNames.map { name in extractInt(state[name]) }.map(String.init).joined(separator: ", ")
            let transitions = graph.transitions[stateID] ?? []
            let meaningfulTransitions = transitions.filter { transition in
                guard let targetState = graph.states[transition.target] else { return false }
                return statesNotEqual(targetState, state)
            }
            let body: String
            if meaningfulTransitions.isEmpty {
                body = "return []"
            } else {
                let items = meaningfulTransitions.map { transition in
                    guard let targetState = graph.states[transition.target] else { return "nil" }
                    return "(." + identifier(named: transition.action) + ", Self(" + initArgs(targetState) + "))"
                }
                body = "return [" + items.joined(separator: ", ") + "]"
            }
            return "case (" + values + "): " + body
        }.joined(separator: "\n")
        let switchBody = "switch (" + pattern + ") {\n" + cases + "\ndefault: return []\n}"
        return DeclSyntax(stringLiteral: "public var transitions: [StateGraph.Transition] { " + switchBody + " }")
    }

    // MARK: - Apply

    private func applyMethod() throws -> FunctionDeclSyntax {
        return FunctionDeclSyntax(
            modifiers: DeclModifierListSyntax {
                DeclModifierSyntax(name: .keyword(.public))
                DeclModifierSyntax(name: .keyword(.mutating))
            },
            name: .identifier("apply"),
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(
                    parameters: FunctionParameterListSyntax {
                        FunctionParameterSyntax(
                            firstName: .wildcardToken(),
                            secondName: .identifier("action"),
                            type: IdentifierTypeSyntax(name: .identifier("Action"))
                        )
                    }
                )
            )
        ) {
            StmtSyntax(stringLiteral: "guard let next = transitions.first(where: { $0.action == action })?.target else { return }")
            StmtSyntax(stringLiteral: "self = next")
        }
    }

    // MARK: - Helpers

    private var publicModifier: DeclModifierListSyntax {
        DeclModifierListSyntax { DeclModifierSyntax(name: .keyword(.public)) }
    }

    private func identifier(named name: String) -> String {
        let cleaned = name.prefix(1).lowercased() + name.dropFirst()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "_")
        let keywords: Set<String> = [
            "next", "default", "case", "switch", "break", "return", "if", "else", "for", "in",
            "while", "repeat", "do", "catch", "throw", "where", "guard", "let", "var", "as", "is",
            "try", "self", "Self", "super", "nil", "true", "false", "import", "class", "struct",
            "enum", "protocol", "extension", "func", "init", "deinit", "subscript", "operator",
            "precedencegroup", "associatedtype", "typealias",
        ]
        return keywords.contains(cleaned) ? "action_" + cleaned : cleaned
    }

    private func statesNotEqual(_ a: [String: TLAValue], _ b: [String: TLAValue]) -> Bool {
        !variableNames.allSatisfy { a[$0] == b[$0] }
    }

    private func statesEqual(_ a: [String: TLAValue], _ b: [String: TLAValue]) -> Bool {
        variableNames.allSatisfy { a[$0] == b[$0] }
    }
}
