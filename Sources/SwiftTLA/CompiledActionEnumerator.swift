struct CompiledActionEnumerator {
    let state: FormalState
    let model: CompiledModel

    func enumerate(_ action: CompiledAction) throws -> [FormalState] {
        try execute(action.body, bindings: .init()).map { delta in
            try delta.assignments.reduce(state) { next, assignment in
                try next.updating(assignment.key, to: assignment.value)
            }
        }
    }

    private func execute(
        _ action: CompiledActionExpr,
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
            guard case .set(let values) = try evaluator.evaluate(set) else {
                throw EvalError.typeMismatch("CHOOSE requires a set")
            }
            return values.map { .init(assignments: [variable: $0]) }
        case .existsAction(let binder, let set, let body):
            guard case .set(let values) = try evaluator.evaluate(set) else {
                throw EvalError.typeMismatch("WITH requires a set")
            }
            return try values.flatMap { value in
                try execute(body, bindings: bindings.binding(value, to: binder))
            }
        case .define(let binder, let value, let body):
            return try execute(body, bindings: bindings.binding(try evaluator.evaluate(value), to: binder))
        case .ifElse(let condition, let then, let otherwise):
            return try execute(try evaluator.evaluate(condition) == .bool(true) ? then : otherwise, bindings: bindings)
        case .and(let lhs, let rhs):
            let left = try execute(lhs, bindings: bindings)
            let right = try execute(rhs, bindings: bindings)
            return try left.flatMap { first in
                try right.map { second in try first.merging(second) }
            }
        case .or(let lhs, let rhs):
            return try execute(lhs, bindings: bindings) + execute(rhs, bindings: bindings)
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
