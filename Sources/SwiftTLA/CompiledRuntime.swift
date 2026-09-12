struct CompiledRuntime {
    let identity: CompilationIdentity
    let layout: CompiledLayout
    let behavior: CompiledBehavior
    private let operators: CompiledOperators
    private let functions: [ResolvedFunction]

    init(compilation: CompiledSpecification) {
        identity = compilation.identity
        layout = compilation.layout
        behavior = compilation.semantics.behavior
        operators = compilation.semantics.operators
        functions = []
    }

    init(program: CompiledProgram) {
        identity = program.identity
        layout = program.layout
        behavior = program.behavior
        operators = .init()
        functions = program.functions
    }

    func initialStates() throws -> [CompiledState] {
        var assignments: [[VariableID: CompiledValue]] = [[:]]
        for (variable, initialization) in behavior.initializations {
            switch initialization {
            case .value(let expression):
                assignments = try assignments.map { values in
                    var values = values
                    values[variable] = try CompiledEvaluator(
                        variableValues: values,
                        operators: operators, functions: functions
                    ).evaluate(expression)
                    return values
                }
            case .memberOf(let set):
                assignments = try assignments.flatMap { values in
                    let value = try CompiledEvaluator(
                        variableValues: values,
                        operators: operators, functions: functions
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
            }, layout: layout, identity: identity)
        }
    }

    func successors(from state: CompiledState) throws -> [CompiledSuccessor] {
        try state.requireIdentity(identity)
        let enabledActions = try enabledActions(in: state)
        return try behavior.actions.flatMap { action in
            try successors(for: action.id, from: state, enabledActions: enabledActions)
        }
    }

    func successors(for actionID: ActionID, from state: CompiledState) throws -> [CompiledSuccessor] {
        try state.requireIdentity(identity)
        guard let action = behavior.actions.first(where: { $0.id == actionID }) else {
            throw CompiledEvaluationError.unresolvedOperator
        }
        return try successors(for: actionID, from: state,
            enabledActions: enabledActions(in: state, required: behavior.enabledActionDependencies[action.id] ?? []))
    }

    private func successors(
        for actionID: ActionID,
        from state: CompiledState,
        enabledActions: Set<ActionID>
    ) throws -> [CompiledSuccessor] {
        guard let action = behavior.actions.first(where: { $0.id == actionID }) else {
            throw CompiledEvaluationError.unresolvedOperator
        }
        return try actionEnumerator(in: state, enabledActions: enabledActions)
            .enumerateSuccessors(action)
            .filter { successor in try constraintHolds(in: successor.state) }
    }

    func assumeHolds(in state: CompiledState) throws -> Bool {
        try state.requireIdentity(identity)
        guard let assume = behavior.assume else { return true }
        return try boolean(assume, in: state)
    }

    func invariantHolds(_ invariant: CompiledInvariant, in state: CompiledState) throws -> Bool {
        try state.requireIdentity(identity)
        return try boolean(invariant.predicate, in: state)
    }

    func predicateHolds(_ predicate: CompiledStateQuery, in state: CompiledState) throws -> Bool {
        try state.requireIdentity(identity)
        return try boolean(predicate, in: state)
    }

    func evaluate(_ queries: [CompiledStateQuery], in state: CompiledState) throws -> [CompiledValue] {
        try state.requireIdentity(identity)
        let evaluator = CompiledEvaluator(
            state: state,
            operators: operators, functions: functions,
            enabledActions: try enabledActions(in: state, required: queries.reduce(into: Set<ActionID>()) {
                $0.formUnion($1.enabledActions)
            })
        )
        return try queries.map { try evaluator.evaluate($0.expression) }
    }

    private func constraintHolds(in state: CompiledState) throws -> Bool {
        guard let constraint = behavior.constraint else { return true }
        return try boolean(constraint, in: state)
    }

    private func enabledActions(in state: CompiledState, required: Set<ActionID>? = nil) throws -> Set<ActionID> {
        var enabled = Set<ActionID>()
        for index in behavior.enabledActionIndices {
            let action = behavior.actions[index]
            if let required, !required.contains(action.id) { continue }
            if try actionEnumerator(in: state, enabledActions: enabled).enumerate(action).isEmpty == false {
                enabled.insert(action.id)
            }
        }
        return enabled
    }

    private func actionEnumerator(
        in state: CompiledState, enabledActions: Set<ActionID>
    ) -> CompiledActionEnumerator {
        .init(state: state) { expression, bindings in
            try CompiledEvaluator(state: state, operators: operators, functions: functions,
                bindings: bindings, enabledActions: enabledActions).evaluate(expression)
        }
    }

    private func boolean(
        _ predicate: CompiledStateQuery,
        in state: CompiledState
    ) throws -> Bool {
        let value = try CompiledEvaluator(
            state: state,
            operators: operators, functions: functions,
            enabledActions: try enabledActions(in: state, required: predicate.enabledActions)
        ).evaluate(predicate.expression)
        guard case .boolean(let boolean) = value else {
            throw EvalError.expected(.boolean, actual: [value])
        }
        return boolean
    }
}

struct CompiledSuccessor: Sendable {
    let action: ActionID
    let arguments: [CompiledValue]
    let state: CompiledState
}
