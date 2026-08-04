import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftParser
import SwiftTLA
import SwiftTLAGenerator

public struct ModelMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let closure = node.trailingClosure else {
            throw SimpleError("#spec requires a trailing closure")
        }

        let specData = try extractSpec(from: closure.statements)
        let spec = try buildSpec(from: specData)

        let checker = ModelChecker(spec: spec, maxStates: 10_000)
        let result = try checker.check()

        switch result {
        case .ok:
            let graph = try checker.exploreGraph()
            let code = try StateMachineGenerator(graph: graph).generate()
            let source = Parser.parse(source: code)
            let declarations = source.statements.compactMap { $0.item.as(DeclSyntax.self) }
            return declarations

        case .invariantViolated(let inv, _, let trace):
            let traceStr = trace.map { "  \($0)" }.joined(separator: "\n")
            context.diagnose(
                Diagnostic(
                    node: Syntax(node._syntaxNode),
                    message: SimpleDiagnostic(
                        message: "Invariant '\(inv)' violated\nCounterexample:\n\(traceStr)",
                        severity: .error
                    )
                )
            )
            return []

        case .depthExceeded(let count, let limit):
            context.diagnose(
                Diagnostic(
                    node: node._syntaxNode,
                    message: SimpleDiagnostic(
                        message: "State space exceeded \(limit) states (\(count) explored). Increase maxStates.",
                        severity: .warning
                    )
                )
            )
            return []

        case .deadlocked:
            return []

        case .error(let msg):
            throw SimpleError(msg)
        }
    }
}

struct SpecData {
    var typeName: String = "TLAStateMachine"
    var variables: [(name: String, initial: TLAValue)] = []
    var actions: [(name: String, body: ActionExpr)] = []
    var invariants: [(name: String, body: StateExpr)] = []
}

struct SimpleError: Error, CustomStringConvertible {
    let message: String
    init(_ msg: String) { self.message = msg }
    var description: String { message }
}

struct SimpleDiagnostic: DiagnosticMessage {
    let message: String
    let severity: DiagnosticSeverity
    var diagnosticID: MessageID { MessageID(domain: "SwiftTLA", id: message) }
}

func extractSpec(from statements: CodeBlockItemListSyntax) throws -> SpecData {
    var data = SpecData()
    data.variables.append(("_placeholder", .int(0)))

    for item in statements {
        guard let funcCall = item.item.as(FunctionCallExprSyntax.self),
              let callee = funcCall.calledExpression.as(DeclReferenceExprSyntax.self) else { continue }

        let args = funcCall.arguments.map { $0.expression.description.trimmingCharacters(in: .whitespaces) }

        switch callee.baseName.text {
        case "Variable":
            if args.count >= 2 {
                let name = args[0].replacingOccurrences(of: "\"", with: "")
                let val = parseValue(args[1])
                if data.variables.first?.name == "_placeholder" { data.variables.removeFirst() }
                data.variables.append((name, val))
            }
        case "Act":
            if args.count >= 1 {
                let name = args[0].replacingOccurrences(of: "\"", with: "")
                data.actions.append((name, .guard_(.value(.bool(true)))))
            }
        case "Inv":
            if args.count >= 1 {
                let name = args[0].replacingOccurrences(of: "\"", with: "")
                data.invariants.append((name, .value(.bool(true))))
            }
        case "TypeName":
            if args.count >= 1 {
                data.typeName = args[0].replacingOccurrences(of: "\"", with: "")
            }
        default: break
        }
    }
    return data
}

func parseValue(_ s: String) -> TLAValue {
    if let n = Int(s) { return .int(n) }
    if s == "true" { return .bool(true) }
    if s == "false" { return .bool(false) }
    return .int(0)
}

func buildSpec(from data: SpecData) throws -> TLASpec {
    return TLASpec(
        name: data.typeName,
        variables: data.variables.map { NamedVar(name: $0.name, initial: $0.initial) },
        actions: data.actions.map { NamedAction(name: $0.name, body: $0.body) },
        invariants: data.invariants.map { NamedInvariant(name: $0.name, body: $0.body) }
    )
}

struct StateMachineGen {
    let specData: SpecData
    let graph: StateGraph

    func generate() -> String {
        let name = specData.typeName
        let vars = specData.variables
        let actions = specData.actions
        let sortedIDs = graph.states.keys.sorted { $0.id < $1.id }

        var out = ""
        out += "// Verified: \(sortedIDs.count) reachable states\n"
        out += "struct \(name): Equatable, Hashable, Codable, Sendable {\n"
        for v in vars { out += "    var \(v.name): Int\n" }
        out += "\n"
        let params = vars.map { "\($0.name): Int" }.joined(separator: ", ")
        out += "    init(\(params)) {\n"
        for v in vars { out += "        self.\(v.name) = \(v.name)\n" }
        out += "    }\n"
        out += "\n"
        let initVals = vars.map { "\($0.name): \(tlaStr($0.initial))" }.joined(separator: ", ")
        out += "    static let initial = \(name)(\(initVals))\n"
        out += "}\n"

        out += "\nextension \(name) {\n"
        out += "    var transitions: [(action: \(name).Action, target: \(name))] {\n"
        out += "        switch (\(vars.map { "self.\($0.name)" }.joined(separator: ", "))) {\n"
        for stateID in sortedIDs {
            let state = graph.states[stateID]!
            let pattern = vars.map { name in
                if let v = state[name.name], case .int(let n) = v { return "\(n)" }
                return "_"
            }.joined(separator: ", ")
            let trans = (graph.transitions[stateID] ?? []).filter { act, targetID in
                let target = graph.states[targetID]!
                return !vars.allSatisfy { target[$0.name] == state[$0.name] }
            }
            out += "        case (\(pattern)):\n"
            if trans.isEmpty {
                out += "            return []\n"
            } else {
                out += "            return [\n"
                for (act, targetID) in trans {
                    let actCase = act.prefix(1).lowercased() + act.dropFirst()
                    let targetState = graph.states[targetID]!
                    let tparams = vars.map { name in
                        if let v = targetState[name.name], case .int(let n) = v { return "\(n)" }
                        return "0"
                    }.joined(separator: ", ")
                    out += "                (.\(actCase), \(name)(\(name): \(tparams))),\n"
                }
                out += "            ]\n"
            }
        }
        out += "        default: return []\n"
        out += "        }\n"
        out += "    }\n"
        out += "\n"
        out += "    mutating func apply(_ action: \(name).Action) {\n"
        out += "        guard let next = transitions.first(where: { $0.action == action })?.target else { return }\n"
        out += "        self = next\n"
        out += "    }\n"
        out += "}\n"

        out += "\nextension \(name) {\n"
        out += "    enum Action: String, CaseIterable, Identifiable, Codable, Sendable {\n"
        for act in actions {
            let caseName = act.name.prefix(1).lowercased() + act.name.dropFirst()
            out += "        case \(caseName)\n"
        }
        out += "\n        var id: Self { self }\n"
        out += "    }\n"
        out += "}\n"
        return out
    }

    func tlaStr(_ v: TLAValue) -> String {
        if case .int(let n) = v { return "\(n)" }
        if case .bool(let b) = v { return "\(b)" }
        return "0"
    }
}

@main
struct VerifiedMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ModelMacro.self,
        AttachedTLASpecMacro.self,
    ]
}
