import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension TLASpec {
    public var swiftSource: String {
        var lines: [String] = []
        lines.append("@TLAModel")
        lines.append("public struct \(name.replacingOccurrences(of: " ", with: "")) {")
        lines.append("    static var spec: TLASpec {")
        lines.append("        TLASpec(\"\(name)\") {")
        if extendsModules != "Integers" { lines.append("            Extends(\"\(extendsModules)\")") }
        for (k, v) in constants.sorted(by: { $0.key < $1.key }) { lines.append("            Constant(\"\(k)\", \(v.swiftLiteral))") }
        for v in variables {
            let initStr: String
            if let s = v.initialSet { initStr = "in: \(s.swiftSource)" }
            else { initStr = "\(v.initial.swiftLiteral)" }
            lines.append("            Variable(Var<Int>(\"\(v.name)\"), \(initStr))")
        }
        for a in actions { lines.append("            Action(\"\(a.name)\") { \(a.body.swiftSource) }") }
        for i in invariants { lines.append("            Invariant(\"\(i.name)\") { \(i.body.swiftSource) }") }
        for t in temporalProperties { lines.append("            Temporal(\"\(t.name)\") { \(t.expr.swiftSource) }") }
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}

extension TLAValue {
    public var swiftLiteral: String {
        switch self {
        case .int(let n): return "\(n)"
        case .bool(let b): return "\(b)"
        case .string(let s): return "\"\(s)\""
        case .set(let s): return "StateExpr.set([\(s.map(\.swiftLiteral).joined(separator: ", "))])"
        case .tuple(let t): return "StateExpr.tuple([\(t.map(\.swiftLiteral).joined(separator: ", "))])"
        case .record(let r): return "StateExpr.record([\(r.sorted(by: {$0.key<$1.key}).map {"\"\($0.key)\": \($0.value.swiftLiteral)"}.joined(separator: ", "))])"
        case .function: return "StateExpr.function(domain: StateExpr.set([]), 0)"  // placeholder
        case .constant(let n): return "TLAValue.constant(\"\(n)\")"
        }
    }
}

extension ActionExpr {
    var swiftSource: String {
        switch self {
        case .assign(let v, let e): return "\(v).becomes(\(e.swiftSource))"
        case .unchanged(let v): return "\(v).stays"
        case .guard_(let e): return e.swiftSource
        case .chooseAction(let v, let s): return "ActionExpr.choose(\"\(v)\", from: \(s.swiftSource))"
        case .and(let a, let b): return "\(a.swiftSource) && \(b.swiftSource)"
        case .or(let a, let b): return "\(a.swiftSource) || \(b.swiftSource)"
        }
    }
}

extension StateExpr {
    var swiftSource: String {
        switch self {
        case .value(let v): return v.swiftLiteral
        case .variable(let n): return n
        case .add(let a, let b): return "\(a.swiftSource) + \(b.swiftSource)"
        case .subtract(let a, let b): return "\(a.swiftSource) - \(b.swiftSource)"
        case .multiply(let a, let b): return "\(a.swiftSource) * \(b.swiftSource)"
        case .divide(let a, let b): return "\(a.swiftSource) / \(b.swiftSource)"
        case .modulo(let a, let b): return "\(a.swiftSource) % \(b.swiftSource)"
        case .negate(let a): return "-(\(a.swiftSource))"
        case .equal(let a, let b): return "\(a.swiftSource) == \(b.swiftSource)"
        case .notEqual(let a, let b): return "\(a.swiftSource) != \(b.swiftSource)"
        case .lessThan(let a, let b): return "\(a.swiftSource) < \(b.swiftSource)"
        case .lessOrEqual(let a, let b): return "\(a.swiftSource) <= \(b.swiftSource)"
        case .greaterThan(let a, let b): return "\(a.swiftSource) > \(b.swiftSource)"
        case .greaterOrEqual(let a, let b): return "\(a.swiftSource) >= \(b.swiftSource)"
        case .and(let a, let b): return "\(a.swiftSource) && \(b.swiftSource)"
        case .or(let a, let b): return "\(a.swiftSource) || \(b.swiftSource)"
        case .not(let a): return "!\(a.swiftSource)"
        case .in(let a, let b): return "\(a.swiftSource).isIn(\(b.swiftSource))"
        case .setLiteral(let es): return "StateExpr.set([\(es.map(\.swiftSource).joined(separator: ", "))])"
        case .ifThenElse(let c, let t, let f): return "\(c.swiftSource) ? \(t.swiftSource) : \(f.swiftSource)"
        default: return description
        }
    }
}

extension TemporalExpr {
    var swiftSource: String {
        switch self {
        case .always(let p): return "always(\(p.swiftSource))"
        case .eventually(let p): return "eventually(\(p.swiftSource))"
        case .alwaysEventually(let p): return "alwaysEventually(\(p.swiftSource))"
        case .eventuallyAlways(let p): return "eventuallyAlways(\(p.swiftSource))"
        case .leadsTo(let p, let q): return "\(p.swiftSource).leadsTo(\(q.swiftSource))"
        }
    }
}
