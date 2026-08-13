public indirect enum ActionExpr: Hashable, Sendable, CustomStringConvertible {
    case assign(String, StateExpr)
    case unchanged(String)
    case guard_(StateExpr)
    case chooseAction(String, StateExpr)
    case existsAction(String, StateExpr, ActionExpr)
    case ifElse(StateExpr, ActionExpr, ActionExpr)
    case define(String, StateExpr, ActionExpr)
    case and(ActionExpr, ActionExpr)
    case or(ActionExpr, ActionExpr)

    public var description: String {
        switch self {
        case .assign(let v, let e):
            return "\(v)' = \(e)"
        case .unchanged(let v):
            return "UNCHANGED \(v)"
        case .guard_(let e):
            return "\(e)"
        case .chooseAction(let v, let s):
            return "\(v)' \\in \(s)"
        case .existsAction(let v, let s, let b):
            return "\\E \(v) \\in \(s): \(b)"
        case .define(let v, let e, let b):
            return "LET \(v) == \(e) IN \(b)"
        case .ifElse(let c, let t, let e):
            return "IF \(c) THEN (\(t)) ELSE (\(e))"
        case .and(let a, let b):
            return "(\(a) /\\ \(b))"
        case .or(let a, let b):
            return "(\(a) \\/ \(b))"
        }
}

/// Substitute a variable reference with a concrete value in an ActionExpr.
/// Uses rename-then-replace: rename `param` → temp, then replace temp → .value(value).
public func substituteVar(_ param: String, with value: TLAValue, in action: ActionExpr) -> ActionExpr {
    let temp = "_\(param)_s_"
    let renamed = renameVar(param, to: temp, in: action)
    return replaceTemp(temp, with: value, in: renamed)
}
private func replaceTemp(_ temp: String, with value: TLAValue, in a: ActionExpr) -> ActionExpr {
    func rs(_ s: StateExpr) -> StateExpr { replaceTemp(temp, with: value, in: s) }
    func ra(_ a: ActionExpr) -> ActionExpr { replaceTemp(temp, with: value, in: a) }
    switch a {
    case .assign(let v, let e): return .assign(v, rs(e))
    case .unchanged: return a
    case .guard_(let e): return .guard_(rs(e))
    case .chooseAction(let v, let s): return .chooseAction(v, rs(s))
    case .existsAction(let v, let s, let b): return .existsAction(v, rs(s), ra(b))
    case .ifElse(let c, let t, let e): return .ifElse(rs(c), ra(t), ra(e))
    case .define(let v, let e, let b): return .define(v, rs(e), ra(b))
    case .and(let a, let b): return .and(ra(a), ra(b))
    case .or(let a, let b): return .or(ra(a), ra(b))
    }
}
private func replaceTemp(_ temp: String, with value: TLAValue, in s: StateExpr) -> StateExpr {
    if case .variable(temp) = s { return .value(value) }
    func r(_ s: StateExpr) -> StateExpr { replaceTemp(temp, with: value, in: s) }
    switch s {
    case .value, .variable, .enabledAction: return s
    case .add(let a, let b): return .add(r(a), r(b))
    case .subtract(let a, let b): return .subtract(r(a), r(b))
    case .multiply(let a, let b): return .multiply(r(a), r(b))
    case .divide(let a, let b): return .divide(r(a), r(b))
    case .modulo(let a, let b): return .modulo(r(a), r(b))
    case .negate(let a): return .negate(r(a))
    case .integerDivide(let a, let b): return .integerDivide(r(a), r(b))
    case .equal(let a, let b): return .equal(r(a), r(b))
    case .notEqual(let a, let b): return .notEqual(r(a), r(b))
    case .lessThan(let a, let b): return .lessThan(r(a), r(b))
    case .lessOrEqual(let a, let b): return .lessOrEqual(r(a), r(b))
    case .greaterThan(let a, let b): return .greaterThan(r(a), r(b))
    case .greaterOrEqual(let a, let b): return .greaterOrEqual(r(a), r(b))
    case .and(let a, let b): return .and(r(a), r(b))
    case .or(let a, let b): return .or(r(a), r(b))
    case .not(let a): return .not(r(a))
    case .ifThenElse(let c, let t, let e): return .ifThenElse(r(c), r(t), r(e))
    case .setLiteral(let es): return .setLiteral(es.map(r))
    case .in(let e, let s): return .in(r(e), r(s))
    case .subset(let a, let b): return .subset(r(a), r(b))
    case .union(let a, let b): return .union(r(a), r(b))
    case .intersection(let a, let b): return .intersection(r(a), r(b))
    case .setDifference(let a, let b): return .setDifference(r(a), r(b))
    case .cardinality(let a): return .cardinality(r(a))
    case .setFilter(let a, let qv, let b): return .setFilter(r(a), qv, r(b))
    case .setMap(let a, let qv, let b): return .setMap(r(a), qv, r(b))
    case .powerSet(let a): return .powerSet(r(a))
    case .unionAll(let a): return .unionAll(r(a))
    case .tupleLiteral(let es): return .tupleLiteral(es.map(r))
    case .tupleAccess(let t, let i): return .tupleAccess(r(t), i)
    case .tupleLength(let t): return .tupleLength(r(t))
    case .tupleAppend(let t, let e): return .tupleAppend(r(t), r(e))
    case .tupleHead(let t): return .tupleHead(r(t))
    case .tupleTail(let t): return .tupleTail(r(t))
    case .tupleConcatenate(let a, let b): return .tupleConcatenate(r(a), r(b))
    case .recordLiteral(let d): return .recordLiteral(d.mapValues(r))
    case .recordAccess(let rec, let f): return .recordAccess(r(rec), f)
    case .domain(let rec): return .domain(r(rec))
    case .functionLiteral(let d, let qv, let b): return .functionLiteral(r(d), qv, r(b))
    case .functionApply(let f, let a): return .functionApply(r(f), r(a))
    case .except(let f, let k, let v): return .except(r(f), r(k), r(v))
    case .caseExpr(let cases, let fallback):
        return .caseExpr(cases.map(r), fallback.map(r))
    case .forAll(let a, let qv, let b): return .forAll(r(a), qv, r(b))
    case .exists(let a, let qv, let b): return .exists(r(a), qv, r(b))
    case .choose(let a, let qv, let b): return .choose(r(a), qv, r(b))
    case .sequenceFromSet(let a): return .sequenceFromSet(r(a))
    case .setSum(let f, let s): return .setSum(r(f), r(s))
    case .functionSet(let d, let rng): return .functionSet(r(d), r(rng))
    case .recursiveCall(let n, let args): return .recursiveCall(n, args.map(r))
    }
}
}

