enum ActionNormalization {
    private enum CompletionTask {
        case visit([ActionExpr], Set<ActionTarget>)
        case prepend([ActionExpr])
        case disjoin
        case conditional(StateExpr)
        case existential(String, StateExpr)
        case definition(String, StateExpr)
    }

    static func complete(_ action: ActionExpr, variables: [NamedVar]) -> ActionExpr {
        let targets = variables.map(actionTarget(for:))
        var unavailable = action.scopeNames
        var tasks = [CompletionTask.visit([action], [])]
        var results: [ActionExpr] = []
        while let task = tasks.popLast() {
            switch task {
            case .visit(var pending, var defined):
                var prefix: [ActionExpr] = []
                var suspended = false
                traversal: while let node = pending.popLast() {
                    switch node {
                    case .and(let left, let right):
                        pending.append(right)
                        pending.append(left)
                    case .assign(let target, _), .unchanged(let target):
                        defined.insert(target)
                        prefix.append(node)
                    case .guard_:
                        prefix.append(node)
                        if case .guard_(.value(.bool(false))) = node {
                            results.append(combine(prefix, with: ActionExpr.and)!)
                            suspended = true
                            break traversal
                        }
                    case .or(let left, let right), .ifElse(_, let left, let right):
                        if !prefix.isEmpty { tasks.append(.prepend(prefix)) }
                        if case .ifElse(let condition, _, _) = node {
                            tasks.append(.conditional(condition))
                        } else {
                            tasks.append(.disjoin)
                        }
                        tasks.append(.visit(pending + [right], defined))
                        tasks.append(.visit(pending + [left], defined))
                        suspended = true
                        break traversal
                    case .existsAction(let binder, let domain, let body), .define(let binder, let domain, let body):
                        let fresh = pending.contains { $0.scopeNames.contains(binder) }
                            ? StateExpr.freshBoundName(binder, avoiding: unavailable) : binder
                        unavailable.insert(fresh)
                        let renamed = fresh == binder ? body
                            : body.substitutingVariable(binder, with: .variable(fresh))
                        if !prefix.isEmpty { tasks.append(.prepend(prefix)) }
                        if case .define = node {
                            tasks.append(.definition(fresh, domain))
                        } else {
                            tasks.append(.existential(fresh, domain))
                        }
                        tasks.append(.visit(pending + [renamed], defined))
                        suspended = true
                        break traversal
                    }
                }
                if !suspended {
                    let frames = targets.filter { !defined.contains($0) }.map(ActionExpr.unchanged)
                    results.append(combine(prefix + frames, with: ActionExpr.and)!)
                }
            case .prepend(let prefix):
                results.append(combine(prefix + [results.removeLast()], with: ActionExpr.and)!)
            case .disjoin:
                let right = results.removeLast()
                let left = results.removeLast()
                results.append(.or(left, right))
            case .conditional(let condition):
                let no = results.removeLast()
                let yes = results.removeLast()
                results.append(.ifElse(condition, yes, no))
            case .existential(let binder, let domain):
                results.append(.existsAction(binder, domain, results.removeLast()))
            case .definition(let binder, let value):
                results.append(.define(binder, value, results.removeLast()))
            }
        }
        return results[0]
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

    private enum BranchTask {
        case expression(ActionExpr)
        case concatenate
        case conjoin
        case wrapExistential(String, StateExpr)
        case wrapDefinition(String, StateExpr)
    }

    static func branches(of action: ActionExpr) -> [ActionExpr] {
        branches(of: normalized(action)) { condition in
            if case .value(.bool(false)) = condition { return [] }
            return [.guard_(condition)]
        }
    }

    /// Identity comparison supplies guard expansion; executable normalization
    /// retains each Boolean guard's short-circuit evaluation.
    static func branches(
        of action: ActionExpr,
        guardBranches: (StateExpr) -> [ActionExpr]
    ) -> [ActionExpr] {
        var tasks = [BranchTask.expression(action)]
        var branches: [[ActionExpr]] = []
        while let task = tasks.popLast() {
            switch task {
            case .expression(let expression):
                switch expression {
                case .or(let left, let right):
                    tasks.append(.concatenate)
                    tasks.append(.expression(right))
                    tasks.append(.expression(left))
                case .guard_(let condition):
                    branches.append(guardBranches(condition))
                case .and(let left, let right):
                    tasks.append(.conjoin)
                    tasks.append(.expression(right))
                    tasks.append(.expression(left))
                case .ifElse(let condition, let then, let otherwise):
                    tasks.append(.concatenate)
                    tasks.append(.expression(.and(.guard_(.not(condition)), otherwise)))
                    tasks.append(.expression(.and(.guard_(condition), then)))
                case .existsAction(let variable, let set, let body):
                    tasks.append(.wrapExistential(variable, set))
                    tasks.append(.expression(body))
                case .define(let variable, let value, let body):
                    tasks.append(.wrapDefinition(variable, value))
                    tasks.append(.expression(body))
                default:
                    branches.append([expression])
                }
            case .concatenate:
                let right = branches.removeLast()
                let left = branches.removeLast()
                branches.append(left + right)
            case .conjoin:
                let right = branches.removeLast()
                let left = branches.removeLast()
                branches.append(left.flatMap { leftBranch in
                    right.map { rightBranch in .and(leftBranch, rightBranch) }
                })
            case .wrapExistential(let variable, let set):
                branches.append(branches.removeLast().map { .existsAction(variable, set, $0) })
            case .wrapDefinition(let variable, let value):
                branches.append(branches.removeLast().map { .define(variable, value, $0) })
            }
        }
        return branches[0]
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
        case .assign, .unchanged, .guard_:
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
