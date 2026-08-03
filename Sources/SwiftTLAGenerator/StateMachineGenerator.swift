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
        let source = try SourceFileSyntax {
            try buildStruct()
            try buildActionExtension()
            try buildTransitionsExtension()
        }
        return BasicFormat().rewrite(source).description
    }

    private var typeName: String { graph.specName.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "_") }
    private var vars: [String] { graph.variableNames }
    private var sortedIDs: [StateGraph.StateID] { graph.states.keys.sorted { $0.id < $1.id } }

    private func buildStruct() throws -> StructDeclSyntax {
        let initial = structInit(graph.states[sortedIDs.first!]!)
        return try StructDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.internal))],
            name: .identifier(typeName),
            inheritanceClause: inheritance(["Equatable", "Hashable", "Codable", "Sendable"])
        ) {
            for v in vars { "var \(raw: v): Int" }
            try InitializerDeclSyntax("init(\(raw: varParams()))") {
                for v in vars { ExprSyntax("self.\(raw: v) = \(raw: v)") }
            }
            DeclSyntax("static let initial = \(raw: typeName)(\(raw: initial))")
        }
    }

    private func buildActionExtension() throws -> ExtensionDeclSyntax {
        let actions = Set(graph.transitions.values.flatMap { (transitions: [(action: String, target: StateGraph.StateID)]) in
            transitions.map { (t: (action: String, target: StateGraph.StateID)) in t.action }
        }).sorted()
        return try ExtensionDeclSyntax(extendedType: IdentifierTypeSyntax(name: .identifier(typeName))) {
            EnumDeclSyntax(
                name: .identifier("Action"),
                inheritanceClause: inheritance(["String", "CaseIterable", "Identifiable", "Codable", "Sendable"])
            ) {
                for act in actions { "case \(raw: swiftCase(act))" }
                DeclSyntax("var id: Self { self }")
            }

            DeclSyntax("var availableActions: [Action] { transitions.map(\\.action) }")
            DeclSyntax("")
            try FunctionDeclSyntax("mutating func apply(_ action: Action)") {
                StmtSyntax("guard let next = transitions.first(where: { $0.action == action })?.target else { return }")
                StmtSyntax("self = next")
            }
        }
    }

    private func buildTransitionsExtension() throws -> ExtensionDeclSyntax {
        return try ExtensionDeclSyntax(extendedType: IdentifierTypeSyntax(name: .identifier(typeName))) {
            try VariableDeclSyntax("var transitions: [(action: VerifiedStateMachine.Action, target: Self)]") {
                try SwitchExprSyntax("switch (\(raw: vars.map { "self.\($0)" }.joined(separator: ", ")))") {
                    for stateID in sortedIDs {
                        let state = graph.states[stateID]!
                        let patterns = vars.map { v -> String in
                            if let val = state[v], case .int(let n) = val { return "\(n)" }
                            return "_"
                        }.joined(separator: ", ")
                        let trans = (graph.transitions[stateID] ?? []).filter { act, targetID in
                            !statesEqual(graph.states[targetID]!, state)
                        }
                        SwitchCaseSyntax("case (\(raw: patterns)):") {
                            if trans.isEmpty {
                                StmtSyntax("return []")
                            } else {
                                StmtSyntax("return [")
                                for (act, targetID) in trans {
                                    let targetInit = structInit(graph.states[targetID]!)
                                    StmtSyntax("(.\(raw: swiftCase(act)), Self(\(raw: targetInit))),")
                                }
                                StmtSyntax("]")
                            }
                        }
                    }
                    SwitchCaseSyntax("default:") { StmtSyntax("return []") }
                }
            }
        }
    }

    private func inheritance(_ names: [String]) -> InheritanceClauseSyntax {
        InheritanceClauseSyntax {
            for n in names { InheritedTypeSyntax(type: IdentifierTypeSyntax(name: .identifier(n))) }
        }
    }

    private func varParams() -> String { vars.map { "\($0): Int" }.joined(separator: ", ") }

    private func structInit(_ state: [String: TLAValue]) -> String {
        vars.map { v in
            if let val = state[v], case .int(let n) = val { return "\(v): \(n)" }
            return "\(v): 0"
        }.joined(separator: ", ")
    }

    private func swiftCase(_ name: String) -> String {
        if name.isEmpty { return "noop" }
        let lower = name.prefix(1).lowercased() + name.dropFirst()
        return lower.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "_")
    }

    private func statesEqual(_ a: [String: TLAValue], _ b: [String: TLAValue]) -> Bool {
        vars.allSatisfy { a[$0] == b[$0] }
    }
}
