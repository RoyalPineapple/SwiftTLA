public enum ActionTarget: Hashable, Sendable {
    case named(String)
    case programCounter
    case procedureStack
}

public indirect enum ActionExpr: Hashable, Sendable {
    case assign(ActionTarget, StateExpr)
    case unchanged(ActionTarget)
    case guard_(StateExpr)
    case existsAction(String, StateExpr, ActionExpr)
    case ifElse(StateExpr, ActionExpr, ActionExpr)
    case define(String, StateExpr, ActionExpr)
    case and(ActionExpr, ActionExpr)
    case or(ActionExpr, ActionExpr)

}

extension NamedAction {
    func completingFrame(variables: [NamedVar], preservingOuterDomain: Bool = true) throws -> NamedAction {
        var displaced = displacedAssignmentTargets
        func complete(_ action: ActionExpr) throws -> ActionExpr {
            try ActionNormalization.checkedComplete(action, variables: variables,
                at: "actions.\(name).normalization") { previous, fresh in
                if let target = displaced[previous] { displaced[fresh] = target }
            }
        }
        let completed: ActionExpr
        if preservingOuterDomain, case .existsAction(let binder, let domain, let member) = body {
            completed = try .existsAction(binder, domain, complete(member))
        } else {
            completed = try complete(body)
        }
        // These receipts describe the nullary alternative visitor only.
        if !displaced.isEmpty {
            var choice = completed
            while case .define(_, _, let body) = choice { choice = body }
            if case .or = choice {
                // Normalization can drop a statically blocked remainder containing these bindings.
                let retainedNames = completed.scopeNames
                displaced = displaced.filter { retainedNames.contains($0.key) }
            } else {
                displaced = [:]
            }
        }
        return NamedAction(name: name, body: completed, bindings: bindings, isTermination: isTermination,
            displacedAssignmentTargets: displaced)
    }

    package func substitutingVariables(_ replacements: [String: StateExpr]) -> NamedAction {
        guard sourceIssue == nil, !replacements.isEmpty else { return self }
        let scoped = bindings.reversed().reduce(body) { body, binding in
            .existsAction(binding.name, binding.domain, body)
        }
        var displaced = displacedAssignmentTargets
        var substituted: ActionExpr
        if displaced.isEmpty {
            substituted = scoped.substitutingVariables(replacements)
        } else {
            substituted = scoped.substitutingVariables(replacements, avoidingBinders: scoped.scopeNames) { previous, fresh in
                if let target = displaced[previous] { displaced[fresh] = target }
            }
        }
        let bindings = bindings.map { binding -> ActionBinding in
            guard case .existsAction(let name, let domain, let body) = substituted else {
                preconditionFailure("Substitution must preserve action binding scopes")
            }
            substituted = body
            return ActionBinding(name: name, domain: domain, generatedSwiftType: binding.generatedSwiftType)
        }
        return NamedAction(name: name, body: substituted, bindings: bindings, isTermination: isTermination,
            displacedAssignmentTargets: displaced)
    }
}

extension ActionExpr {
    package func substitutingVariable(_ name: String, with replacement: StateExpr) -> ActionExpr {
        substitutingVariables([name: replacement])
    }

    package func substitutingVariables(_ replacements: [String: StateExpr]) -> ActionExpr {
        substitutingVariables(replacements, avoidingBinders: []) { _, _ in }
    }

