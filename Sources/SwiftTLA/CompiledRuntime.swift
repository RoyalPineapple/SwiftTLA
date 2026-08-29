struct CompiledRuntime {
    let compilation: CompiledSpecification

    private var layout: CompiledLayout { compilation.layout }
    private var semantics: CompiledSemantics { compilation.semantics }

    func initialStates() throws -> [CompiledState] {
        var assignments: [[VariableID: CompiledValue]] = [[:]]
        for (variable, initialization) in semantics.variableInitializations {
            switch initialization {
            case .value(let value):
                assignments = assignments.map { values in
                    var values = values
                    values[variable] = value
                    return values
                }
            case .expression(let expression):
                assignments = try assignments.map { values in
                    var values = values
                    values[variable] = try CompiledEvaluator(
                        variableValues: values,
                        semantics: semantics,
                        layout: layout
                    ).evaluate(expression)
                    return values
                }
            case .memberOf(let set):
                assignments = try assignments.flatMap { values in
                    let value = try CompiledEvaluator(
                        variableValues: values,
                        semantics: semantics,
                        layout: layout
                    ).evaluate(set)
                    guard case .set(let members) = value else {
                        throw EvalError.expected(.set, actual: [value])
                    }
                    return CompiledValue.sorted(members).map { member in
                        var values = values
                        values[variable] = member
                        return values
                    }
                }
            }
        }
        return try assignments.map { values in
            try CompiledState(values: layout.variables.map { variable in
                guard let value = values[variable.id] else {
                    throw CompiledEvaluationError.uninitializedVariable(variable.id)
                }
                return value
            }, compilation: compilation)
        }
    }

    func successors(from state: CompiledState) throws -> [CompiledSuccessor] {
        try state.requireIdentity(compilation.identity)
        let enabledActions = try enabledActions(in: state)
        return try semantics.actions.flatMap { action in
            try successors(for: action.id, from: state, enabledActions: enabledActions)
        }
    }

    func successors(for actionID: ActionID, from state: CompiledState) throws -> [CompiledSuccessor] {
        try state.requireIdentity(compilation.identity)
        return try successors(for: actionID, from: state, enabledActions: try enabledActions(in: state))
    }

    private func successors(
        for actionID: ActionID,
        from state: CompiledState,
        enabledActions: Set<ActionID>
    ) throws -> [CompiledSuccessor] {
        guard let action = semantics.actions.first(where: { $0.id == actionID }) else {
            throw CompiledEvaluationError.unresolvedOperator
        }
        return try CompiledActionEnumerator(state: state, semantics: semantics, layout: layout, enabledActions: enabledActions)
            .enumerateSuccessors(action)
            .filter { successor in try constraintHolds(in: successor.state) }
    }

    func assumeHolds(in state: CompiledState) throws -> Bool {
        try state.requireIdentity(compilation.identity)
        guard let assume = semantics.assume else { return true }
        return try boolean(assume, in: state)
    }

    func invariantHolds(_ invariant: CompiledInvariant, in state: CompiledState) throws -> Bool {
        try state.requireIdentity(compilation.identity)
        return try boolean(invariant.body, in: state, enabledActions: try enabledActions(in: state))
    }

    func predicateHolds(_ predicate: CompiledStateExpr, in state: CompiledState) throws -> Bool {
        try state.requireIdentity(compilation.identity)
        return try boolean(predicate, in: state, enabledActions: try enabledActions(in: state))
    }

    func evaluate(_ expressions: [CompiledStateExpr], in state: CompiledState) throws -> [CompiledValue] {
        try state.requireIdentity(compilation.identity)
        let evaluator = CompiledEvaluator(
            state: state,
            semantics: semantics,
            layout: layout,
            enabledActions: try enabledActions(in: state)
        )
        return try expressions.map(evaluator.evaluate)
    }

    private func constraintHolds(in state: CompiledState) throws -> Bool {
        guard let constraint = semantics.constraint else { return true }
        return try boolean(constraint, in: state)
    }

    private func enabledActions(in state: CompiledState) throws -> Set<ActionID> {
        var result = Set<ActionID>()
        for action in semantics.actions {
            if try CompiledActionEnumerator(state: state, semantics: semantics, layout: layout).enumerate(action).isEmpty == false {
                result.insert(action.id)
            }
        }
        return result
    }

    private func boolean(
        _ expression: CompiledStateExpr,
        in state: CompiledState,
        enabledActions: Set<ActionID> = []
    ) throws -> Bool {
        let value = try CompiledEvaluator(
            state: state,
            semantics: semantics,
            layout: layout,
            enabledActions: enabledActions
        ).evaluate(expression)
        guard case .boolean(let result) = value else {
            throw EvalError.expected(.boolean, actual: [value])
        }
        return result
    }
}

struct CompiledSuccessor: Sendable {
    let action: ActionID
    let arguments: [CompiledValue]
    let state: CompiledState
}
