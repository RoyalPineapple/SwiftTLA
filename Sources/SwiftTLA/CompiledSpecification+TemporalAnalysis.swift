enum TemporalEvaluationError: Error, Equatable {
    case predicate(state: StateGraph.StateID, cause: EvalError)
    case leadsToTrigger(state: StateGraph.StateID, cause: EvalError)
}

extension FiniteExploration {
    package func analyzeTemporalProperties(in compilation: CompiledSpecification) throws -> [TemporalAnalysis<StateGraph.StateID, String?>] {
        try validate(for: compilation)
        return try compilation.analyzeTemporalProperties(
            graph: graph, states: compiledStates, initialStateIDs: initialStateIDs, isComplete: isComplete
        )
    }
}

extension CompiledSpecification {
    func livenessChecker(graph: StateGraph) -> LivenessChecker<StateGraph.StateID, CompiledActionCall, CompiledFairnessCondition.Scope> {
        let knownActions = Set(semantics.behavior.actions.map(\.id))
        let calls = Set(graph.transitions.values.flatMap { successors in
            successors.compactMap { successor -> CompiledActionCall? in
                guard let id = successor.label.actionID, knownActions.contains(id) else { return nil }
                return CompiledActionCall(action: id, arguments: successor.label.arguments)
            }
        }).sorted {
            if $0.action != $1.action { return $0.action.ordinal < $1.action.ordinal }
            return $0.arguments.lexicographicallyPrecedes($1.arguments)
        }
        // An invocation absent from the entire graph is never enabled there,
        // so both its weak and strong fairness obligations are vacuous.
        let fairness = semantics.behavior.fairness.flatMap { condition -> [(CompiledFairnessCondition.Scope, Bool)] in
            if case .eachAction(let id) = condition.scope {
                return calls.filter { $0.action == id }.map { (.actionCall($0), condition.isStrong) }
            }
            return [(condition.scope, condition.isStrong)]
        }
        return LivenessChecker(
            states: Set(graph.states.keys),
            transitions: Dictionary(uniqueKeysWithValues: graph.transitions.map { source, successors in
                (source, successors.map { successor in
                    let call = successor.label.actionID.flatMap { action in
                        knownActions.contains(action)
                            ? CompiledActionCall(action: action, arguments: successor.label.arguments) : nil
                    }
                    return GraphEdge(source: source, action: call, target: successor.target)
                })
            }),
            fairness: fairness,
            matches: { call, scope in
                switch scope {
                case .next: return true
                case .action(let action): return call.action == action
                case .actionCall(let expected): return call == expected
                case .eachAction: preconditionFailure("Per-instance fairness must be expanded before analysis")
                }
            },
            actionOrder: { lhs, rhs in
                if lhs.action != rhs.action { return lhs.action.ordinal < rhs.action.ordinal }
                return lhs.arguments.lexicographicallyPrecedes(rhs.arguments)
            },
            stateOrder: { $0.id < $1.id }
        )
    }

    func analyzeTemporalProperties(
        graph: StateGraph,
        states: [StateGraph.StateID: CompiledState],
        initialStateIDs: [StateGraph.StateID],
        isComplete: Bool = true
    ) throws -> [TemporalAnalysis<StateGraph.StateID, String?>] {
        let runtime = CompiledRuntime(compilation: self)
        let checker = livenessChecker(graph: graph)
        func predicate(_ query: CompiledStateQuery, bindings: CompiledBindings,
                       isTrigger: Bool = false) -> @Sendable (StateGraph.StateID) throws -> Bool {
            { state in
                guard let compiled = states[state] else {
                    throw CompilationDiagnostic(
                        code: .compilationIdentityMismatch, stage: .checking, path: "liveness.state",
                        expected: "a state produced by this compilation",
                        actual: "state \(state) has no compiled value",
                        nextSafeAction: "Explore the compiled specification again before checking liveness."
                    )
                }
                do {
                    return try runtime.predicateHolds(query, in: compiled, bindings: bindings)
                } catch let error as EvalError {
                    if isTrigger { throw TemporalEvaluationError.leadsToTrigger(state: state, cause: error) }
                    throw TemporalEvaluationError.predicate(state: state, cause: error)
                }
            }
        }
        func predicates(_ source: TemporalCondition<CompiledStateQuery>, bindings: CompiledBindings) -> TemporalCondition<@Sendable (StateGraph.StateID) throws -> Bool> {
            switch source {
            case .all(let conditions): return .all(conditions.map { predicates($0, bindings: bindings) })
            case .conditional(let guardQuery, let yes, let no):
                return .conditional(predicate(guardQuery, bindings: bindings),
                    then: predicates(yes, bindings: bindings), else: predicates(no, bindings: bindings))
            case .leadsTo(let trigger, let target): return .leadsTo(predicate(trigger, bindings: bindings, isTrigger: true), predicate(target, bindings: bindings))
            default: return source.map { predicate($0, bindings: bindings) }
            }
        }
        return try semantics.behavior.temporalProperties.map { property in
            var bindings = [CompiledBindings()]
            for binding in property.bindings {
                bindings = try bindings.flatMap { scope in
                    let domain = try CompiledEvaluator(variableValues: [:], operators: semantics.operators, bindings: scope).evaluate(binding.domain)
                    guard case .set(let members) = domain else {
                        throw EvalError.expected(.set, actual: [domain])
                    }
                    return CompiledValue.sorted(members).map { scope.binding($0, to: binding.binder) }
                }
            }
            return try checker.analyze(
                property.bindings.isEmpty ? predicates(property.expression, bindings: .init())
                    : .all(bindings.map { predicates(property.expression, bindings: $0) }),
                initialStates: initialStateIDs, isComplete: isComplete,
                renderScope: { scope in
                    switch scope {
                    case .next: return "Next"
                    case .action(let action): return layout.actions[action.ordinal].declaration.name
                    case .actionCall(let call):
                        return formalActionCall(
                            named: layout.actions[call.action.ordinal].declaration.name,
                            arguments: try call.arguments.map { try $0.rendered(using: layout) }
                        )
                    case .eachAction: preconditionFailure("Per-instance fairness must be expanded before analysis")
                    }
                }
            ).map(state: { $0 }, action: { call in
                guard let call else { return nil }
                return formalActionCall(
                    named: layout.actions[call.action.ordinal].declaration.name,
                    arguments: try call.arguments.map { try $0.rendered(using: layout) }
                )
            })
        }
    }
}
