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
        let choices = chooseActions(in: action.body)
        return try actionBindings(action.bindings).flatMap { binding in
            let selections = try selectChoices(choices, bindings: binding.values)
            return try selections.flatMap { selection in
                let evaluationState = try state.updating(selection)
                return try execute(action.body, state: evaluationState, bindings: binding.values).map { delta in
                    CompiledSuccessor(
                        action: action.id,
                        arguments: binding.arguments,
                        state: try state.updating(selection).updating(delta.assignments),
                    )
                }
            }
        }
    }

    private func execute(
        _ action: CompiledActionExpr,
        state: CompiledState,
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
        case .unchanged:
            return [.init()]
        case .guard_(let expression):
            guard try evaluator.evaluate(expression) == .boolean(true) else { return [] }
            return [.init()]
        case .chooseAction(let variable, let set):
            _ = variable
            _ = set
            return [.init()]
        case .existsAction(let binder, let set, let body):
            guard case .set(let values) = try evaluator.evaluate(set) else {
                throw EvalError.typeMismatch("WITH requires a set")
            }
            return try values.flatMap { value in
                try execute(body, state: state, bindings: bindings.binding(value, to: binder))
            }
        case .define(let binder, let value, let body):
            return try execute(
                body,
                state: state,
                bindings: bindings.binding(try evaluator.evaluate(value), to: binder)
            )
        case .ifElse(let condition, let then, let otherwise):
            return try execute(
                try evaluator.evaluate(condition) == .boolean(true) ? then : otherwise,
                state: state,
                bindings: bindings
            )
        case .and(let lhs, let rhs):
            let left = try execute(lhs, state: state, bindings: bindings)
            guard !left.isEmpty else { return [] }
            let right = try execute(rhs, state: state, bindings: bindings)
            return try left.flatMap { first in
                try right.map { second in try first.merging(second) }
            }
        case .or(let lhs, let rhs):
            return try execute(lhs, state: state, bindings: bindings)
                + execute(rhs, state: state, bindings: bindings)
        }
    }

    private func actionBindings(_ bindings: [CompiledActionBinding]) -> [CompiledActionBindingValues] {
        bindings.reduce([.init(values: .init(), arguments: [])]) { partial, binding in
            partial.flatMap { current in
                binding.values.map { value in
                    .init(
                        values: current.values.binding(.init(formal: value), to: binding.binder),
                        arguments: current.arguments + [.init(formal: value)]
                    )
                }
            }
        }
    }

    private func selectChoices(
        _ choices: [(VariableID, CompiledStateExpr)],
        bindings: CompiledBindings
    ) throws -> [[VariableID: CompiledValue]] {
        try choices.reduce([[:]]) { selections, choice in
            try selections.flatMap { selection in
                let selectionState = try state.updating(selection)
                let evaluator = CompiledEvaluator(
                    state: selectionState,
                    semantics: semantics,
                    layout: layout,
                    bindings: bindings,
                    enabledActions: enabledActions
                )
                guard case .set(let values) = try evaluator.evaluate(choice.1) else {
                    throw EvalError.typeMismatch("CHOOSE requires a set")
                }
                return values.map { value in
                    var selected = selection
                    selected[choice.0] = value
                    return selected
                }
            }
        }
    }

    private func chooseActions(in action: CompiledActionExpr) -> [(VariableID, CompiledStateExpr)] {
        switch action {
        case .chooseAction(let variable, let set):
            return [(variable, set)]
        case .and(let lhs, let rhs):
            return chooseActions(in: lhs) + chooseActions(in: rhs)
        case .assign, .unchanged, .guard_, .existsAction, .ifElse, .define, .or:
            return []
        }
    }
}

private struct CompiledActionBindingValues {
    let values: CompiledBindings
    let arguments: [CompiledValue]
}

private struct CompiledActionDelta {
    var assignments: [VariableID: CompiledValue] = [:]

    func merging(_ other: CompiledActionDelta) throws -> CompiledActionDelta {
        var merged = self
        for assignment in other.assignments {
            if let value = merged.assignments[assignment.key], value != assignment.value {
                throw CompiledEvaluationError.conflictingAssignment(assignment.key)
            }
            merged.assignments[assignment.key] = assignment.value
        }
        return merged
    }
}
