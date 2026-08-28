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

    func check(_ exploration: ModelExplorationResult) throws -> ModelCheckOutcome? {
        guard exploration.isComplete else {
            return compilation.refinements.first.map {
                .refinementUnproven(refinement: $0.name, exploration: exploration.result)
            }
        }
        for refinement in compilation.refinements {
            if let result = try check(
                refinement,
                states: exploration.compiledStates,
                initialStateIDs: exploration.initialStateIDs,
                graph: exploration.graph
            ) {
                return result
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
        for stateID in initialStateIDs {
            guard let source = states[stateID] else { continue }
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
            guard let source = states[sourceID] else { continue }
            let mappedSource = try mappedState(refinement, source: source)
            let abstractSuccessors = try abstractRuntime.successors(from: mappedSource).map(\.state)
            for transition in transitions {
                guard let target = states[transition.target] else { continue }
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

    private func mappedState(_ refinement: CompiledRefinement, source: CompiledState) throws -> CompiledState {
        try CompiledState(
            values: CompiledRuntime(compilation: compilation).evaluate(refinement.variableMappings, in: source),
            compilation: refinement.abstract
        )
    }
}

extension TLASpec {
    func specializing(parameters: [String: StateExpr]) -> TLASpec {
        func state(_ expression: StateExpr) -> StateExpr {
            parameters.reduce(expression) { result, binding in
                StateExpr.substituteVariable(binding.key, with: binding.value, in: result)
            }
        }
        func action(_ expression: ActionExpr) -> ActionExpr {
            parameters.reduce(expression) { result, binding in
                result.substitutingVariable(binding.key, with: binding.value)
            }
        }
        func initialization(_ value: VariableInitialization) -> VariableInitialization {
            switch value {
            case .value: return value
            case .expression(let expression): return .expression(state(expression))
            case .memberOf(let set): return .memberOf(state(set))
            }
        }
        return TLASpec(
            name: name,
            variables: variables.map { .init(name: $0.name, initialization: initialization($0.initialization), collectionType: $0.collectionType, generatedSwiftType: $0.generatedSwiftType, origin: $0.origin) },
            actions: actions.map { .init(name: $0.name, body: action($0.body), bindings: $0.bindings, controlOwner: $0.controlOwner) },
            invariants: invariants.map { .init(name: $0.name, body: state($0.body)) }, temporalProperties: temporalProperties,
            fairness: fairness, assume: assume.map(state), checkDeadlock: checkDeadlock,
            extendsModules: extendsModules, constraint: constraint.map(state),
            recursiveFuncs: recursiveFuncs.map { .init(name: $0.name, params: $0.params, body: state($0.body)) },
            formalOperatorDefinitions: formalOperatorDefinitions.map { .init(name: $0.name, parameters: $0.parameters, body: state($0.body), plusCalPhase: $0.plusCalPhase, plusCalDependencies: $0.plusCalDependencies) },
            imports: imports, importConfigurations: importConfigurations, moduleInstances: moduleInstances, refinements: [],
            symmetrySets: symmetrySets, symmetricCollections: symmetricCollections,
            sourceAlgorithms: sourceAlgorithms
        )
    }
}
