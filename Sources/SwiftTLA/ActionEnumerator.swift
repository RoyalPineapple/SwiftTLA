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
        let disjuncts = distributeOr(action)
        return try disjuncts.flatMap { try processDisjunct($0, oldState: oldState, varNames: varNames) }
    }

    private static func processDisjunct(
        _ action: ActionExpr,
        oldState: [String: TLAValue],
        varNames: [String]
    ) throws -> [[String: TLAValue]] {
        // Handle LET bindings: evaluate value, substitute into body
        if case .define(let name, let valueExpr, let body) = action {
            let val = try valueExpr.evaluate(in: oldState)
            let substituted = substituteVarInAction(name, val, body)
            let disjuncts = distributeOr(substituted)
            return try disjuncts.flatMap { try processDisjunct($0, oldState: oldState, varNames: varNames) }
        }

        if let expanded = try expandFirstExistsAction(in: action, oldState: oldState) {
            return try expanded.flatMap { try processDisjunct($0, oldState: oldState, varNames: varNames) }
        }

        let chooseAssignments = try extractChooseActions(action)
        if !chooseAssignments.isEmpty {
            var partials: [[String: TLAValue]] = [[:]]
            for (varName, setExpr) in chooseAssignments {
                var next: [[String: TLAValue]] = []
                for partial in partials {
                    let env = oldState.merging(partial) { _, new in new }
                    guard case .set(let sv) = try setExpr.evaluate(in: env) else {
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
        let guardExpr = guards.reduce(StateExpr.value(.bool(true))) { .and($0, $1) }
        guard try guardExpr.evaluateBool(in: oldState) else { return [] }

        var newState = oldState
        for varName in varNames {
            if let rhs = assignments[varName] {
                newState[varName] = try rhs.evaluate(in: oldState)
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
        let guardExpr = guards.reduce(StateExpr.value(.bool(true))) { .and($0, $1) }
        guard try guardExpr.evaluateBool(in: oldState) else { return nil }

        var newState = oldState
        for varName in varNames where !skip.contains(varName) {
            if let rhs = assignments[varName] {
                newState[varName] = try rhs.evaluate(in: oldState)
            }
        }
        return newState
    }

    private static func extractChooseActions(_ action: ActionExpr) throws -> [(String, StateExpr)] {
        switch action {
        case .chooseAction(let v, let s): return [(v, s)]
        case .and(let a, let b):
            return try extractChooseActions(a) + extractChooseActions(b)
        case .or, .ifElse, .define, .assign, .unchanged, .guard_, .existsAction: return []
        }
    }

    private static func extractExistsActions(_ action: ActionExpr) -> [(String, StateExpr, ActionExpr)] {
        switch action {
        case .existsAction(let v, let s, let b): return [(v, s, b)]
        case .and(let a, let b): return extractExistsActions(a) + extractExistsActions(b)
        case .assign, .unchanged, .guard_, .chooseAction, .or, .ifElse, .define: return []
        }
    }

    /// Expands one existential binder while retaining every surrounding action
    /// clause. A `With` can appear between guards and assignments; enumerating
    /// only its body would change the transition relation.
    private static func expandFirstExistsAction(
        in action: ActionExpr,
        oldState: [String: TLAValue]
    ) throws -> [ActionExpr]? {
        switch action {
        case .existsAction(let name, let set, let body):
            guard case .set(let values) = try set.evaluate(in: oldState) else {
                throw ActionError.invalidActionForm("\\E set must be a set")
            }
            return values.map { substituteVarInAction(name, $0, body) }
        case .and(let lhs, let rhs):
            if let expanded = try expandFirstExistsAction(in: lhs, oldState: oldState) {
                return expanded.map { .and($0, rhs) }
            }
            return try expandFirstExistsAction(in: rhs, oldState: oldState).map { expanded in
                expanded.map { .and(lhs, $0) }
            }
        case .or(let lhs, let rhs):
            if let expanded = try expandFirstExistsAction(in: lhs, oldState: oldState) {
                return expanded.map { .or($0, rhs) }
            }
            return try expandFirstExistsAction(in: rhs, oldState: oldState).map { expanded in
                expanded.map { .or(lhs, $0) }
            }
        case .ifElse(let condition, let then, let otherwise):
            if let expanded = try expandFirstExistsAction(in: then, oldState: oldState) {
                return expanded.map { .ifElse(condition, $0, otherwise) }
            }
            return try expandFirstExistsAction(in: otherwise, oldState: oldState).map { expanded in
                expanded.map { .ifElse(condition, then, $0) }
            }
        case .assign, .unchanged, .guard_, .chooseAction, .define:
            return nil
        }
    }

    public static func extractAssignments(_ action: ActionExpr) throws -> (assignments: [String: StateExpr], guards: [StateExpr]) {
        switch action {
        case .assign(let name, let expr):
            return ([name: expr], [])
        case .unchanged(let name):
            return ([name: .variable(name)], [])
        case .guard_(let expr):
            return ([:], [expr])
        case .chooseAction, .existsAction, .ifElse, .define:
            return ([:], [])
        case .and(let a, let b):
            let (lhsAssign, lhsGuards) = try extractAssignments(a)
            let (rhsAssign, rhsGuards) = try extractAssignments(b)
            for (key, rhsValue) in rhsAssign {
                if let lhsValue = lhsAssign[key], lhsValue != rhsValue {
                    throw ActionError.multipleAssignment(key)
                }
            }
            return (lhsAssign.merging(rhsAssign) { lhs, _ in lhs }, lhsGuards + rhsGuards)
        case .or:
            return ([:], [])
        }
    }

    private static func substituteVarInAction(_ name: String, _ value: TLAValue, _ action: ActionExpr) -> ActionExpr {
        substituteVar(name, with: value, in: action)
    }
}
