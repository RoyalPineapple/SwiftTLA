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
        let disjuncts = distOr(action)
        return try disjuncts.flatMap { try processDisjunct($0, oldState: oldState, varNames: varNames) }
    }

    private static func processDisjunct(
        _ action: ActionExpr,
        oldState: [String: TLAValue],
        varNames: [String]
    ) throws -> [[String: TLAValue]] {
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

        let (assignments, guards) = try extractAssignments(action)
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
        let (assignments, guards) = try extractAssignments(action)
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

    /// Flattens OR at all levels by distributing AND over OR
    private static func distOr(_ action: ActionExpr) -> [ActionExpr] {
        switch action {
        case .or(let a, let b):
            return distOr(a) + distOr(b)
        case .and(let a, let b):
            let lhs = distOr(a)
            let rhs = distOr(b)
            return lhs.flatMap { l in rhs.map { r in .and(l, r) } }
        default:
            return [action]
        }
    }

    private static func extractChooseActions(_ action: ActionExpr) throws -> [(String, StateExpr)] {
        switch action {
        case .chooseAction(let v, let s): return [(v, s)]
        case .and(let a, let b):
            return try extractChooseActions(a) + extractChooseActions(b)
        case .or: return []
        case .assign, .unchanged, .guard_: return []
        }
    }

    private static func extractAssignments(_ action: ActionExpr) throws -> (assignments: [String: StateExpr], guards: [StateExpr]) {
        switch action {
        case .assign(let name, let expr):
            return ([name: expr], [])
        case .unchanged(let name):
            return ([name: .variable(name)], [])
        case .guard_(let expr):
            return ([:], [expr])
        case .chooseAction:
            return ([:], [])
        case .and(let a, let b):
            let (lhsAssign, lhsGuards) = try extractAssignments(a)
            let (rhsAssign, rhsGuards) = try extractAssignments(b)
            for key in rhsAssign.keys where lhsAssign[key] != nil {
                throw ActionError.multipleAssignment(key)
            }
            return (lhsAssign.merging(rhsAssign) { $1 }, lhsGuards + rhsGuards)
        case .or:
            return ([:], [])
        }
    }
}
