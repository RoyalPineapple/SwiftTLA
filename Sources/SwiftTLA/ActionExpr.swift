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
        case .assign(let v, let e): return "\(v)' = \(e)"
        case .unchanged(let v): return "UNCHANGED \(v)"
        case .guard_(let e): return "\(e)"
        case .chooseAction(let v, let s): return "\(v)' \\in \(s)"
        case .existsAction(let v, let s, let b): return "\\E \(v) \\in \(s): \(b)"
        case .define(let v, let e, let b): return "LET \(v) == \(e) IN \(b)"
        case .ifElse(let c, let t, let e): return "IF \(c) THEN (\(t)) ELSE (\(e))"
        case .and(let a, let b): return "(\(a) /\\ \(b))"
        case .or(let a, let b): return "(\(a) \\/ \(b))"
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
