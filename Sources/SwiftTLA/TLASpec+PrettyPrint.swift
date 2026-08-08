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

        for sym in symmetrySets {
            let sortedVals = Array(sym.values).sorted(by: { $0.description < $1.description })
            let valList = sortedVals.map(\.description).joined(separator: ", ")
            lines.append("SYMMETRY Symm\(sym.variableName) == {\(valList)}")
        }
        if !symmetrySets.isEmpty { lines.append("") }

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

        for rf in recursiveFuncs {
            let underscores = rf.params.map { _ in "_" }.joined(separator: ", ")
            let params = rf.params.joined(separator: ", ")
            lines.append("RECURSIVE \(rf.name)(\(underscores))")
            lines.append("\(rf.name)(\(params)) == \(rf.body)")
            lines.append("")
        }

        for body in runtimeFuncBodies {
            lines.append(body)
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

    /// Auto-generated TLC configuration matching the module.
    public var tlaCfg: String {
        var lines: [String] = []
        lines.append("SPECIFICATION Spec")
        if checkDeadlock { lines.append("CHECK_DEADLOCK TRUE") }
        else { lines.append("CHECK_DEADLOCK FALSE") }
        if let c = constraint { lines.append("CONSTRAINT \(c)") }
        for inv in invariants { lines.append("INVARIANT \(inv.name)") }
        for t in temporalProperties { lines.append("PROPERTY \(t.name)") }
        for f in fairness {
            let vn = variables.map(\.name)
            let vt = vn.count == 1 ? vn[0] : "<<\(vn.joined(separator: ", "))>>"
            lines.append(f.tlaForm(vars: vt))
        }
        for sym in symmetrySets {
            let vals = sym.values.sorted { $0.description < $1.description }
            lines.append("SYMMETRY Symm\(sym.variableName) == {\(vals.map(\.description).joined(separator: ", "))}")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Complete TLA+ bundle: .tla module + .cfg file.
    public var tlaBundle: (tla: String, cfg: String) {
        (tlaModule, tlaCfg)
    }
}

/// Push UNCHANGED into every OR branch after distributing AND over OR.
/// Without distribution, `assignedVars` unions all branches and a variable
/// assigned in only one arm is treated as assigned in every arm (TLC error).
public func completeAction(_ e: ActionExpr, allVars: [String]) -> ActionExpr {
    let branches = distributeOr(e)
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

func distributeOr(_ action: ActionExpr) -> [ActionExpr] {
    switch action {
    case .or(let a, let b):
        return distributeOr(a) + distributeOr(b)
    case .and(let a, let b):
        let lhs = distributeOr(a)
        let rhs = distributeOr(b)
        return lhs.flatMap { l in rhs.map { r in .and(l, r) } }
    case .ifElse(let c, let t, let e):
        return distributeOr(.and(.guard_(c), t)) + distributeOr(.and(.guard_(StateExpr.not(c)), e))
    case .define(_, _, let b):
        return distributeOr(b)
    case .existsAction(let v, let s, let b):
        return distributeOr(b).map { .existsAction(v, s, $0) }
    default:
        return [action]
    }
}
