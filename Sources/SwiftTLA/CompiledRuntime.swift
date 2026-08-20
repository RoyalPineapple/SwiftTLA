struct CompiledRuntime {
    let compilation: CompiledSpecification

    private var layout: CompiledLayout { compilation.layout }
    private var model: CompiledModel { compilation.model }

    func initialStates() throws -> [FormalState] {
        let initialValues = compilation.spec.variables.map(\.initial)
        var states = [try FormalState(values: initialValues, layout: layout)]

        for variable in layout.variables {
            guard let initializer = model.variableInitializers[variable.id] else { continue }
            guard let set = initializer.lazySet ?? initializer.initialSet else { continue }
            states = try states.flatMap { state in
                guard case .set(let values) = try CompiledEvaluator(state: state, model: model).evaluate(set) else {
                    throw EvalError.typeMismatch("Variable initialization requires a set")
                }
                return try TLAValue.sorted(values).map { value in
                    try state.updating(variable.id, to: value)
                }
            }
        }

        for variable in layout.variables {
            guard let initializer = model.variableInitializers[variable.id], let expression = initializer.initExpr else {
                continue
            }
            states = try states.map { state in
                try state.updating(
                    variable.id,
                    to: CompiledEvaluator(state: state, model: model).evaluate(expression)
                )
            }
        }
        return states
    }

    func successors(from state: FormalState) throws -> [CompiledSuccessor] {
        try model.actions.flatMap { action in
            try successors(for: action.id, from: state)
        }
    }

    func successors(for actionID: ActionID, from state: FormalState) throws -> [CompiledSuccessor] {
        guard let action = model.actions.first(where: { $0.id == actionID }) else {
            throw CompiledEvaluationError.unresolvedOperator
        }
        return try CompiledActionEnumerator(state: state, model: model)
            .enumerate(action)
            .filter { successor in try constraintHolds(in: successor) }
            .map { .init(action: actionID, state: $0) }
    }

    func assumeHolds(in state: FormalState) throws -> Bool {
        guard let assume = model.assume else { return true }
        return try boolean(assume, in: state)
    }

    func invariantHolds(_ invariant: CompiledInvariant, in state: FormalState) throws -> Bool {
        try boolean(invariant.body, in: state)
    }

    func canonicalState(_ state: FormalState) -> FormalState {
        let groups = model.symmetricCollections.map {
            SymmetricCollectionPermutationGroup(members: $0.members)
        }
        let candidates = groups.reduce([state]) { candidates, group in
            candidates.flatMap { candidate in
                group.mappings.map { mapping in
                    candidate.transformingValues { applySymmetricMemberPermutation($0, mapping: mapping) }
                }
            }
        }
        let base = candidates.min { $0.canonicalEncoding < $1.canonicalEncoding } ?? state
        return model.symmetrySets.reduce(base) { current, symmetry in
            let present = TLAValue.sorted(symmetry.values).filter(current.contains)
            guard let canonical = present.first else { return current }
            let mapping = Dictionary(uniqueKeysWithValues: present.map { ($0, canonical) })
            return current.transformingValues { applyMapping($0, mapping: mapping) }
        }
    }

    private func constraintHolds(in state: FormalState) throws -> Bool {
        guard let constraint = model.constraint else { return true }
        return try boolean(constraint, in: state)
    }

    private func boolean(_ expression: CompiledStateExpr, in state: FormalState) throws -> Bool {
        guard case .bool(let result) = try CompiledEvaluator(state: state, model: model).evaluate(expression) else {
            throw EvalError.typeMismatch("Expected a boolean")
        }
        return result
    }
}

struct CompiledSuccessor: Sendable {
    let action: ActionID
    let state: FormalState
}
