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

extension StateExpr {
    /// TLA+ export spelling. The AST retains anonymous formal lambdas for
    /// parser fidelity and PlusCal source; direct applications lower only for
    /// TLA+, where anonymous operators cannot occupy operator position.
    var tlaModuleSource: String {
        StateExpr.renamingRecursiveCalls(
            in: self,
            using: { $0 },
            lowerAnonymousLambdaApplications: true
        ).description
    }
}

extension ActionExpr {
    /// TLA+ export spelling, distinct from the lossless authoring spelling.
    var tlaModuleSource: String {
        switch self {
        case .assign(let variable, let value):
            "\(variable)' = \(value.tlaModuleSource)"
        case .unchanged(let variable):
            "UNCHANGED \(variable)"
        case .guard_(let condition):
            condition.tlaModuleSource
        case .chooseAction(let variable, let set):
            "\(variable)' \\in \(set.tlaModuleSource)"
        case .existsAction(let variable, let set, let body):
            "\\E \(variable) \\in \(set.tlaModuleSource): \(body.tlaModuleSource)"
        case .define(let variable, let value, let body):
            "LET \(variable) == \(value.tlaModuleSource) IN \(body.tlaModuleSource)"
        case .ifElse(let condition, let then, let otherwise):
            "IF \(condition.tlaModuleSource) THEN (\(then.tlaModuleSource)) ELSE (\(otherwise.tlaModuleSource))"
        case .and(let lhs, let rhs):
            "(\(lhs.tlaModuleSource) /\\ \(rhs.tlaModuleSource))"
        case .or(let lhs, let rhs):
            "(\(lhs.tlaModuleSource) \\/ \(rhs.tlaModuleSource))"
        }
    }
}
}

/// Substitute a free variable reference with a concrete value in an ActionExpr.
/// A nested TLA binder can shadow the name. Its body stays unchanged.
public func substituteVar(_ param: String, with value: TLAValue, in action: ActionExpr) -> ActionExpr {
    func state(_ expression: StateExpr) -> StateExpr {
        StateExpr.substituteVariable(param, value, in: expression)
    }
    func recurse(_ expression: ActionExpr) -> ActionExpr {
        switch expression {
        case .assign(let name, let expression): return .assign(name, state(expression))
        case .unchanged: return expression
        case .guard_(let condition): return .guard_(state(condition))
        case .chooseAction(let name, let set): return .chooseAction(name, state(set))
        case .existsAction(let name, let set, let body):
            return .existsAction(name, state(set), name == param ? body : recurse(body))
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(state(condition), recurse(then), recurse(otherwise))
        case .define(let name, let definition, let body):
            return .define(name, state(definition), name == param ? body : recurse(body))
        case .and(let lhs, let rhs): return .and(recurse(lhs), recurse(rhs))
        case .or(let lhs, let rhs): return .or(recurse(lhs), recurse(rhs))
        }
    }
    return recurse(action)
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
    case .existsAction(let v, let s, let b):
        return .existsAction(v, r(s), v == from ? b : ra(b))
    case .ifElse(let c, let t, let e): return .ifElse(r(c), ra(t), ra(e))
    case .define(let v, let expr, let b):
        return .define(v, r(expr), v == from ? b : ra(b))
    case .and(let a, let b): return .and(ra(a), ra(b))
    case .or(let a, let b): return .or(ra(a), ra(b))
    }
}
