struct CompiledRuntime {
    let compilation: CompiledSpecification

    private var layout: CompiledLayout { compilation.layout }
    private var semantics: CompiledSemantics { compilation.semantics }

    func initialStates() throws -> [CompiledState] {
        let initialValues = try layout.variables.map { variable in
            guard let value = semantics.initialValues[variable.id] else {
                throw CompiledEvaluationError.invalidVariableID(variable.id)
            }
            return value
        }
        var states = [try CompiledState(values: initialValues, compilation: compilation)]

        for variable in layout.variables {
            guard let initializer = semantics.variableInitializers[variable.id] else { continue }
            guard let set = initializer.lazySet ?? initializer.initialSet else { continue }
            states = try states.flatMap { state in
                guard case .set(let values) = try CompiledEvaluator(state: state, semantics: semantics, layout: layout).evaluate(set) else {
                    throw EvalError.typeMismatch("Variable initialization requires a set")
                }
                return try CompiledValue.sorted(values).map { value in
                    try state.updating(variable.id, to: value)
                }
            }
        }

        for variable in layout.variables {
            guard let initializer = semantics.variableInitializers[variable.id], let expression = initializer.initExpr else {
                continue
            }
            states = try states.map { state in
                try state.updating(
                    variable.id,
                    to: CompiledEvaluator(state: state, semantics: semantics, layout: layout).evaluate(expression)
                )
            }
        }
        return states
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
            .enumerateResults(action)
            .filter { successor in try constraintHolds(in: successor.state) }
            .map { .init(action: actionID, arguments: $0.arguments, state: $0.state) }
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

    func canonicalState(_ state: CompiledState) throws -> CompiledState {
        try state.requireIdentity(compilation.identity)
        let groups = semantics.symmetricCollections.map {
            SymmetricCollectionPermutationGroup(members: $0.members)
        }
        let candidates = groups.reduce([state]) { candidates, group in
            candidates.flatMap { candidate in
                group.mappings.map { mapping in
                    candidate.transformingFormalValues { applySymmetricMemberPermutation($0, mapping: mapping) }
                }
            }
        }
        let base = try candidates.min {
            try $0.canonicalEncoding(using: layout) < $1.canonicalEncoding(using: layout)
        } ?? state
        return semantics.symmetrySets.reduce(base) { current, symmetry in
            let present = TLAValue.sorted(symmetry.values).filter(current.contains)
            guard let canonical = present.first else { return current }
            let mapping: [TLAValue: TLAValue] = Dictionary(
                uniqueKeysWithValues: present.map { ($0, canonical) }
            )
            return current.transformingFormalValues { applyMapping($0, mapping) }
        }
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
        guard case .boolean(let result) = try CompiledEvaluator(
            state: state,
            semantics: semantics,
            layout: layout,
            enabledActions: enabledActions
        ).evaluate(expression) else {
            throw EvalError.typeMismatch("Expected a boolean")
        }
        return result
    }
}

struct CompiledSuccessor: Sendable {
    let action: ActionID
    let arguments: [TLAValue]
    let state: CompiledState
}

package enum CompiledPropertyOutcome: Sendable, Equatable {
    case satisfied(name: String)
    case violated(name: String)
    case evaluationFailed(name: String, diagnostic: CompiledPropertyDiagnostic)
    case evaluationUnavailable(name: String, diagnostic: CompiledPropertyDiagnostic)
}

package struct CompiledPropertyDiagnostic: Sendable, Equatable {
    package enum Code: String, Sendable, Equatable {
        case evaluationError
        case evaluatorUnavailable
    }

    package let code: Code
    package let message: String

    package init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}
