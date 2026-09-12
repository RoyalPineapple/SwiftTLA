package enum RefinementFailureEvidence: Sendable, Equatable {
    case initialState(
        mapped: TLAStateProjection,
        abstractInitialStates: [TLAStateProjection]
    )
    case transition(
        action: String,
        source: TLAStateProjection,
        target: TLAStateProjection,
        mappedSource: TLAStateProjection,
        mappedTarget: TLAStateProjection,
        abstractSuccessors: [TLAStateProjection]
    )
}

struct RefinementChecker {
    let compilation: CompiledSpecification

    func check(_ exploration: FiniteExploration) throws -> ModelCheckOutcome? {
        guard !compilation.refinements.isEmpty else { return nil }
        try exploration.validate(for: compilation)
        guard exploration.isComplete else {
            guard case .depthExceeded = exploration.outcome else { return nil }
            return compilation.refinements.first.map {
                .refinementUnproven(refinement: $0.name, exploration: exploration.outcome)
            }
        }
        for refinement in compilation.refinements {
            if let violation = try check(
                refinement,
                states: exploration.compiledStates,
                initialStateIDs: exploration.initialStateIDs,
                graph: exploration.graph
            ) {
                return violation
            }
        }
        return nil
    }

    private func check(
        _ refinement: CompiledRefinement,
        states: [StateGraph.StateID: CompiledState],
        initialStateIDs: [StateGraph.StateID],
        graph: StateGraph
    ) throws -> ModelCheckOutcome? {
        guard compilation.layout.moduleInstances.contains(where: {
            $0.id == refinement.instance
        }) else {
            throw CompilationDiagnostic(
                code: .unresolvedRefinementInstance,
                stage: .runtime,
                path: "refinements.\(refinement.name).instance",
                expected: "the compiled module-instance identity",
                actual: "a refinement bound to a different compilation",
                nextSafeAction: "Compile the source model again before checking refinement."
            )
        }
        let abstractRuntime = CompiledRuntime(compilation: refinement.abstract)
        let abstractInitialStates = try abstractRuntime.initialStates()
        if let initial = abstractInitialStates.first,
           try !abstractRuntime.assumeHolds(in: initial) {
            return .assumptionViolated
        }
        for stateID in initialStateIDs {
            let source = try requiredState(stateID, in: states)
            let mapped = try mappedState(refinement, source: source)
            guard abstractInitialStates.contains(mapped) else {
                return .refinementViolated(
                    refinement: refinement.name,
                    evidence: .initialState(
                        mapped: try mapped.projection(using: refinement.abstract.layout),
                        abstractInitialStates: try abstractInitialStates.map { try $0.projection(using: refinement.abstract.layout) }
                    )
                )
            }
        }
        for (sourceID, transitions) in graph.transitions {
            let source = try requiredState(sourceID, in: states)
            let mappedSource = try mappedState(refinement, source: source)
            let abstractSuccessors = try abstractRuntime.successors(from: mappedSource).map(\.state)
            for transition in transitions {
                let target = try requiredState(transition.target, in: states)
                let mappedTarget = try mappedState(refinement, source: target)
                guard mappedTarget == mappedSource || abstractSuccessors.contains(mappedTarget) else {
                    return .refinementViolated(
                        refinement: refinement.name,
                        evidence: .transition(
                            action: transition.label.description,
                            source: try source.projection(using: compilation.layout),
                            target: try target.projection(using: compilation.layout),
                            mappedSource: try mappedSource.projection(using: refinement.abstract.layout),
                            mappedTarget: try mappedTarget.projection(using: refinement.abstract.layout),
                            abstractSuccessors: try abstractSuccessors.map { try $0.projection(using: refinement.abstract.layout) }
                        )
                    )
                }
            }
        }
        return nil
    }

    private func requiredState(
        _ id: StateGraph.StateID, in states: [StateGraph.StateID: CompiledState]
    ) throws -> CompiledState {
        guard let state = states[id] else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch, stage: .checking, path: "refinement.exploration",
                expected: "a compiled state for every initial identity and transition endpoint",
                actual: "no compiled state for \(id)",
                nextSafeAction: "Explore the compiled specification again before checking refinement."
            )
        }
        return state
    }

    private func mappedState(_ refinement: CompiledRefinement, source: CompiledState) throws -> CompiledState {
        try CompiledState(
            values: CompiledRuntime(compilation: compilation).evaluate(refinement.variableMappings, in: source),
            layout: refinement.abstract.layout, identity: refinement.abstract.identity
        )
    }
}

extension TLASpec {
    func specializing(parameters: [String: StateExpr]) -> TLASpec {
        func state(_ expression: StateExpr) -> StateExpr {
            StateExpr.substituteVariables(parameters, in: expression)
        }
        func action(_ expression: ActionExpr) -> ActionExpr {
            expression.substitutingVariables(parameters)
        }
        func initialization(_ value: VariableInitialization) -> VariableInitialization {
            switch value {
            case .value: return value
            case .expression(let expression): return .expression(state(expression))
            case .memberOf(let set): return .memberOf(state(set))
            }
        }
        var specialized = TLASpec(
            name: name,
            variables: variables.map { .init(name: $0.name, initialization: initialization($0.initialization), collectionType: $0.collectionType, generatedSwiftType: $0.generatedSwiftType, origin: $0.origin) },
            actions: actions.map { .init(name: $0.name, body: action($0.body), bindings: $0.bindings, controlOwner: $0.controlOwner) },
            invariants: invariants.map { .init(name: $0.name, body: state($0.body)) }, temporalProperties: temporalProperties,
            fairness: fairness, assume: assume.map(state), checkDeadlock: checkDeadlock,
            extendsModules: extendsModules, constraint: constraint.map(state),
            recursiveFuncs: recursiveFuncs.map { $0.substitutingVariables(parameters) },
            formalOperatorDefinitions: formalOperatorDefinitions.map { $0.substitutingVariables(parameters) },
            imports: imports, importConfigurations: importConfigurations, moduleInstances: moduleInstances, refinements: [],
            symmetrySets: symmetrySets, collections: collections,
            sourceAlgorithms: sourceAlgorithms
        )
        specialized.authoredPlusCalAlgorithmPlan = authoredPlusCalAlgorithmPlan
        specialized.algorithmPhase = algorithmPhase
        return specialized
    }
}
