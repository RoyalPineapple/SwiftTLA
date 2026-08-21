public enum ActionTarget: Hashable, Sendable, CustomStringConvertible {
    case named(String)
    case programCounter
    case procedureStack

    public var description: String {
        switch self {
        case .named(let name): return name
        case .programCounter: return CompilerControlSymbol.programCounter.rawValue
        case .procedureStack: return CompilerControlSymbol.stack.rawValue
        }
    }
}

public indirect enum ActionExpr: Hashable, Sendable, CustomStringConvertible {
    case assign(ActionTarget, StateExpr)
    case unchanged(ActionTarget)
    case guard_(StateExpr)
    case chooseAction(ActionTarget, StateExpr)
    case existsAction(String, StateExpr, ActionExpr)
    case ifElse(StateExpr, ActionExpr, ActionExpr)
    case define(String, StateExpr, ActionExpr)
    case and(ActionExpr, ActionExpr)
    case or(ActionExpr, ActionExpr)

    public var description: String {
        switch self {
        case .assign(let target, let e):
            return "\(target)' = \(e)"
        case .unchanged(let target):
            return "UNCHANGED \(target)"
        case .guard_(let e):
            return "\(e)"
        case .chooseAction(let target, let s):
            return "\(target)' \\in \(s)"
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
        case .assign(let target, let value):
            "\(target)' = \(value.tlaModuleSource)"
        case .unchanged(let target):
            "UNCHANGED \(target)"
        case .guard_(let condition):
            condition.tlaModuleSource
        case .chooseAction(let target, let set):
            "\(target)' \\in \(set.tlaModuleSource)"
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

extension ActionExpr {
    package func substitutingVariable(_ name: String, with replacement: StateExpr) -> ActionExpr {
        func state(_ expression: StateExpr) -> StateExpr {
            StateExpr.substituteVariable(name, with: replacement, in: expression)
        }
        func action(_ expression: ActionExpr) -> ActionExpr {
            switch expression {
            case .assign(let target, let value): return .assign(target, state(value))
            case .unchanged: return expression
            case .guard_(let condition): return .guard_(state(condition))
            case .chooseAction(let target, let values): return .chooseAction(target, state(values))
            case .existsAction(let binder, let values, let body): return .existsAction(binder, state(values), binder == name ? body : action(body))
            case .ifElse(let condition, let then, let otherwise): return .ifElse(state(condition), action(then), action(otherwise))
            case .define(let binder, let value, let body): return .define(binder, state(value), binder == name ? body : action(body))
            case .and(let lhs, let rhs): return .and(action(lhs), action(rhs))
            case .or(let lhs, let rhs): return .or(action(lhs), action(rhs))
            }
        }
        return action(self)
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

package func renameVar(_ from: String, to: String, in action: ActionExpr) -> ActionExpr {
    func r(_ s: StateExpr) -> StateExpr { renameVar(from, to: to, in: s) }
    func ra(_ a: ActionExpr) -> ActionExpr { renameVar(from, to: to, in: a) }
    switch action {
    case .assign(let target, let e): return .assign(rename(target), r(e))
    case .unchanged(let target): return .unchanged(rename(target))
    case .guard_(let e): return .guard_(r(e))
    case .chooseAction(let target, let s): return .chooseAction(rename(target), r(s))
    case .existsAction(let v, let s, let b):
        return .existsAction(v, r(s), v == from ? b : ra(b))
    case .ifElse(let c, let t, let e): return .ifElse(r(c), ra(t), ra(e))
    case .define(let v, let expr, let b):
        return .define(v, r(expr), v == from ? b : ra(b))
    case .and(let a, let b): return .and(ra(a), ra(b))
    case .or(let a, let b): return .or(ra(a), ra(b))
    }

    func rename(_ target: ActionTarget) -> ActionTarget {
        guard case .named(let name) = target, name == from else { return target }
        return .named(to)
    }
}