extension ActionExpr {
    @discardableResult public static func && (lhs: ActionExpr, rhs: ActionExpr) -> ActionExpr { .and(lhs, rhs) }
    @discardableResult public static func || (lhs: ActionExpr, rhs: ActionExpr) -> ActionExpr { .or(lhs, rhs) }
}

extension ActionExpr {
    @discardableResult public static func && (lhs: ActionExpr, rhs: StateExpr) -> ActionExpr { .and(lhs, .guard_(rhs)) }
    @discardableResult public static func && (lhs: StateExpr, rhs: ActionExpr) -> ActionExpr { .and(.guard_(lhs), rhs) }
    @discardableResult public static func || (lhs: ActionExpr, rhs: StateExpr) -> ActionExpr { .or(lhs, .guard_(rhs)) }
    @discardableResult public static func || (lhs: StateExpr, rhs: ActionExpr) -> ActionExpr { .or(.guard_(lhs), rhs) }
}

public func renameVar(_ from: String, to: String, in action: ActionExpr) -> ActionExpr {
    func r(_ s: StateExpr) -> StateExpr { renameVar(from, to: to, in: s) }
    func ra(_ a: ActionExpr) -> ActionExpr { renameVar(from, to: to, in: a) }
    switch action {
    case .assign(let v, let e): return .assign(v == from ? to : v, r(e))
    case .unchanged(let v): return .unchanged(v == from ? to : v)
    case .guard_(let e): return .guard_(r(e))
    case .chooseAction(let v, let s): return .chooseAction(v == from ? to : v, r(s))
    case .existsAction(let v, let s, let b): return .existsAction(v == from ? to : v, r(s), ra(b))
    case .ifElse(let c, let t, let e): return .ifElse(r(c), ra(t), ra(e))
    case .define(let v, let expr, let b): return .define(v == from ? to : v, r(expr), ra(b))
    case .and(let a, let b): return .and(ra(a), ra(b))
    case .or(let a, let b): return .or(ra(a), ra(b))
    }
}
