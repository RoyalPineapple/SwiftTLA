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
        let existsBindings = extractExistsActions(action)
        if !existsBindings.isEmpty {
            let (v, s, body) = existsBindings[0]
            guard case .set(let sv) = try Evaluator.evaluate(s, in: oldState) else {
                throw ActionError.invalidActionForm("\\E set must be a set")
            }
            var results: [[String: TLAValue]] = []
            for elem in sv {
                var rest = body
                rest = substituteVarInAction(v, elem, rest)
                let disjuncts = distOr(rest)
                let inner = try disjuncts.flatMap { try processDisjunct($0, oldState: oldState, varNames: varNames) }
                results.append(contentsOf: inner)
            }
            return results
        }

        let chooseAssignments = try extractChooseActions(action)
        if !chooseAssignments.isEmpty {
            var partials: [[String: TLAValue]] = [[:]]
            for (varName, setExpr) in chooseAssignments {
                var next: [[String: TLAValue]] = []
                for partial in partials {
                    let env = oldState.merging(partial) { _, new in new }
                    guard case .set(let sv) = try Evaluator.evaluate(setExpr, in: env) else {
                        throw ActionError.invalidActionForm("CHOOSE set for \(varName) must be a set")
                    }
                    for elem in sv {
                        var binding = partial
                        binding[varName] = elem
                        next.append(binding)
                    }
                }
                partials = next
            }

            let skip = Set(chooseAssignments.map(\.0))
            var results: [[String: TLAValue]] = []
            for partial in partials {
                let enriched = oldState.merging(partial) { _, new in new }
                guard let baseState = try applyNonChooseAssignments(
                    action, oldState: enriched, varNames: varNames, skip: skip
                ) else { continue }
                var finalState = baseState
                for (name, value) in partial {
                    finalState[name] = value
                }
                results.append(finalState)
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
        skip: Set<String>
    ) throws -> [String: TLAValue]? {
        let (assignments, guards) = try extractAssignments(action)
        guard try Evaluator.evaluateBool(
            guards.reduce(StateExpr.value(.bool(true))) { .and($0, $1) },
            in: oldState
        ) else { return nil }

        var newState = oldState
        for varName in varNames where !skip.contains(varName) {
            if let rhs = assignments[varName] {
                newState[varName] = try Evaluator.evaluate(rhs, in: oldState)
            }
        }
        return newState
    }

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
        case .assign, .unchanged, .guard_, .existsAction: return []
        }
    }

    private static func extractExistsActions(_ action: ActionExpr) -> [(String, StateExpr, ActionExpr)] {
        switch action {
        case .existsAction(let v, let s, let b): return [(v, s, b)]
        case .and(let a, let b): return extractExistsActions(a) + extractExistsActions(b)
        case .assign, .unchanged, .guard_, .chooseAction, .or: return []
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
        case .chooseAction, .existsAction:
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

    private static func substituteVarInAction(_ name: String, _ value: TLAValue, _ action: ActionExpr) -> ActionExpr {
        switch action {
        case .assign(let v, let e):
            return .assign(v, Evaluator.subExpr(e, name: name, value: value))
        case .unchanged(let v):
            return .unchanged(v)
        case .guard_(let e):
            return .guard_(Evaluator.subExpr(e, name: name, value: value))
        case .chooseAction(let v, let s):
            return .chooseAction(v, Evaluator.subExpr(s, name: name, value: value))
        case .existsAction(let v, let s, let b):
            return .existsAction(v, Evaluator.subExpr(s, name: name, value: value), substituteVarInAction(name, value, b))
        case .and(let a, let b):
            return .and(substituteVarInAction(name, value, a), substituteVarInAction(name, value, b))
        case .or(let a, let b):
            return .or(substituteVarInAction(name, value, a), substituteVarInAction(name, value, b))
        }
    }
}
