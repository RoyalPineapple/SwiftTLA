import Foundation
import SwiftParser
import SwiftSyntax
import SwiftBasicFormat

public struct StateMachineGenerator {
    public let graph: StateGraph

    public init(graph: StateGraph) {
        self.graph = graph
    }

    public func generate() -> String {
        let source = buildSource()
        let syntax = Parser.parse(source: source)
        return BasicFormat().rewrite(syntax).description
    }

    private var typeName: String {
        graph.specName
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "_")
    }

    private var actionEnum: String { "\(typeName).Action" }
    private var vars: [String] { graph.variableNames }
    private var sortedIDs: [StateGraph.StateID] { graph.states.keys.sorted { $0.id < $1.id } }

    private func buildSource() -> String {
        let count = sortedIDs.count
        let trans = graph.transitions.values.map(\.count).reduce(0, +)
        return """
        import Foundation

        // Auto-generated from verified TLA+ spec "\(graph.specName)" (\(count) states, \(trans) transitions)

        \(buildStruct())

        \(buildTransitionsExtension())

        \(buildActionExtension())
        """
    }

    private func buildStruct() -> String {
        var lines: [String] = []
        lines.append("struct \(typeName): Equatable, Hashable, Codable, Sendable {")
        for v in vars { lines.append("    var \(v): Int") }
        lines.append("")
        lines.append("    init(\(params())) {")
        for v in vars { lines.append("        self.\(v) = \(v)") }
        lines.append("    }")
        lines.append("")
        lines.append("    static let initial = \(typeName)(\(structInit(graph.states[sortedIDs.first!]!)))")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func buildTransitionsExtension() -> String {
        var lines: [String] = []
        lines.append("extension \(typeName) {")

        let tupleVars = vars.map { "self.\($0)" }.joined(separator: ", ")
        lines.append("    var transitions: [(action: \(actionEnum), target: \(typeName))] {")
        lines.append("        switch (\(tupleVars)) {")

        for stateID in sortedIDs {
            let state = graph.states[stateID]!
            let pattern = vars.map { name -> String in
                if let v = state[name], case .int(let n) = v { return "\(n)" }
                return "_"
            }.joined(separator: ", ")
            let outTrans = graph.transitions[stateID] ?? []
            let meaningful = outTrans.filter { act, targetID in
                let targetState = graph.states[targetID]!
                return !statesEqual(targetState, state)
            }
            lines.append("        case (\(pattern)):")
            if meaningful.isEmpty {
                lines.append("            return []")
            } else {
                lines.append("            return [")
                for (act, targetID) in meaningful {
                    let actCase = act.isEmpty ? "noop" : swiftCase(act)
                    let ti = structInit(graph.states[targetID]!)
                    lines.append("                (.\(actCase), \(typeName)(\(ti))),")
                }
                lines.append("            ]")
            }
        }
        lines.append("        default: return []")
        lines.append("        }")
        lines.append("    }")

        lines.append("")
        lines.append("    var availableActions: [\(actionEnum)] {")
        lines.append("        transitions.map(\\.action)")
        lines.append("    }")

        lines.append("")
        lines.append("    mutating func apply(_ action: \(actionEnum)) {")
        lines.append("        guard let next = transitions.first(where: { $0.action == action })?.target else { return }")
        lines.append("        self = next")
        lines.append("    }")

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func buildActionExtension() -> String {
        let allActions = Set(graph.transitions.values.flatMap { $0.map(\.action) }).sorted()
        var lines: [String] = []
        lines.append("extension \(typeName) {")
        lines.append("    enum Action: String, CaseIterable, Identifiable, Codable, Sendable {")
        for act in allActions {
            lines.append("        case \(act.isEmpty ? "noop" : swiftCase(act))")
        }
        lines.append("")
        lines.append("        var id: Self { self }")
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func params() -> String {
        vars.map { "\($0): Int" }.joined(separator: ", ")
    }

    private func structInit(_ state: [String: TLAValue]) -> String {
        vars.map { name -> String in
            if let v = state[name], case .int(let n) = v {
                return "\(name): \(n)"
            }
            return "\(name): 0"
        }.joined(separator: ", ")
    }

    private func swiftCase(_ name: String) -> String {
        let lower = name.prefix(1).lowercased() + name.dropFirst()
        return lower.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "_")
    }

    private func statesEqual(_ a: [String: TLAValue], _ b: [String: TLAValue]) -> Bool {
        for v in vars {
            if a[v] != b[v] { return false }
        }
        return true
    }
}
