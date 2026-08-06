public indirect enum ActionExpr: Hashable, Codable, Sendable, CustomStringConvertible {
    case assign(String, StateExpr)
    case unchanged(String)
    case guard_(StateExpr)
    case chooseAction(String, StateExpr)  // CHOOSE var \in set : TRUE
    case and(ActionExpr, ActionExpr)
    case or(ActionExpr, ActionExpr)

    public var description: String {
        switch self {
        case .assign(let v, let e): return "\(v)' = \(e)"
        case .unchanged(let v): return "UNCHANGED \(v)"
        case .guard_(let e): return "\(e)"
        case .chooseAction(let v, let s): return "\(v)' \\in \(s)"
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
