import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

extension TLASpec {
    public var annotatedDescription: String {
        let structName = TokenSyntax(stringLiteral: name.replacingOccurrences(of: " ", with: ""))
        let structDecl = StructDeclSyntax(
            attributes: AttributeListSyntax { AttributeSyntax(stringLiteral: "@TLASpec") },
            name: structName,
            memberBlock: MemberBlockSyntax {
                for v in variables {
                    DeclSyntax(stringLiteral: swiftVarDecl(v).description)
                }
                for a in actions {
                    let body = swiftActionBody(a)
                    let funcDecl = FunctionDeclSyntax(
                        leadingTrivia: Trivia.newline,
                        name: TokenSyntax(stringLiteral: a.name.lowercased()),
                        signature: FunctionSignatureSyntax(parameterClause: FunctionParameterClauseSyntax(parameters: [])),
                        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax {
                            for stmt in body.statements { stmt }
                        })
                    )
                    funcDecl
                }
                for i in invariants {
                    DeclSyntax(stringLiteral: "    var \(i.name.lowercased()): StateExpr { \(StateExprSyntax(from: i.body)) }")
                }
            }
        )
        let source = SourceFileSyntax { structDecl }
        let result = source.formatted()
        var desc = result.description
        if let firstNL = desc.firstIndex(of: "\n") {
            let after = desc.index(after: firstNL)
            desc = String(desc[after...])
        }
        return desc
    }

    public var tlaDescription: String {
        let vars = variables.map(\.name)
        var lines: [String] = ["---- MODULE \(name.replacingOccurrences(of: " ", with: "")) ----"]
        lines.append("EXTENDS Naturals, FiniteSets, Sequences\n")
        lines.append("VARIABLES \(vars.joined(separator: ", "))\n")
        let inits = variables.map { "\($0.name) = \($0.initial)" }.joined(separator: " /\\\n       ")
        lines.append("Init == \(inits)\n")
        for act in actions where !act.name.isEmpty { lines.append("\(act.name) == \(act.body)\n") }
        let nexts = actions.filter { !$0.name.isEmpty }.map(\.name).joined(separator: " \\/\n      ")
        lines.append("Next == \(nexts)\n")
        for inv in invariants { lines.append("\(inv.name) == \(inv.body)") }
        lines.append("====\n")
        return lines.joined(separator: "\n")
    }
}

private func swiftVarDecl(_ v: NamedVar) -> DeclSyntax {
    let initVal = initValueString(v.initial)
    return DeclSyntax(stringLiteral: "var \(v.name) = Var(\"\(v.name)\", \(initVal))")
}

private func initValueString(_ value: TLAValue) -> String {
    if case .int(let n) = value { return "\(n)" }
    return value.description
}

private func swiftActionBody(_ a: NamedAction) -> CodeBlockSyntax {
    let rendered = actionExprString(a.body)
    return CodeBlockSyntax(statements: CodeBlockItemListSyntax {
        CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: rendered)))
    })
}

private func actionExprString(_ e: ActionExpr) -> String {
    switch e {
    case .or(let a, let b):
        let lhs = actionExprString(a)
        let rhs = actionExprString(b)
        return "\(lhs)\n        || \(rhs)"
    case .and(let a, let b):
        let lhs = actionExprString(a)
        let rhs = actionExprString(b)
        return "\(lhs) && \(rhs)"
    case .guard_(let c):
        return "(\(StateExprSyntax(from: c)))"
    case .assign(let vn, let rhs):
        return "\(vn).next == \(StateExprSyntax(from: rhs))"
    case .unchanged(let vn):
        return "\(vn).stays"
    default:
        return e.description
    }
}

private struct StateExprSyntax: CustomStringConvertible {
    let expr: StateExpr
    init(from e: StateExpr) { self.expr = e }
    var description: String {
        switch expr {
        case .value(let v): return "\(v)"
        case .variable(let n): return n
        case .add(let a, let b): return "\(StateExprSyntax(from: a)) + \(StateExprSyntax(from: b))"
        case .subtract(let a, let b): return "\(StateExprSyntax(from: a)) - \(StateExprSyntax(from: b))"
        case .multiply(let a, let b): return "\(StateExprSyntax(from: a)) * \(StateExprSyntax(from: b))"
        case .equal(let a, let b): return "\(StateExprSyntax(from: a)) == \(StateExprSyntax(from: b))"
        case .lessThan(let a, let b): return "\(StateExprSyntax(from: a)) < \(StateExprSyntax(from: b))"
        case .lessOrEqual(let a, let b): return "\(StateExprSyntax(from: a)) <= \(StateExprSyntax(from: b))"
        case .greaterThan(let a, let b): return "\(StateExprSyntax(from: a)) > \(StateExprSyntax(from: b))"
        case .greaterOrEqual(let a, let b): return "\(StateExprSyntax(from: a)) >= \(StateExprSyntax(from: b))"
        case .not(let a): return "!(\(StateExprSyntax(from: a)))"
        case .negate(let a): return "-(\(StateExprSyntax(from: a)))"
        case .in(let a, let b): return "\(StateExprSyntax(from: a)).isIn(\(StateExprSyntax(from: b)))"
        case .union(let a, let b): return "\(StateExprSyntax(from: a)).union(\(StateExprSyntax(from: b)))"
        case .intersection(let a, let b): return "\(StateExprSyntax(from: a)).intersection(\(StateExprSyntax(from: b)))"
        case .setDifference(let a, let b): return "\(StateExprSyntax(from: a)).subtracting(\(StateExprSyntax(from: b)))"
        case .subset(let a, let b): return "\(StateExprSyntax(from: a)).isSubset(of: \(StateExprSyntax(from: b)))"
        case .cardinality(let s): return "count(of: \(StateExprSyntax(from: s)))"
        case .except(let f, let k, let v): return "\(StateExprSyntax(from: f)).updated(at: \(StateExprSyntax(from: k)), to: \(StateExprSyntax(from: v)))"
        case .functionApply(let f, let a): return "\(StateExprSyntax(from: f)).applying(\(StateExprSyntax(from: a)))"
        case .ifThenElse(let c, let t, let f): return "if \(StateExprSyntax(from: c)) { \(StateExprSyntax(from: t)) } else { \(StateExprSyntax(from: f)) }"
        case .modulo(let a, let b): return "\(StateExprSyntax(from: a)) % \(StateExprSyntax(from: b))"
        case .notEqual(let a, let b): return "\(StateExprSyntax(from: a)) != \(StateExprSyntax(from: b))"
        case .integerDivide(let a, let b): return "\(StateExprSyntax(from: a)) / \(StateExprSyntax(from: b))"
        default: return expr.description
        }
    }
}