    fileprivate func substitutingVariables(_ replacements: [String: StateExpr], avoidingBinders: Set<String>,
                                           renamingDefinition: (String, String) -> Void) -> ActionExpr {
        guard !replacements.isEmpty else { return self }
        func state(_ expression: StateExpr) -> StateExpr {
            StateExpr.substituteVariables(replacements, in: expression)
        }
        func action(_ expression: ActionExpr) -> ActionExpr {
            expression.substitutingVariables(replacements, avoidingBinders: avoidingBinders,
                renamingDefinition: renamingDefinition)
        }
        func scope(_ binder: String, _ body: ActionExpr) -> (String, ActionExpr) {
            let scoped = replacements.filter { $0.key != binder }
            guard !scoped.isEmpty else { return (binder, body) }
            let freeVariables = Set(scoped.values.flatMap(\.freeVariableNames))
            guard freeVariables.contains(binder) else {
                return (binder, body.substitutingVariables(scoped, avoidingBinders: avoidingBinders,
                    renamingDefinition: renamingDefinition))
            }
            let fresh = StateExpr.freshBoundName(binder, avoiding: body.scopeNames
                .union(freeVariables).union(scoped.keys).union([binder]).union(avoidingBinders))
            let renamed = body.substitutingVariable(binder, with: .variable(fresh))
            return (fresh, renamed.substitutingVariables(scoped, avoidingBinders: avoidingBinders,
                renamingDefinition: renamingDefinition))
        }
        switch self {
        case .assign(let target, let value): return .assign(target, state(value))
        case .unchanged: return self
        case .guard_(let condition): return .guard_(state(condition))
        case .existsAction(let binder, let values, let body):
            let (name, body) = scope(binder, body)
            return .existsAction(name, state(values), body)
        case .define(let binder, let value, let body):
            let (name, body) = scope(binder, body)
            if name != binder { renamingDefinition(binder, name) }
            return .define(name, state(value), body)
        case .ifElse(let condition, let then, let otherwise): return .ifElse(state(condition), action(then), action(otherwise))
        case .and(let lhs, let rhs): return .and(action(lhs), action(rhs))
        case .or(let lhs, let rhs): return .or(action(lhs), action(rhs))
        }
    }

    var scopeNames: Set<String> {
        var pending = [self]
        var names: Set<String> = []
        while let action = pending.popLast() {
            switch action {
            case .assign(let target, let value):
                if case .named(let name) = target { names.insert(name) }
                names.formUnion(value.freeVariableNames)
            case .unchanged(let target):
                if case .named(let name) = target { names.insert(name) }
            case .guard_(let condition): names.formUnion(condition.freeVariableNames)
            case .existsAction(let binder, let value, let body), .define(let binder, let value, let body):
                names.formUnion(value.freeVariableNames)
                names.insert(binder)
                pending.append(body)
            case .ifElse(let condition, let then, let otherwise):
                names.formUnion(condition.freeVariableNames)
                pending.append(contentsOf: [then, otherwise])
            case .and(let lhs, let rhs), .or(let lhs, let rhs): pending.append(contentsOf: [lhs, rhs])
            }
        }
        return names
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

extension ActionExpr {
    @discardableResult
    public static func && (lhs: some TypedExpression<Bool>, rhs: ActionExpr) -> ActionExpr {
        .and(.guard_(lhs.stateExpr), rhs)
    }

    @discardableResult
    public static func && (lhs: ActionExpr, rhs: some TypedExpression<Bool>) -> ActionExpr {
        .and(lhs, .guard_(rhs.stateExpr))
    }

    @discardableResult
    public static func || (lhs: some TypedExpression<Bool>, rhs: ActionExpr) -> ActionExpr {
        .or(.guard_(lhs.stateExpr), rhs)
    }

    @discardableResult
    public static func || (lhs: ActionExpr, rhs: some TypedExpression<Bool>) -> ActionExpr {
        .or(lhs, .guard_(rhs.stateExpr))
    }
}

package func renameVar(_ from: String, to: String, in action: ActionExpr) -> ActionExpr {
    func r(_ s: StateExpr) -> StateExpr { renameVar(from, to: to, in: s) }
    func ra(_ a: ActionExpr) -> ActionExpr { renameVar(from, to: to, in: a) }
    switch action {
    case .assign(let target, let e): return .assign(rename(target), r(e))
    case .unchanged(let target): return .unchanged(rename(target))
    case .guard_(let e): return .guard_(r(e))
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
