struct CompiledActionEnumerator {
    let state: FormalState
    let model: CompiledModel

    func enumerate(_ action: CompiledAction) throws -> [FormalState] {
        let choices = chooseActions(in: action.body)
        return try actionBindings(action.bindings).flatMap { bindings in
            let selections = try selectChoices(choices, bindings: bindings)
            return try selections.flatMap { selection in
                let evaluationState = try state.updating(selection)
                return try execute(action.body, state: evaluationState, bindings: bindings).map { delta in
                    try state.updating(selection).updating(delta.assignments)
                }
            }
        }
    }

    private func execute(
        _ action: CompiledActionExpr,
        state: FormalState,
        bindings: CompiledBindings
    ) throws -> [CompiledActionDelta] {
        let evaluator = CompiledEvaluator(state: state, model: model, bindings: bindings)
        switch action {
        case .assign(let variable, let expression):
            return [.init(assignments: [variable: try evaluator.evaluate(expression)])]
        case .unchanged:
            return [.init()]
        case .guard_(let expression):
            guard try evaluator.evaluate(expression) == .bool(true) else { return [] }
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
                try evaluator.evaluate(condition) == .bool(true) ? then : otherwise,
                state: state,
                bindings: bindings
            )
        case .and(let lhs, let rhs):
            let left = try execute(lhs, state: state, bindings: bindings)
            let right = try execute(rhs, state: state, bindings: bindings)
            return try left.flatMap { first in
                try right.map { second in try first.merging(second) }
            }
        case .or(let lhs, let rhs):
            return try execute(lhs, state: state, bindings: bindings)
                + execute(rhs, state: state, bindings: bindings)
        }
    }

    private func actionBindings(_ bindings: [CompiledActionBinding]) -> [CompiledBindings] {
        bindings.reduce([.init()]) { partial, binding in
            partial.flatMap { values in
                binding.values.map { values.binding($0, to: binding.binder) }
            }
        }
    }

    private func selectChoices(
        _ choices: [(VariableID, CompiledStateExpr)],
        bindings: CompiledBindings
    ) throws -> [[VariableID: TLAValue]] {
        try choices.reduce([[:]]) { selections, choice in
            try selections.flatMap { selection in
                let selectionState = try state.updating(selection)
                let evaluator = CompiledEvaluator(state: selectionState, model: model, bindings: bindings)
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

private struct CompiledActionDelta {
    var assignments: [VariableID: TLAValue] = [:]

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
