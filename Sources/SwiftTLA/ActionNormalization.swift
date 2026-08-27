enum ActionNormalization {
    static func complete(_ action: ActionExpr, variables: [NamedVar]) -> ActionExpr {
        let targets = variables.map(actionTarget(for:))
        let completed = branches(of: action).map { branch in
            let assigned = assignedVars(branch)
            let explicit = explicitUnchanged(branch)
            var terms = conjunctionTerms(in: branch)
            for target in targets where !assigned.contains(target) && !explicit.contains(target) {
                terms.append(.unchanged(target))
            }
            return combine(terms, with: ActionExpr.and) ?? branch
        }
        return combine(completed, with: ActionExpr.or) ?? action
    }

    private static func actionTarget(for variable: NamedVar) -> ActionTarget {
        switch variable.origin {
        case .programCounter:
            .programCounter
        case .procedureStack:
            .procedureStack
        case .source, .compiler:
            .named(variable.name)
        }
    }

    static func branches(of action: ActionExpr) -> [ActionExpr] {
        normalizedBranches(of: normalized(action))
    }

    private static func normalizedBranches(of action: ActionExpr) -> [ActionExpr] {
        switch action {
        case .or(let left, let right):
            return normalizedBranches(of: left) + normalizedBranches(of: right)
        case .and(let left, let right):
            let leftBranches = normalizedBranches(of: left)
            let rightBranches = normalizedBranches(of: right)
            return leftBranches.flatMap { left in rightBranches.map { right in .and(left, right) } }
        case .ifElse(let condition, let thenBranch, let elseBranch):
            return normalizedBranches(of: normalized(.and(.guard_(condition), thenBranch)))
                + normalizedBranches(of: normalized(.and(.guard_(StateExpr.not(condition)), elseBranch)))
        case .define(let variable, let value, let body):
            return normalizedBranches(of: body).map { .define(variable, value, $0) }
        case .existsAction(let variable, let set, let body):
            return normalizedBranches(of: body).map { .existsAction(variable, set, $0) }
        default:
            return [action]
        }
    }

    private static func normalized(_ action: ActionExpr) -> ActionExpr {
        switch action {
        case .and:
            let terms = conjunctionTerms(in: action).map(normalized)
            return combine(terms, with: ActionExpr.and) ?? action
        case .or:
            let terms = disjunctionTerms(in: action).map(normalized)
            return combine(terms, with: ActionExpr.or) ?? action
        case .existsAction(let binder, let set, let body):
            return .existsAction(binder, set, normalized(body))
        case .define(let binder, let value, let body):
            return .define(binder, value, normalized(body))
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(condition, normalized(then), normalized(otherwise))
        case .assign, .unchanged, .guard_, .chooseAction:
            return action
        }
    }

    private static func conjunctionTerms(in action: ActionExpr) -> [ActionExpr] {
        var pending = [action]
        var terms: [ActionExpr] = []
        while let next = pending.popLast() {
            if case .and(let left, let right) = next {
                pending.append(right)
                pending.append(left)
            } else {
                terms.append(next)
            }
        }
        return terms
    }

    private static func disjunctionTerms(in action: ActionExpr) -> [ActionExpr] {
        var pending = [action]
        var terms: [ActionExpr] = []
        while let next = pending.popLast() {
            if case .or(let left, let right) = next {
                pending.append(right)
                pending.append(left)
            } else {
                terms.append(next)
            }
        }
        return terms
    }

    private static func combine(
        _ actions: [ActionExpr],
        with operation: (ActionExpr, ActionExpr) -> ActionExpr
    ) -> ActionExpr? {
        var level = actions
        while level.count > 1 {
            var next: [ActionExpr] = []
            next.reserveCapacity((level.count + 1) / 2)
            var index = 0
            while index < level.count {
                if level.indices.contains(index + 1) {
                    next.append(operation(level[index], level[index + 1]))
                } else {
                    next.append(level[index])
                }
                index += 2
            }
            level = next
        }
        return level.first
    }
}
