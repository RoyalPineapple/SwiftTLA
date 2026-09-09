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
            try execute(action.body, bindings: binding.values).map { delta in
                CompiledSuccessor(
                    action: action.id,
                    arguments: binding.arguments,
                    state: try state.updating(delta.assignments)
                )
            }
        }
    }

    private func execute(
        _ action: CompiledActionExpr<CompiledStateExpr>,
        bindings: CompiledBindings
    ) throws -> [CompiledActionDelta] {
        let evaluator = CompiledEvaluator(
            state: state,
            semantics: semantics,
            layout: layout,
            bindings: bindings,
            enabledActions: enabledActions
        )
        switch action {
        case .assign(let variable, let expression):
            return [.init(assignments: [variable: try evaluator.evaluate(expression)])]
        case .unchanged(let variable):
            return [.init(assignments: [variable: try state.value(for: variable)])]
        case .guard_(let expression):
            let value = try evaluator.evaluate(expression)
            guard case .boolean(let enabled) = value else {
                throw EvalError.expected(.boolean, actual: [value])
            }
            return enabled ? [.init()] : []
        case .existsAction(let binder, let set, let body):
            let domain = try evaluator.evaluate(set)
            guard case .set(let values) = domain else {
                throw EvalError.expected(.set, actual: [domain])
            }
            return try CompiledValue.sorted(values).flatMap { value in
                try execute(body, bindings: bindings.binding(value, to: binder))
            }
        case .define(let binder, let value, let body):
            return try execute(
                body,
                bindings: bindings.binding(try evaluator.evaluate(value), to: binder)
            )
        case .ifElse(let condition, let then, let otherwise):
            let value = try evaluator.evaluate(condition)
            guard case .boolean(let conditionHolds) = value else {
                throw EvalError.expected(.boolean, actual: [value])
            }
            return try execute(conditionHolds ? then : otherwise, bindings: bindings)
        case .and(let lhs, let rhs):
            let left = try execute(lhs, bindings: bindings)
            guard !left.isEmpty else { return [] }
            let right = try execute(rhs, bindings: bindings)
            return try left.flatMap { first in
                try right.map { try first.merging($0) }
            }
        case .or(let lhs, let rhs):
            return try execute(lhs, bindings: bindings) + execute(rhs, bindings: bindings)
        }
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

private struct CompiledActionDelta {
    var assignments: [VariableID: CompiledValue] = [:]

    func merging(_ other: Self) throws -> Self {
        .init(assignments: try other.assignments.reduce(into: assignments) { merged, assignment in
            if let previous = merged[assignment.key], previous != assignment.value {
                throw CompiledEvaluationError.conflictingAssignment(assignment.key)
            }
            merged[assignment.key] = assignment.value
        })
    }
}
