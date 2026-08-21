enum ActionNormalization {
    static func complete(_ action: ActionExpr, variables: [String]) -> ActionExpr {
        let completed = branches(of: action).map { branch in
            let assigned = assignedVars(branch)
            let explicit = explicitUnchanged(branch)
            var completedBranch = branch
            for variable in variables where !assigned.contains(variable) && !explicit.contains(variable) {
                completedBranch = .and(completedBranch, .unchanged(variable))
            }
            return completedBranch
        }
        guard let first = completed.first else { return action }
        return completed.dropFirst().reduce(first) { .or($0, $1) }
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
