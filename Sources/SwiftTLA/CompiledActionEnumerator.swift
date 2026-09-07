struct CompiledActionEnumerator {
    let state: CompiledState
    let semantics: CompiledSemantics
    let layout: CompiledLayout
    let enabledActions: Set<ActionID>

    init(
        state: CompiledState,
        semantics: CompiledSemantics,
        layout: CompiledLayout,
        enabledActions: Set<ActionID> = []
    ) {
        self.state = state
        self.semantics = semantics
        self.layout = layout
        self.enabledActions = enabledActions
    }

    func enumerate(_ action: CompiledAction) throws -> [CompiledState] {
        try enumerateSuccessors(action).map(\.state)
    }

    func enumerateSuccessors(_ action: CompiledAction) throws -> [CompiledSuccessor] {
        try actionBindings(action.bindings).flatMap { binding in
            try plans(for: action.body, extending: .init(), bindings: binding.values).map { plan in
                var assignments = plan.choices
                for (variable, value) in plan.assignments {
                    if let previous = assignments[variable], previous != value {
                        throw CompiledEvaluationError.conflictingAssignment(variable)
                    }
                    assignments[variable] = value
                }
                return CompiledSuccessor(
                    action: action.id,
                    arguments: binding.arguments,
                    state: try state.updating(assignments)
                )
            }
        }
    }

    private func plans(
        for action: CompiledActionExpr,
        extending plan: CompiledActionPlan,
        bindings: CompiledBindings
    ) throws -> [CompiledActionPlan] {
        let evaluator = try self.evaluator(state: state.updating(plan.choices), bindings: bindings)
        switch action {
        case .assign(let variable, let expression):
            let value = try evaluator.evaluate(expression)
            if let previous = plan.assignments[variable], previous != value {
                throw CompiledEvaluationError.conflictingAssignment(variable)
            }
            var assigned = plan
            assigned.assignments[variable] = value
            return [assigned]
        case .unchanged:
            return [plan]
        case .guard_(let expression):
            let value = try evaluator.evaluate(expression)
            guard case .boolean(let enabled) = value else {
                throw EvalError.expected(.boolean, actual: [value])
            }
            return enabled ? [plan] : []
        case .chooseAction(let variable, let set):
            let domain = try evaluator.evaluate(set)
            guard case .set(let values) = domain else {
                throw EvalError.expected(.set, actual: [domain])
            }
            if let selected = plan.choices[variable] {
                return values.contains(selected) ? [plan] : []
            }
            return CompiledValue.sorted(values).map { value in
                var selected = plan
                selected.choices[variable] = value
                return selected
            }
        case .existsAction(let binder, let set, let body):
            let domain = try evaluator.evaluate(set)
            guard case .set(let values) = domain else {
                throw EvalError.expected(.set, actual: [domain])
            }
            return try CompiledValue.sorted(values).flatMap { value in
                try plans(for: body, extending: plan, bindings: bindings.binding(value, to: binder))
            }
        case .define(let binder, let value, let body):
            return try plans(
                for: body,
                extending: plan,
                bindings: bindings.binding(try evaluator.evaluate(value), to: binder)
            )
        case .ifElse(let condition, let then, let otherwise):
            let value = try evaluator.evaluate(condition)
            guard case .boolean(let conditionHolds) = value else {
                throw EvalError.expected(.boolean, actual: [value])
            }
            return try plans(
                for: conditionHolds ? then : otherwise,
                extending: plan,
                bindings: bindings
            )
        case .and:
            // Choice slots are visible throughout their conjunction, including
            // in expressions that precede the choice in the source action.
            let terms = conjuncts(in: action)
            let choices = terms.filter { if case .chooseAction = $0 { return true }; return false }
            let remaining = terms.filter { if case .chooseAction = $0 { return false }; return true }
            return try (choices + remaining).reduce([plan]) { partial, term in
                try partial.flatMap { try plans(for: term, extending: $0, bindings: bindings) }
            }
        case .or(let lhs, let rhs):
            return try plans(for: lhs, extending: plan, bindings: bindings)
                + plans(for: rhs, extending: plan, bindings: bindings)
        }
    }

    private func conjuncts(in action: CompiledActionExpr) -> [CompiledActionExpr] {
        if case .and(let lhs, let rhs) = action {
            return conjuncts(in: lhs) + conjuncts(in: rhs)
        }
        return [action]
    }

    private func evaluator(state: CompiledState, bindings: CompiledBindings) -> CompiledEvaluator {
        CompiledEvaluator(
            state: state,
            semantics: semantics,
            layout: layout,
            bindings: bindings,
            enabledActions: enabledActions
        )
    }

    private func actionBindings(_ bindings: [CompiledActionBinding]) -> [CompiledActionBindingValues] {
        bindings.reduce([.init(values: .init(), arguments: [])]) { partial, binding in
            partial.flatMap { current in
                binding.values.map { value in
                    .init(
                        values: current.values.binding(value, to: binding.binder),
                        arguments: current.arguments + [value]
                    )
                }
            }
        }
    }
}

private struct CompiledActionBindingValues {
    let values: CompiledBindings
    let arguments: [CompiledValue]
}

private struct CompiledActionPlan {
    var choices: [VariableID: CompiledValue] = [:]
    var assignments: [VariableID: CompiledValue] = [:]
}
