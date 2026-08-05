import SwiftSyntax

/// Parses SwiftSyntax AST into DSL types (StateExpr, ActionExpr, etc.).
/// Pure transformation — every AST pattern maps deterministically to a DSL value.
/// Tested via matrix tests in SpecParserTests.
public enum SpecParser {
    // MARK: - Top-level

    public static func parseStateExpr(_ expression: ExprSyntax?) -> StateExpr? {
        guard let expression else { return nil }
        if let int = expression.as(IntegerLiteralExprSyntax.self) { return .value(.int(Int(int.literal.text) ?? 0)) }
        if let bool = expression.as(BooleanLiteralExprSyntax.self) { return .value(.bool(bool.literal.text == "true")) }
        if let reference = expression.as(DeclReferenceExprSyntax.self) { return .variable(reference.baseName.text) }
        if let call = expression.as(FunctionCallExprSyntax.self) { return parseMethodCall(call) }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) { return parseMemberAccess(memberAccess) }
        if let tuple = expression.as(TupleExprSyntax.self), let single = tuple.elements.first?.expression { return parseStateExpr(single) }
        if let infix = expression.as(InfixOperatorExprSyntax.self), let left = parseStateExpr(infix.leftOperand), let right = parseStateExpr(infix.rightOperand) {
            return parseInfixOp(left, right, infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text)
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3, let left = parseStateExpr(elements[0]),
                  let opText = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let right = parseStateExpr(elements[2]) else { return nil }
            return parseInfixOp(left, right, opText)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            let operand = parseStateExpr(prefix.expression)
            if prefix.operator.text == "!", let operand { return .not(operand) }
            if prefix.operator.text == "-", let operand { return .negate(operand) }
        }
        return nil
    }

    private static func parseInfixOp(_ left: StateExpr, _ right: StateExpr, _ op: String?) -> StateExpr? {
        switch op {
        case "+": .add(left, right); case "-": .subtract(left, right)
        case "*": .multiply(left, right); case "/": .divide(left, right); case "%": .modulo(left, right)
        case "<": .lessThan(left, right); case "<=": .lessOrEqual(left, right)
        case ">": .greaterThan(left, right); case ">=": .greaterOrEqual(left, right)
        case "==": .equal(left, right); case "!=": .notEqual(left, right)
        case "&&": .and(left, right); case "||": .or(left, right)
        default: nil
        }
    }

    // MARK: - Action parsing

    public static func parseActionFrom(_ closure: ClosureExprSyntax) -> ActionExpr? {
        let actions = closure.statements.compactMap { stmt -> ActionExpr? in
            guard case .expr(let inner) = stmt.item else { return nil }
            return parseSingleAction(inner)
        }
        if actions.isEmpty { return .guard_(.value(.bool(true))) }
        return actions.dropFirst().reduce(actions[0]) { .and($0, $1) }
    }

    public static func parseSingleAction(_ expression: ExprSyntax) -> ActionExpr? {
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text
            if op == "||", let l = parseSingleAction(infix.leftOperand), let r = parseSingleAction(infix.rightOperand) { return .or(l, r) }
            if op == "&&" {
                let ls = parseStateExpr(infix.leftOperand); let rs = parseStateExpr(infix.rightOperand)
                let la = ls == nil ? parseSingleAction(infix.leftOperand) : nil
                let ra = rs == nil ? parseSingleAction(infix.rightOperand) : nil
                if let g = ls, let a = ra { return .and(.guard_(g), a) }
                if let a = la, let g = rs { return .and(a, .guard_(g)) }
                if let a = la, let b = ra { return .and(a, b) }
            }
        }
        if let seq = expression.as(SequenceExprSyntax.self) {
            let e = Array(seq.elements)
            guard e.count == 3, let op = e[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
                  let l = parseSingleAction(e[0]), let r = parseSingleAction(e[2]) else { return nil }
            if op == "||" { return .or(l, r) }
            if op == "&&" { return .and(l, r) }
        }
        if let call = expression.as(FunctionCallExprSyntax.self), let chain = parseBecomesChain(call) { return chain }
        if let ma = expression.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "stays",
           let base = ma.base?.as(DeclReferenceExprSyntax.self) { return .unchanged(base.baseName.text) }
        return nil
    }

    private struct Chain { let call: FunctionCallExprSyntax; let condition: StateExpr? }
    private static func unwrapWhen(_ call: FunctionCallExprSyntax) -> Chain {
        if let ma = call.calledExpression.as(MemberAccessExprSyntax.self), ma.declName.baseName.text == "when",
           let base = ma.base?.as(FunctionCallExprSyntax.self) {
            let cond = parseStateExpr(call.arguments.first?.expression)
            let inner = unwrapWhen(base)
            if let c = cond, let ic = inner.condition { return Chain(call: inner.call, condition: .and(c, ic)) }
            return Chain(call: inner.call, condition: cond ?? inner.condition)
        }
        return Chain(call: call, condition: nil)
    }
    private static func parseBecomesChain(_ call: FunctionCallExprSyntax) -> ActionExpr? {
        let chain = unwrapWhen(call)
        guard let (vn, val) = parseBecomes(chain.call) else { return nil }
        let a = ActionExpr.assign(vn, val)
        return chain.condition.map { .and(.guard_($0), a) } ?? a
    }
    private static func parseBecomes(_ call: FunctionCallExprSyntax) -> (String, StateExpr)? {
        guard let ma = call.calledExpression.as(MemberAccessExprSyntax.self),
              ma.declName.baseName.text == "becomes",
              let base = ma.base?.as(DeclReferenceExprSyntax.self),
              let arg = call.arguments.first?.expression else { return nil }
        return (base.baseName.text, parseStateExpr(arg) ?? .value(.int(0)))
    }

    // MARK: - Temporal

    public static func parseTemporal(_ expr: ExprSyntax) -> TemporalExpr? {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let ref = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        let m = ref.declName.baseName.text
        let arg = call.arguments.first.flatMap { parseStateExpr($0.expression) }
        switch m {
        case "leadsTo": return arg.map { .leadsTo(parseStateExpr(ref.base) ?? .value(.bool(true)), $0) }
        case "always": return arg.map { .always($0) }
        case "eventually": return arg.map { .eventually($0) }
        case "alwaysEventually": return arg.map { .alwaysEventually($0) }
        case "eventuallyAlways": return arg.map { .eventuallyAlways($0) }
        default: return nil
        }
    }

    // MARK: - Fairness

    public static func parseFairnessExpr(_ expr: ExprSyntax) -> FairnessCondition? {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let ref = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        let m = ref.declName.baseName.text
        let name = call.arguments.first?.expression.as(StringLiteralExprSyntax.self)?.segments.description.replacingOccurrences(of: "\"", with: "") ?? ""
        switch m {
        case "weakFairness": return .weakFairness(name)
        case "strongFairness": return .strongFairness(name)
        default: return nil
        }
    }

    // MARK: - Method calls

    private static func parseMethodCall(_ call: FunctionCallExprSyntax) -> StateExpr? {
        guard let ma = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        let method = ma.declName.baseName.text; let arg = call.arguments.first?.expression; let base = ma.base
        switch method {
        case "isIn": return bin { .in($0, $1) }
        case "union": return bin { .union($0, $1) }
        case "intersection": return bin { .intersection($0, $1) }
        case "subtracting": return bin { .setDifference($0, $1) }
        case "isSubset": return bin { .subset($0, $1) }
        case "updated": return mod2 { .except($0, $1.0, $1.1) }
        case "applying": return bin { .functionApply($0, $1) }
        case "filtering": return bin { .setFilter($0, $1) }
        case "mapping": return bin { .setMap($1, $0) }
        case "appending": return bin { .tupleAppend($0, $1) }
        case "concatenating": return bin { .tupleConcatenate($0, $1) }
        default:
            if let rb = ma.base?.as(DeclReferenceExprSyntax.self), rb.baseName.text == "StateExpr" {
                return parseStaticCall(memberAccess: ma, arguments: Array(call.arguments), method: method)
            }
            return nil
        }

        func bin(_ f: (StateExpr, StateExpr) -> StateExpr) -> StateExpr? {
            guard let base, let s = parseStateExpr(base), let a = parseStateExpr(arg) else { return nil }
            return f(s, a)
        }
        func mod2(_ f: (StateExpr, (StateExpr, StateExpr)) -> StateExpr) -> StateExpr? {
            let args = Array(call.arguments)
            guard let base, let s = parseStateExpr(base), args.count >= 2,
                  let k = parseStateExpr(args[0].expression), let v = parseStateExpr(args[1].expression) else { return nil }
            return f(s, (k, v))
        }
    }

    private static func parseStaticCall(memberAccess: MemberAccessExprSyntax, arguments: [LabeledExprSyntax], method: String) -> StateExpr? {
        switch method {
        case "set":
            let es = arguments.first?.expression.as(ArrayExprSyntax.self)?.elements.compactMap { parseStateExpr($0.expression) } ?? []
            return .setLiteral(es)
        case "tuple":
            let es = arguments.first?.expression.as(ArrayExprSyntax.self)?.elements.compactMap { parseStateExpr($0.expression) } ?? []
            return .tupleLiteral(es)
        case "record":
            var f: [String: StateExpr] = [:]
            for a in arguments { guard let l = a.label?.text, let v = parseStateExpr(a.expression) else { return nil }; f[l] = v }
            return .recordLiteral(f)
        case "if":
            guard arguments.count >= 3, let c = parseStateExpr(arguments[0].expression),
                  let t = parseStateExpr(arguments[1].expression), let e = parseStateExpr(arguments[2].expression) else { return nil }
            return .ifThenElse(c, t, e)
        case "enabled":
            let n = arguments.first?.expression.as(StringLiteralExprSyntax.self)?.segments.description.replacingOccurrences(of: "\"", with: "") ?? ""
            return .enabledAction(n)
        case "function":
            guard arguments.count >= 2, let d = parseStateExpr(arguments[0].expression), let b = parseStateExpr(arguments[1].expression) else { return nil }
            return .functionLiteral(d, b)
        case "for":
            guard arguments.count >= 2, let s = parseStateExpr(arguments[0].expression), let p = parseStateExpr(arguments[1].expression) else { return nil }
            return .forAll(s, p)
        case "exists":
            guard arguments.count >= 2, let s = parseStateExpr(arguments[0].expression), let p = parseStateExpr(arguments[1].expression) else { return nil }
            return .exists(s, p)
        case "choose":
            guard arguments.count >= 2, let s = parseStateExpr(arguments[0].expression), let p = parseStateExpr(arguments[1].expression) else { return nil }
            return .choose(s, p)
        default: return nil
        }
    }

    private static func parseMemberAccess(_ ma: MemberAccessExprSyntax) -> StateExpr? {
        let p = ma.declName.baseName.text
        guard let base = ma.base, let s = parseStateExpr(base) else { return nil }
        switch p {
        case "cardinality": return .cardinality(s)
        case "flattened": return .unionAll(s)
        case "subsets": return .powerSet(s)
        case "domain": return .domain(s)
        case "count": return .tupleLength(s)
        default: return nil
        }
    }
}
