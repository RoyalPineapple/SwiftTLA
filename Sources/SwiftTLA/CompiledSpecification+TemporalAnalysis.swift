enum TemporalEvaluationError: Error, Equatable {
    case predicate(state: StateGraph.StateID, cause: EvalError)
    case leadsToTrigger(state: StateGraph.StateID, cause: EvalError)
}

extension FiniteExploration {
    package func analyzeTemporalProperties(in compilation: CompiledSpecification) throws -> [TemporalAnalysis] {
        try validate(for: compilation)
        return try compilation.analyzeTemporalProperties(
            graph: graph, states: compiledStates, initialStateIDs: initialStateIDs, isComplete: isComplete
        )
    }
}

extension CompiledSpecification {
    func livenessChecker(graph: StateGraph) -> LivenessChecker<CompiledActionCall, CompiledFairnessCondition.Scope> {
        let knownActions = Set(semantics.behavior.actions.map(\.id))
        return LivenessChecker(
            states: Set(graph.states.keys),
            transitions: Dictionary(uniqueKeysWithValues: graph.transitions.map { source, successors in
                (source, successors.map { successor in
                    let call = successor.label.actionID.flatMap { action in
                        knownActions.contains(action)
                            ? CompiledActionCall(action: action, arguments: successor.label.arguments) : nil
                    }
                    return GraphEdge(source: source, action: call, renderedAction: successor.action, target: successor.target)
                })
            }),
            matches: { call, scope in
                switch scope {
                case .next: return true
                case .action(let action): return call.action == action
                case .actionCall(let expected): return call == expected
                }
            },
            actionOrder: { lhs, rhs in
                if lhs.action != rhs.action { return lhs.action.ordinal < rhs.action.ordinal }
                return lhs.arguments.lexicographicallyPrecedes(rhs.arguments)
            }
        )
    }

    func analyzeTemporalProperties(
        graph: StateGraph,
        states: [StateGraph.StateID: CompiledState],
        initialStateIDs: [StateGraph.StateID],
        isComplete: Bool = true
    ) throws -> [TemporalAnalysis] {
        let runtime = CompiledRuntime(compilation: self)
        let checker = livenessChecker(graph: graph)
        func predicate(_ query: CompiledStateQuery, isTrigger: Bool = false) -> @Sendable (StateGraph.StateID) throws -> Bool {
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
                    return try runtime.predicateHolds(query, in: compiled)
                } catch let error as EvalError {
                    if isTrigger { throw TemporalEvaluationError.leadsToTrigger(state: state, cause: error) }
                    throw TemporalEvaluationError.predicate(state: state, cause: error)
                }
            }
        }
        return try semantics.behavior.temporalProperties.map { property in
            let expression: TemporalCondition<@Sendable (StateGraph.StateID) throws -> Bool>
            if case .leadsTo(let trigger, let target) = property.expression {
                expression = .leadsTo(predicate(trigger, isTrigger: true), predicate(target))
            } else {
                expression = property.expression.map { predicate($0) }
            }
            return try checker.analyze(
                expression, fairness: semantics.behavior.fairness.map { ($0.scope, $0.isStrong) },
                initialStateIDs: initialStateIDs, isComplete: isComplete,
                renderScope: { scope in
                    switch scope {
                    case .next: return "Next"
                    case .action(let action): return layout.actions[action.ordinal].declaration.name
                    case .actionCall(let call):
                        return formalActionCall(
                            named: layout.actions[call.action.ordinal].declaration.name,
                            arguments: try call.arguments.map { try $0.rendered(using: layout) }
                        )
                    }
                }
            )
        }
    }
}
