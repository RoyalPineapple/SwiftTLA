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
        let disjuncts = splitOr(action)
        return try disjuncts.flatMap { try processDisjunct($0, oldState: oldState, varNames: varNames) }
    }

    private static func processDisjunct(
        _ action: ActionExpr,
        oldState: [String: TLAValue],
        varNames: [String]
    ) throws -> [[String: TLAValue]] {
        // Check for CHOOSE — enumerate all choices
        let chooseAssignments = try extractChooseActions(action)

        if !chooseAssignments.isEmpty {
            var results: [[String: TLAValue]] = []
            for (varName, setExpr) in chooseAssignments {
                guard case .set(let sv) = try Evaluator.evaluate(setExpr, in: oldState) else {
                    throw ActionError.invalidActionForm("CHOOSE set for \(varName) must be a set")
                }
                let baseState = try applyNonChooseAssignments(action, oldState: oldState, varNames: varNames, skip: varName)
                if baseState == nil { continue }
                for elem in sv {
                    var s = baseState!
                    s[varName] = elem
                    results.append(s)
                }
            }
            return results
        }

        let (assignments, guards) = try extractAssignments(action, isTopLevel: true)
        guard try Evaluator.evaluateBool(
            guards.reduce(StateExpr.value(.bool(true))) { .and($0, $1) },
            in: oldState
        ) else { return [] }

        var newState = oldState
        for varName in varNames {
            if let rhs = assignments[varName] {
                newState[varName] = try Evaluator.evaluate(rhs, in: oldState)
            }
        }
        return [newState]
    }

    private static func applyNonChooseAssignments(
        _ action: ActionExpr,
        oldState: [String: TLAValue],
        varNames: [String],
        skip: String
    ) throws -> [String: TLAValue]? {
        let (assignments, guards) = try extractAssignments(action, isTopLevel: false)
        guard try Evaluator.evaluateBool(
            guards.reduce(StateExpr.value(.bool(true))) { .and($0, $1) },
            in: oldState
        ) else { return nil }

        var newState = oldState
        for varName in varNames where varName != skip {
            if let rhs = assignments[varName] {
                newState[varName] = try Evaluator.evaluate(rhs, in: oldState)
            }
        }
        return newState
    }

    private static func extractChooseActions(_ action: ActionExpr) throws -> [(String, StateExpr)] {
        switch action {
        case .chooseAction(let v, let s): return [(v, s)]
        case .and(let a, let b):
            let lhs = try extractChooseActions(a)
            let rhs = try extractChooseActions(b)
            return lhs + rhs
        case .assign, .unchanged, .guard_: return []
        case .or: throw ActionError.invalidActionForm("CHOOSE must not be inside OR")
        }
    }

    private static func extractAssignments(_ action: ActionExpr, isTopLevel: Bool) throws -> (assignments: [String: StateExpr], guards: [StateExpr]) {
        switch action {
        case .assign(let name, let expr):
            return ([name: expr], [])
        case .unchanged(let name):
            return ([name: .variable(name)], [])
        case .guard_(let expr):
            return ([:], [expr])
        case .chooseAction:
            if isTopLevel { return ([:], []) }
            return ([:], [.value(.bool(true))])
        case .and(let a, let b):
            let (lhsAssign, lhsGuards) = try extractAssignments(a, isTopLevel: isTopLevel)
            let (rhsAssign, rhsGuards) = try extractAssignments(b, isTopLevel: isTopLevel)
            for key in rhsAssign.keys where lhsAssign[key] != nil {
                throw ActionError.multipleAssignment(key)
            }
            return (lhsAssign.merging(rhsAssign) { $1 }, lhsGuards + rhsGuards)
        case .or:
            if isTopLevel { return ([:], []) }
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
