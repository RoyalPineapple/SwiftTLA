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
        let outcomes = try initialOutcomes()
        if let failure = outcomes.firstFailure {
            if let compiledFailure = failure.compiledFailure { throw compiledFailure }
            throw failure
        }
        return outcomes.states
    }

    func initialOutcomes() throws -> InitialEvaluationOutcomes<CompiledState> {
        var pending: [(Int, [VariableID: CompiledValue])] = [(0, [:])]
        var states: [CompiledState] = []
        var firstFailure: NativeMachineEvaluationError?
        let initializations = behavior.initializations
        let selectedInvariant = behavior.initialInvariant.map { selected in
            guard let invariant = behavior.invariants.first(where: { $0.id == selected }) else {
                preconditionFailure("Compiled initial invariant is absent from its behavior")
            }
            return invariant
        }
        while let (index, values) = pending.popLast() {
            try _NativeMachineOperations.visitInitialBranch {
                guard index < initializations.count else {
                    let state = try CompiledState(values: layout.variables.map { variable in
                        guard let value = values[variable.id] else {
                            throw CompiledEvaluationError.uninitializedVariable(variable.id)
                        }
                        return value
                    }, layout: layout, identity: identity)
                    if let selectedInvariant {
                        if try invariantHolds(selectedInvariant, in: state) { states.append(state) }
                    } else {
                        states.append(state)
                    }
                    return
                }
                let (variable, initialization) = initializations[index]
                let evaluator = CompiledEvaluator(
                    variableValues: values,
                    operators: operators, functions: functions
                )
                switch initialization {
                case .value(let expression):
                    var values = values
                    values[variable] = try evaluator.evaluate(expression)
                    pending.append((index + 1, values))
                case .memberOf(let set):
                    let members: Set<CompiledValue>
                    if case .randomSubset = set.computation.operation {
                        let countValue = try evaluator.evaluate(set.computation.children[0])
                        guard case .integer(let count) = countValue else {
                            throw EvalError.expected(.integer, actual: [countValue])
                        }
                        try _NativeMachineOperations.validateRandomSubsetCount(count)
                        let domainExpression = set.computation.children[1]
                        if case .functionSet = domainExpression.operation {
                            let fromValue = try evaluator.evaluate(domainExpression.children[0])
                            let toValue = try evaluator.evaluate(domainExpression.children[1])
                            guard case .set(let from) = fromValue, case .set(let to) = toValue else {
                                throw EvalError.expected(.functionSetDomains, actual: [fromValue, toValue])
                            }
                            let functions = try _NativeMachineOperations.randomFunctionInitialSupport(
                                upTo: count, from: from, to: to)
                            members = Set(functions.map(CompiledValue.function))
                        } else {
                            let domainValue = try evaluator.evaluate(domainExpression)
                            guard case .set(let domain) = domainValue else {
                                throw EvalError.expected(.set, actual: [domainValue])
                            }
                            members = try _NativeMachineOperations.randomSubsetInitialSupport(
                                upTo: count, from: domain)
                        }
                    } else {
                        let value = try evaluator.evaluate(set)
                        guard case .set(let domain) = value else {
                            throw EvalError.expected(.set, actual: [value])
                        }
                        members = domain
                    }
                    for member in CompiledValue.sorted(members).reversed() {
                        var candidate = values
                        candidate[variable] = member
                        pending.append((index + 1, candidate))
                    }
                }
            } onEvaluationFailure: { failure in
                if firstFailure == nil { firstFailure = failure }
            }
        }
        return .init(states: states, firstFailure: firstFailure)
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
    }

    func assumeHolds(in state: CompiledState) throws -> Bool {
        try state.requireIdentity(identity)
        guard let assume = behavior.assume else { return true }
        return try boolean(assume, in: state)
    }

    func invariantHolds(_ invariant: CompiledStatePredicate, in state: CompiledState) throws -> Bool {
        try state.requireIdentity(identity)
        return try boolean(invariant.predicate, in: state)
    }

    func predicateHolds(_ predicate: CompiledStateQuery, in state: CompiledState,
                        bindings: CompiledBindings = .init()) throws -> Bool {
        try state.requireIdentity(identity)
        return try boolean(predicate, in: state, bindings: bindings)
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

    func constraintHolds(in state: CompiledState) throws -> Bool {
        try state.requireIdentity(identity)
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
        in state: CompiledState,
        bindings: CompiledBindings = .init()
    ) throws -> Bool {
        let value = try CompiledEvaluator(
            state: state,
            operators: operators, functions: functions, bindings: bindings,
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
