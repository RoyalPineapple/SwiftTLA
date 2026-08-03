public enum ActionError: Error, CustomStringConvertible {
    case multipleAssignment(String)
    case invalidActionForm(String)

    public var description: String {
        switch self {
        case .multipleAssignment(let v): return "Variable '\(v)' is assigned multiple times in one action branch"
        case .invalidActionForm(let m): return "Invalid action form: \(m)"
        }
    }
}

public enum ActionEnumerator {
    public static func enumerate(
        _ action: ActionExpr,
        from oldState: [String: TLAValue],
        varNames: [String]
    ) throws -> [[String: TLAValue]] {
        return try splitOr(action).compactMap { disjunct in
            try processDisjunct(disjunct, oldState: oldState, varNames: varNames)
        }
    }

    private static func processDisjunct(
        _ action: ActionExpr,
        oldState: [String: TLAValue],
        varNames: [String]
    ) throws -> [String: TLAValue]? {
        let (assignments, guards) = try extractAssignments(action)

        guard try Evaluator.evaluateBool(
            guards.reduce(StateExpr.value(.bool(true))) { .and($0, $1) },
            in: oldState
        ) else { return nil }

        var newState = oldState
        for varName in varNames {
            if let rhs = assignments[varName] {
                newState[varName] = try Evaluator.evaluate(rhs, in: oldState)
            }
        }
        return newState
    }

    private static func extractAssignments(_ action: ActionExpr) throws -> (assignments: [String: StateExpr], guards: [StateExpr]) {
        switch action {
        case .assign(let name, let expr):
            return ([name: expr], [])
        case .unchanged(let name):
            return ([name: .variable(name)], [])
        case .guard_(let expr):
            return ([:], [expr])
        case .and(let a, let b):
            let (lhsAssign, lhsGuards) = try extractAssignments(a)
            let (rhsAssign, rhsGuards) = try extractAssignments(b)
            for key in rhsAssign.keys where lhsAssign[key] != nil {
                throw ActionError.multipleAssignment(key)
            }
            return (lhsAssign.merging(rhsAssign) { $1 }, lhsGuards + rhsGuards)
        case .or:
            throw ActionError.invalidActionForm("OR must be at the top level of an action, not nested inside AND")
        }
    }

    private static func splitOr(_ action: ActionExpr) -> [ActionExpr] {
        if case .or(let a, let b) = action {
            return splitOr(a) + splitOr(b)
        }
        return [action]
    }
}
