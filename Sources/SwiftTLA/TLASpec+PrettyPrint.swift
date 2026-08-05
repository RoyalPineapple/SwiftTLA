import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension TLASpec {
    public var annotatedForm: String {
        let structName = TokenSyntax(stringLiteral: name.replacingOccurrences(of: " ", with: ""))
        let structDecl = StructDeclSyntax(
            attributes: AttributeListSyntax { AttributeSyntax(stringLiteral: "@TLAModel") },
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
        let varNames = variables.map(\.name)
        let varsTuple = varNames.count == 1 ? varNames[0] : "<<\(varNames.joined(separator: ", "))>>"
        var lines: [String] = []

        let modName = name.replacingOccurrences(of: " ", with: "")
        lines.append("---- MODULE \(modName) ----")

        lines.append("EXTENDS \(extendsModules), FiniteSets, Sequences")
        lines.append("")

        if !constants.isEmpty {
            lines.append("CONSTANTS \(constants.keys.sorted().joined(separator: ", "))")
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

        let varsDef = "vars == \(varsTuple)"
        if varNames.count > 1 { lines.append(varsDef); lines.append("") }

        for inv in invariants {
            lines.append("\(inv.name) == \(inv.body)")
        }
        if !invariants.isEmpty { lines.append("") }

        let inits = variables.map { v -> String in
            if let s = v.initialSet { return "\(v.name) \\in \(s)" }
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
            let complete = completeAction(act.body, allVars: varNames)
            lines.append("\(act.name) == \(complete)")
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

private func assignedVarNames(_ e: ActionExpr) -> Set<String> {
    switch e {
    case .assign(let v, _): return [v]
    case .unchanged: return []
    case .guard_: return []
    case .chooseAction(let v, _): return [v]
    case .and(let a, let b): return assignedVarNames(a).union(assignedVarNames(b))
    case .or(let a, let b): return assignedVarNames(a).union(assignedVarNames(b))
    }
}

private func completeAction(_ e: ActionExpr, allVars: [String]) -> ActionExpr {
    switch e {
    case .or(let a, let b):
        return .or(completeAction(a, allVars: allVars), completeAction(b, allVars: allVars))
    default:
        let assigned = assignedVarNames(e)
        let explicit = explicitUnchanged(e)
        var result = e
        for v in allVars where !assigned.contains(v) && !explicit.contains(v) {
            result = .and(result, .unchanged(v))
        }
        return result
    }
}

private func explicitUnchanged(_ e: ActionExpr) -> Set<String> {
    switch e {
    case .unchanged(let v): return [v]
    case .or(let a, let b): return explicitUnchanged(a).intersection(explicitUnchanged(b))
    case .and(let a, let b): return explicitUnchanged(a).union(explicitUnchanged(b))
    default: return []
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
        let lhs = renderActionExpr(a)
        let rhs = renderActionExpr(b)
        if let last = lhs.last {
            return lhs.dropLast() + [last + " ||"] + rhs.map { "        " + $0 }
        }
        return rhs
    case .and(_, _):
        let atoms = flattenAction(e)
        let grouped = groupGuards(atoms)
        let lines = grouped.map(renderActionAtom)
        if lines.count <= 1 { return lines }
        return lines.enumerated().map { i, line in
            i < lines.count - 1 ? line + " &&" : line
        }
    default:
        return [renderActionAtom(e)]
    }
}

private func flattenAction(_ e: ActionExpr) -> [ActionExpr] {
    switch e {
    case .and(let a, let b): return flattenAction(a) + flattenAction(b)
    default: return [e]
    }
}

private func groupGuards(_ atoms: [ActionExpr]) -> [ActionExpr] {
    var result: [ActionExpr] = []
    var pending: StateExpr?
    for atom in atoms {
        if case .guard_(let cond) = atom {
            pending = cond
            continue
        }
        if let cond = pending {
            result.append(.and(.guard_(cond), atom))
            pending = nil
        } else {
            result.append(atom)
        }
    }
    return result
}

private func renderActionAtom(_ e: ActionExpr) -> String {
    switch e {
    case .assign(let vn, let rhs):
        return "\(vn).becomes(\(StateExprSyntax(from: rhs)))"
    case .unchanged(let vn):
        return "\(vn).stays"
    case .and(.guard_(let cond), .assign(let vn, let rhs)):
        return "\(vn).becomes(\(StateExprSyntax(from: rhs))).when(\(StateExprSyntax(from: cond)))"
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