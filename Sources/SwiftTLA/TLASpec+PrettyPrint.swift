import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension TLASpec {
    public var tlaModule: String {
        let varNames = variables.map(\.name)
        let varsTuple = varNames.count == 1 ? varNames[0] : "<<\(varNames.joined(separator: ", "))>>"
        var lines: [String] = []

        let modName = name.replacingOccurrences(of: " ", with: "")
        lines.append("---- MODULE \(modName) ----")

        lines.append("EXTENDS \(extendsModules), FiniteSets, Sequences")
        lines.append("")

        if !constants.isEmpty {
            lines.append("CONSTANTS \(constants.keys.sorted().joined(separator: ", "))")
            for (name, value) in constants.sorted(by: { $0.key < $1.key }) {
                lines.append("ASSUME \(name) = \(value)")
            }
            lines.append("")
        }

        if let assume = assume {
            lines.append("ASSUME \(assume)")
            lines.append("")
        }

        lines.append("VARIABLES \(varNames.joined(separator: ", "))")
        lines.append("")

        for def in definitions {
            lines.append(def)
            lines.append("")
        }

        for rec in recursiveDefs {
            lines.append(rec)
            lines.append("")
        }

        let varsDef = "vars == \(varsTuple)"
        if varNames.count > 1 { lines.append(varsDef); lines.append("") }

        for inv in invariants {
            lines.append("\(inv.name) == \(inv.body)")
        }
        if !invariants.isEmpty { lines.append("") }

        if let constraint = constraint {
            lines.append("StateConstraint == \(constraint)")
            lines.append("")
        }

        let inits = variables.map { v -> String in
            if let s = v.initialSet { return "\(v.name) \\in \(s)" }
            if let expr = v.initExpr { return "\(v.name) = \(expr)" }
            return "\(v.name) = \(v.initial)"
        }
        if inits.count == 1 {
            lines.append("Init == \(inits[0])")
        } else {
            lines.append("Init ==")
            for i in inits { lines.append("  /\\ \(i)") }
        }
        lines.append("")

        for act in actions where !act.name.isEmpty {
            lines.append("\(act.name) == \(act.body)")
        }
        lines.append("")

        let actionNames = actions.filter { !$0.name.isEmpty }
        if actionNames.count == 1 && actionNames[0].name == "Next" {
            // Single action already named Next — no separate disjunction needed
        } else if actionNames.count == 1 {
            lines.append("Next == \(actionNames[0].name)")
        } else {
            lines.append("Next ==")
            for a in actions where !a.name.isEmpty {
                lines.append("  \\/ \(a.name)")
            }
        }
        lines.append("")

        lines.append("Spec ==")
        lines.append("  /\\ Init")
        lines.append("  /\\ [][Next]_\(varsTuple)")
        for f in fairness {
            lines.append("  /\\ \(f.tlaForm(vars: varsTuple))")
        }
        lines.append("")

        for t in temporalProperties {
            lines.append("\(t.name) == \(t.expr)")
        }
        if !temporalProperties.isEmpty { lines.append("") }

        for th in theorems {
            lines.append("THEOREM \(th)")
            lines.append("")
        }

        lines.append("====")
        return lines.joined(separator: "\n") + "\n"
    }

    public var base64JSON: String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return "" }
        return data.base64EncodedString()
    }

    public     static func decode(base64: String) -> TLASpec {
        let d = Data(base64Encoded: base64)!
        return try! JSONDecoder().decode(TLASpec.self, from: d)
    }
}

/// Push UNCHANGED into every OR branch after distributing AND over OR.
/// Without distribution, `assignedVars` unions all branches and a variable
/// assigned in only one arm is treated as assigned in every arm (TLC error).
public func completeAction(_ e: ActionExpr, allVars: [String]) -> ActionExpr {
    let branches = distributeActionOr(e)
    let completed: [ActionExpr] = branches.map { branch in
        let assigned = assignedVars(branch)
        let explicit = explicitUnchanged(branch)
        var result = branch
        for v in allVars where !assigned.contains(v) && !explicit.contains(v) {
            result = .and(result, .unchanged(v))
        }
        return result
    }
    guard let first = completed.first else { return e }
    return completed.dropFirst().reduce(first) { .or($0, $1) }
}

private func distributeActionOr(_ action: ActionExpr) -> [ActionExpr] {
    switch action {
    case .or(let a, let b):
        return distributeActionOr(a) + distributeActionOr(b)
    case .and(let a, let b):
        let lhs = distributeActionOr(a)
        let rhs = distributeActionOr(b)
        return lhs.flatMap { l in rhs.map { r in .and(l, r) } }
    default:
        return [action]
    }
}


