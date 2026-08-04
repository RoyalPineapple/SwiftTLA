import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

extension TLASpec {
    public var annotatedForm: String {
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
                    VariableDeclSyntax(
                        .let,
                        name: PatternSyntax(stringLiteral: i.name.lowercased()),
                        type: TypeAnnotationSyntax(
                            type: IdentifierTypeSyntax(name: TokenSyntax(stringLiteral: "StateExpr"))
                        ),
                        initializer: InitializerClauseSyntax(
                            value: ExprSyntax(stringLiteral: StateExprSyntax(from: i.body).description)
                        )
                    )
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

    public var tlaModule: String {
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

    public var base64JSON: String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return "" }
        return data.base64EncodedString()
    }

    public static func decode(base64: String) -> TLASpec {
        let d = Data(base64Encoded: base64)!
        return try! JSONDecoder().decode(TLASpec.self, from: d)
    }
}

private func swiftVarDecl(_ v: NamedVar) -> DeclSyntax {
    let initVal = initValueString(v.initial)
    return DeclSyntax(stringLiteral: "var \(v.name) = Var(\(initVal))")
}

private func initValueString(_ value: TLAValue) -> String {
    if case .int(let n) = value { return "\(n)" }
    return value.description
}

private func swiftActionBody(_ a: NamedAction) -> CodeBlockSyntax {
    let lines = renderActionExpr(a.body)
    let stmts = lines.map { CodeBlockItemSyntax(item: .expr(ExprSyntax(stringLiteral: $0))) }
    return CodeBlockSyntax(statements: CodeBlockItemListSyntax(stmts))
}

private func renderActionExpr(_ e: ActionExpr) -> [String] {
    switch e {
    case .or(let a, let b):
        return renderActionExpr(a) + renderActionExpr(b)
    case .and(_, _):
        return [renderAndChain(e)]
    case .assign(let vn, let rhs):
        return ["\(vn).becomes(\(StateExprSyntax(from: rhs)))"]
    case .unchanged(let vn):
        return ["\(vn).stays"]
    default:
        return [e.description]
    }
}


private func renderAndChain(_ e: ActionExpr) -> String {
    switch e {
    case .and(let a, let b):
        if case .guard_(let cond) = a, case .assign(let vn, let rhs) = b {
            return "\(vn).becomes(\(StateExprSyntax(from: rhs))).when(\(StateExprSyntax(from: cond)))"
        }
        if case .and(let innerA, let innerB) = a, case .guard_(let cond) = innerA, case .assign(let vn, let rhs) = innerB, case .assign(let vn2, let rhs2) = b {
            return "\(vn).becomes(\(StateExprSyntax(from: rhs))).when(\(StateExprSyntax(from: cond)))\n\(vn2).becomes(\(StateExprSyntax(from: rhs2)))"
        }
        return "\(renderAndChain(a)) && \(renderAndChain(b))"
    case .guard_(let cond):
        return "/* guard: \(StateExprSyntax(from: cond)) */"
    case .assign(let vn, let rhs):
        return "\(vn).becomes(\(StateExprSyntax(from: rhs)))"
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
        case .cardinality(let s): return "\(StateExprSyntax(from: s)).cardinality"
        case .domain(let d): return "\(StateExprSyntax(from: d)).domain"
        case .powerSet(let s): return "\(StateExprSyntax(from: s)).subsets"
        case .unionAll(let s): return "\(StateExprSyntax(from: s)).flattened"
        case .tupleLength(let t): return "\(StateExprSyntax(from: t)).count"
        case .setFilter(let s, let p): return "\(StateExprSyntax(from: s)).filtering(\(StateExprSyntax(from: p)))"
        case .setMap(let e, let s): return "\(StateExprSyntax(from: s)).mapping(\(StateExprSyntax(from: e)))"
        case .tupleAppend(let t, let e): return "\(StateExprSyntax(from: t)).appending(\(StateExprSyntax(from: e)))"
        case .tupleConcatenate(let a, let b): return "\(StateExprSyntax(from: a)).concatenating(\(StateExprSyntax(from: b)))"
        case .forAll(let s, let p): return "StateExpr.for(allIn: \(StateExprSyntax(from: s)), \(StateExprSyntax(from: p)))"
        case .exists(let s, let p): return "StateExpr.exists(in: \(StateExprSyntax(from: s)), \(StateExprSyntax(from: p)))"
        case .choose(let s, let p): return "StateExpr.choose(from: \(StateExprSyntax(from: s)), matching: \(StateExprSyntax(from: p)))"
        case .functionLiteral(let d, let b): return "StateExpr.function(domain: \(StateExprSyntax(from: d)), \(StateExprSyntax(from: b)))"
        case .setLiteral(let es): return "StateExpr.set([\(es.map { StateExprSyntax(from: $0).description }.joined(separator: ", ")))])"
        case .tupleLiteral(let es): return "StateExpr.tuple([\(es.map { StateExprSyntax(from: $0).description }.joined(separator: ", ")))])"
        case .enabledAction(let n): return "StateExpr.enabled(\"\(n)\")"
        case .except(let f, let k, let v): return "\(StateExprSyntax(from: f)).updated(at: \(StateExprSyntax(from: k)), to: \(StateExprSyntax(from: v)))"
        case .functionApply(let f, let a): return "\(StateExprSyntax(from: f)).applying(\(StateExprSyntax(from: a)))"
        case .ifThenElse(let c, let t, let f): return "if \(StateExprSyntax(from: c)) { \(StateExprSyntax(from: t)) } else { \(StateExprSyntax(from: f)) }"
        case .modulo(let a, let b): return "\(StateExprSyntax(from: a)) % \(StateExprSyntax(from: b))"
        case .and(let a, let b): return "\(StateExprSyntax(from: a)) && \(StateExprSyntax(from: b))"
        case .or(let a, let b): return "\(StateExprSyntax(from: a)) || \(StateExprSyntax(from: b))"
        case .notEqual(let a, let b): return "\(StateExprSyntax(from: a)) != \(StateExprSyntax(from: b))"
        case .integerDivide(let a, let b): return "\(StateExprSyntax(from: a)) / \(StateExprSyntax(from: b))"
        default: return expr.description
        }
    }
}