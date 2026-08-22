enum ActionNormalization {
    static func complete(_ action: ActionExpr, variables: [NamedVar]) -> ActionExpr {
        let targets = variables.map(actionTarget(for:))
        let completed = branches(of: action).map { branch in
            let assigned = assignedVars(branch)
            let explicit = explicitUnchanged(branch)
            var completedBranch = branch
            for target in targets where !assigned.contains(target) && !explicit.contains(target) {
                completedBranch = .and(completedBranch, .unchanged(target))
            }
            return completedBranch
        }
        guard let first = completed.first else { return action }
        return completed.dropFirst().reduce(first) { .or($0, $1) }
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
        switch action {
        case .or(let left, let right):
            return branches(of: left) + branches(of: right)
        case .and(let left, let right):
            let leftBranches = branches(of: left)
            let rightBranches = branches(of: right)
            return leftBranches.flatMap { left in rightBranches.map { right in .and(left, right) } }
        case .ifElse(let condition, let thenBranch, let elseBranch):
            return branches(of: .and(.guard_(condition), thenBranch))
                + branches(of: .and(.guard_(StateExpr.not(condition)), elseBranch))
        case .define(let variable, let value, let body):
            return branches(of: body).map { .define(variable, value, $0) }
        case .existsAction(let variable, let set, let body):
            return branches(of: body).map { .existsAction(variable, set, $0) }
        default:
            return [action]
        }
    }
}
