import Foundation
import SwiftParser
import SwiftSyntax
import SwiftBasicFormat
import SwiftSyntaxBuilder

public struct StateMachineGenerator {
    public let graph: StateGraph
    public init(graph: StateGraph) { self.graph = graph }

    public func generate() throws -> String {
        let source = try SourceFileSyntax { try structDeclaration() }
        return BasicFormat().rewrite(source).description
    }

    public func generateGraph(structName: String) -> String {
        var nodeStrings: [String] = []
        var edgeStrings: [String] = []
        for id in orderedIDs {
            guard let state = graph.states[id] else { continue }
            let args = variableNames.map { "\($0): \(extractInt(state[$0]))" }.joined(separator: ", ")
            nodeStrings.append("TLAMachineGraph<\(structName)>.Node(state: \(structName)(\(args)))")
            for t in graph.transitions[id] ?? [] {
                guard let target = graph.states[t.target] else { continue }
                let srcArgs = variableNames.map { "\($0): \(extractInt(state[$0]))" }.joined(separator: ", ")
                let dstArgs = variableNames.map { "\($0): \(extractInt(target[$0]))" }.joined(separator: ", ")
                edgeStrings.append("TLAMachineGraph<\(structName)>.Edge(source: \(structName)(\(srcArgs)), transition: .\(identifier(named: t.action)), destination: \(structName)(\(dstArgs)))")
            }
        }
        return "static let graph: TLAMachineGraph<\(structName)> = TLAMachineGraph(nodes: [\(nodeStrings.joined(separator: ", "))], edges: [\(edgeStrings.joined(separator: ", "))])"
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
            DeclSyntax(stringLiteral: "public var availableTransitions: [Transition] { transitions.map { $0.action } }")
            DeclSyntax(stringLiteral: "public var enabledTransitions: [Transition] { availableTransitions }")
            try applyMethod()
            try descriptionProperty()
        }
    }

    // MARK: - Variables

    private var variableTypes: [String: String] {  // var name → Swift type string
        Dictionary(uniqueKeysWithValues: variableNames.map { name in
            let type: String
            switch initialState[name] {
            case .string: type = "String"
            case .bool: type = "Bool"
            case .set: type = "Set<TLAValue>"
            case .tuple: type = "[TLAValue]"
            case .record: type = "[String: TLAValue]"
            default: type = "Int"
            }
            return (name, type)
        })
    }

    private func variableDeclarations() -> [DeclSyntax] {
        variableNames.map { name in
            DeclSyntax(stringLiteral: "public var " + name + ": \(variableTypes[name] ?? "Int")")
        }
    }

    // MARK: - Init

    private func memberwiseInit() throws -> DeclSyntax {
        let parameters = variableNames.map { $0 + ": \(variableTypes[$0] ?? "Int")" }.joined(separator: ", ")
        let body = variableNames.map { "self." + $0 + " = " + $0 }.joined(separator: "\n")
        return DeclSyntax(stringLiteral: "public init(" + parameters + ") {\n" + body + "\n}")
    }

    private func initArgs(_ state: [String: TLAValue]) -> String {
        variableNames.map { name in
            let value: String = extractValue(state[name])
            return name + ": " + value
        }.joined(separator: ", ")
    }

    private func extractValue(_ value: TLAValue?) -> String {
        guard let value else { return "0" }
        switch value {
        case .int(let n): return "\(n)"
        case .bool(let b): return "\(b)"
        case .string(let s): return "\"\(s)\""
        case .set: return "[]"
        case .tuple: return "[]"
        case .record: return "[:]"
        case .function: return "[:]"
        case .constant(let n): return n
        }
    }

    private func extractInt(_ value: TLAValue?) -> Int { 0 }  // keep for compatibility

    // MARK: - Action enum

    private func actionEnum() throws -> DeclSyntax {
        let cases = actionNames.map { name in
            let caseName = identifier(named: name)
            return "case " + caseName
        }.joined(separator: "\n")
        return DeclSyntax(stringLiteral: "public enum Transition: String, CaseIterable, Identifiable, Codable, Sendable, CustomStringConvertible {\n" + cases + "\npublic var id: Self { self }\npublic var description: String { rawValue }\n}")
    }

    // MARK: - Transitions

    private func transitionsProperty() throws -> DeclSyntax {
        let pattern = variableNames.joined(separator: ", ")
        let cases = orderedIDs.compactMap { stateID -> String? in
            guard let state = graph.states[stateID] else { return nil }
            let values = variableNames.map { name in extractValue(state[name]) }.joined(separator: ", ")
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
        return DeclSyntax(stringLiteral: "public var transitions: [(action: Transition, target: Self)] { " + switchBody + " }")
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
                            secondName: .identifier("transition"),
                            type: IdentifierTypeSyntax(name: .identifier("Transition"))
                        )
                    }
                )
            )
        ) {
            StmtSyntax(stringLiteral: "guard let next = transitions.first(where: { $0.action == transition })?.target else { return }")
            StmtSyntax(stringLiteral: "self = next")
        }
    }

    // MARK: - Description

    private func descriptionProperty() throws -> DeclSyntax {
        let parts = variableNames.map { "\"\\(\($0))\"" }.joined(separator: ", \", \", ")
        return DeclSyntax(stringLiteral: "public var description: String { [\(parts)].joined() }")
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
