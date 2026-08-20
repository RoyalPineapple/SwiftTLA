extension Algorithm {
    /// Lowers a validated bounded algorithm into the ordinary executable TLA+ model.
    public func lower(
        formalOperatorDefinitions: [FormalOperatorDefinition] = []
    ) throws -> TLASpec {
        try requireValid()
        return try AlgorithmLowerer.lower(
            model,
            formalOperatorDefinitions: formalOperatorDefinitions
        )
    }
}

enum AlgorithmLoweringError: Error, CustomStringConvertible {
    case nonStaticInitialValue(name: String, underlying: Error)

    var description: String {
        switch self {
        case .nonStaticInitialValue(let name, let underlying):
            return "Algorithm variable '\(name)' needs a closed formal initial expression: \(underlying)"
        }
    }
}

enum AlgorithmLowerer {
    private static let controlVariable = "pc"
    private static let stackVariable = "__pcal_stack"
    // These frame keys are the names emitted by the official PlusCal
    // translator.  The runtime stack remains an implementation detail, but
    // its formal representation must be comparable to the independent
    // translation rather than merely equivalent by convention.
    private static let procedureField = "procedure"
    private static let returnPCField = "pc"
    private static let processBinding = "process"
    private static let builderProcessIdentifier = "__pcal_self"
    private static let doneLabel = "Done"
    private static let terminatingAction = "Terminating"

    static func lower(
        _ algorithm: AlgorithmModel,
        formalOperatorDefinitions: [FormalOperatorDefinition] = []
    ) throws -> TLASpec {
        let resolvedFormalOperators = formalOperatorDefinitions + algorithm.formalOperatorDefinitions
        let processes = algorithm.processes
        if processes.isEmpty, !algorithm.sequentialSteps.isEmpty {
            return try lowerSequential(
                algorithm,
                formalOperatorDefinitions: resolvedFormalOperators
            )
        }
        let requiresProgramCounter = requiresProgramCounter(for: algorithm)
        let translatedProcessNames = algorithm.translatedProcessNames()
        let shared = algorithm.components.compactMap { component -> AlgorithmStateModel? in
            guard case .shared(let state) = component else { return nil }
            return state
        }
        let localStates = processes.flatMap { process in
            process.components.compactMap { component -> AlgorithmStateModel? in
                guard case .local(let state) = component else { return nil }
                return state
            }
        }
        let procedures = algorithm.procedures
        let declaredInvariants = algorithm.components.compactMap { component -> NamedInvariant? in
            guard case .invariant(let invariant) = component else { return nil }
            return invariant
        }
        let processInvariants = processes.flatMap { process -> [NamedInvariant] in
            let localRoots = Set(process.components.compactMap { component -> String? in
                guard case .local(let state) = component else { return nil }
                return state.root
            })
            let processDomain = StateExpr.setLiteral(process.domain.map(StateExpr.value))
            return process.components.compactMap { component -> NamedInvariant? in
                guard case .invariant(let invariant) = component else { return nil }
                return NamedInvariant(
                    name: invariant.name,
                    body: .forAll(
                        processDomain,
                        processBinding,
                        rewrite(invariant.body, localRoots: localRoots)
                    )
                )
            }
        }
        let declaredTemporal = algorithm.components.compactMap { component -> NamedTemporal? in
            guard case .temporal(let temporal) = component else { return nil }
            return temporal
        }
        let declaredFairness = algorithm.components.compactMap { component -> FairnessCondition? in
            guard case .fairness(let fairness) = component else { return nil }
            return fairness
        }
        let declaredConstraint = algorithm.components.compactMap { component -> StateExpr? in
            guard case .stateConstraint(let constraint) = component else { return nil }
            return constraint
        }.reduce(nil) { partial, constraint in
            partial.map { .and($0, constraint) } ?? constraint
        }

        var variables = shared.map { state in
            if let initial = try? state.initial.evaluate(
                in: [:],
                formalOperatorDefinitions: resolvedFormalOperators
            ) {
                NamedVar(name: state.root, initial: initial, initialSet: state.initialSet)
            } else {
                NamedVar(name: state.root, initial: .int(0), initExpr: state.initial)
            }
        }
        for process in processes {
            for local in process.components {
                guard case .local(let state) = local else { continue }
                variables.append(
                    NamedVar(
                        name: state.root,
                        initial: try staticInitialValue(
                            constantFunction(domain: process.domain, value: state.initial),
                            named: state.root,
                            formalOperatorDefinitions: resolvedFormalOperators
                        )
                    ))
            }
        }

        if requiresProgramCounter {
            let controlBinding = "__pcal_initial_process"
            let controlDomain = processes
                .map { StateExpr.setLiteral($0.domain.map(StateExpr.value)) }
                .dropFirst()
                .reduce(
                    StateExpr.setLiteral(processes.first?.domain.map(StateExpr.value) ?? [])
                ) { partial, domain in
                    .union(partial, domain)
                }
            let controlCases = processes.flatMap { process -> [StateExpr] in
                guard let first = process.steps.first else { return [] }
                return [
                    .in(
                        .variable(controlBinding),
                        .setLiteral(process.domain.map(StateExpr.value))
                    ),
                    .value(.string(first.label.name))
                ]
            }
            variables.insert(NamedVar(
                name: controlVariable,
                initial: .function([:]),
                initExpr: .functionLiteral(
                    controlDomain,
                    controlBinding,
                    .caseExpr(controlCases, nil)
                )
            ), at: 0)
        }
        if !procedures.isEmpty {
            for slot in procedureSlots(procedures) {
                variables.append(NamedVar(
                    name: slot.root,
                    initial: try staticInitialValue(
                        constantFunction(domain: controlDomainValues(processes), value: slot.initial),
                        named: slot.root,
                        formalOperatorDefinitions: resolvedFormalOperators
                    )
                ))
            }
            variables.append(NamedVar(
                name: stackVariable,
                initial: try staticInitialValue(
                        constantFunction(domain: controlDomainValues(processes), value: .tupleLiteral([])),
                        named: stackVariable,
                        formalOperatorDefinitions: resolvedFormalOperators
                )
            ))
        }

        let variableNames = variables.map(\.name)
        let localRoots = Set(localStates.map(\.root) + procedureSlots(procedures).map(\.root))
        var generatedAssertionInvariants: [NamedInvariant] = []
        var fairness: [FairnessCondition] = []
        var actions = processes.enumerated().flatMap { processIndex, process in
            process.steps.enumerated().map { index, atomic in
                let nextLabel = process.steps.indices.contains(index + 1)
                    ? process.steps[index + 1].label.name
                    : doneLabel
                let loweredStatements = lower(
                    atomic.statements,
                    localRoots: localRoots,
                    processDomain: process.domain,
                    procedures: procedures,
                    owner: nil,
                    nextLabel: nextLabel
                )
                let body: ActionExpr
                if !requiresProgramCounter {
                    body = loweredStatements
                } else if let loopCondition = atomic.loopCondition {
                    body = .ifElse(
                        rewrite(loopCondition, localRoots: localRoots),
                        completingControl(loweredStatements, fallthrough: atomic.label.name),
                        transfer(to: nextLabel)
                    )
                } else {
                    body = completingControl(loweredStatements, fallthrough: nextLabel)
                }
                let generatedAction = NamedAction(
                    name: requiresProgramCounter ? atomic.label.name : translatedProcessNames[processIndex],
                    body: completeAction(
                        requiresProgramCounter
                            ? .and(
                                .guard_(.equal(
                                    .functionApply(.variable(controlVariable), .variable(processBinding)),
                                    .value(.string(atomic.label.name))
                                )),
                                body
                            )
                            : body,
                        allVars: variableNames
                    ),
                    bindings: [ActionBinding(name: processBinding, values: process.domain)]
                )
                if requiresProgramCounter {
                    let actionAssertions = assertionInvariants(
                        in: atomic.statements,
                        process: process,
                        label: atomic.label.name,
                        localRoots: localRoots,
                        executionCondition: atomic.loopCondition.map { rewrite($0, localRoots: localRoots) },
                        pathCondition: .value(.bool(true)),
                        quantifiedBindings: []
                    )
                    generatedAssertionInvariants += uniquelyNamed(actionAssertions)
                }
                fairness += fairnessConditions(for: generatedAction, policy: process.fairness)
                return generatedAction
            }
        }

        let procedureActions = procedures.flatMap { procedure in
            procedure.steps.enumerated().map { index, atomic in
                let label = emittedLabel(atomic.label.name, owner: procedure)
                let nextLabel = procedure.steps.indices.contains(index + 1)
                    ? emittedLabel(procedure.steps[index + 1].label.name, owner: procedure)
                    : emittedLabel(doneLabel, owner: procedure)
                let guardExpression = StateExpr.equal(
                    .functionApply(.variable(controlVariable), .variable(processBinding)),
                    .value(.string(label))
                )
                let loweredStatements = lower(
                    atomic.statements,
                    localRoots: localRoots,
                    processDomain: controlDomainValues(processes),
                    procedures: procedures,
                    owner: procedure,
                    nextLabel: nextLabel
                )
                let body = completingControl(loweredStatements, fallthrough: nextLabel)
                return NamedAction(
                    name: label,
                    body: completeAction(.and(.guard_(guardExpression), body), allVars: variableNames),
                    bindings: [ActionBinding(name: processBinding, values: controlDomainValues(processes))]
                )
            }
        }
        actions += procedureActions

        if requiresProgramCounter {
            let allDone = processes.reduce(StateExpr.value(.bool(true))) { condition, process in
                let members = StateExpr.setLiteral(process.domain.map(StateExpr.value))
                let processDone = StateExpr.forAll(
                    members,
                    processBinding,
                    .equal(
                        .functionApply(.variable(controlVariable), .variable(processBinding)),
                        .value(.string(doneLabel))
                    )
                )
                return .and(condition, processDone)
            }
            let unchanged = variableNames
                .map(ActionExpr.unchanged)
                .reduce(.guard_(allDone), ActionExpr.and)
            actions.append(NamedAction(name: terminatingAction, body: unchanged))
        }

        return TLASpec(
            name: algorithm.name,
            variables: variables,
            actions: actions,
            invariants: declaredInvariants + processInvariants + generatedAssertionInvariants,
            temporalProperties: declaredTemporal,
            fairness: declaredFairness + fairness,
            definitions: algorithm.formalOperatorDefinitions.map {
                .init(name: $0.name, text: FormalOperatorDecl($0).tlaText, dependencies: $0.plusCalDependencies)
            },
            constraint: declaredConstraint,
            formalOperatorDefinitions: resolvedFormalOperators,
            sourceAlgorithms: [Algorithm(model: algorithm)])
    }

    private static func constantFunction(domain: [TLAValue], value: StateExpr) -> StateExpr {
        let binding = "__pcal_initial_process"
        return .functionLiteral(
            .setLiteral(domain.map(StateExpr.value)),
            binding,
            // A process-local initializer may refer to `self`. At this
            // boundary `self` becomes the key of the initial formal function.
            StateExpr.substituteVariable(
                builderProcessIdentifier,
                with: .variable(binding),
                in: value
            )
        )
    }

    private static func controlDomainValues(_ processes: [AlgorithmProcessModel]) -> [TLAValue] {
        Array(Set(processes.flatMap(\.domain))).sorted { $0.description < $1.description }
    }

    /// The PlusCal translator omits `pc` for a process machine made entirely
    /// of one unconditional, control-free loop.  Preserve that source-level
    /// machine shape instead of materializing a constant implementation state.
    private static func requiresProgramCounter(for algorithm: AlgorithmModel) -> Bool {
        guard !algorithm.processes.isEmpty, algorithm.procedures.isEmpty else {
            return true
        }
        return !algorithm.processes.allSatisfy { process in
            guard process.steps.count == 1,
                  let loopCondition = process.steps.first?.loopCondition,
                  case .value(.bool(true)) = loopCondition
            else {
                return false
            }
            return !containsControlTransfer(process.steps[0].statements)
        }
    }

    private static func containsControlTransfer(_ statements: [AlgorithmStatementModel]) -> Bool {
        statements.contains { statement in
            switch statement {
            case .assert, .goto, .call, .return, .stop:
                return true
            case .letBinding(_, _, let body), .with(_, _, let body), .choose(_, _, let body):
                return containsControlTransfer(body)
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                return containsControlTransfer(then) || containsControlTransfer(otherwise)
            case .await, .set, .skip:
                return false
            }
        }
    }

    /// Lowers a PlusCal `begin ... end algorithm` body. This is deliberately
    /// not a one-element process: PlusCal gives this form a scalar `pc` and
    /// unparameterized action labels.
    private static func lowerSequential(
        _ algorithm: AlgorithmModel,
        formalOperatorDefinitions: [FormalOperatorDefinition]
    ) throws -> TLASpec {
        let steps = algorithm.sequentialSteps
        let procedures = algorithm.procedures
        let shared = algorithm.components.compactMap { component -> AlgorithmStateModel? in
            guard case .shared(let state) = component else { return nil }
            return state
        }
        let declaredInvariants = algorithm.components.compactMap { component -> NamedInvariant? in
            guard case .invariant(let invariant) = component else { return nil }
            return invariant
        }
        let declaredTemporal = algorithm.components.compactMap { component -> NamedTemporal? in
            guard case .temporal(let temporal) = component else { return nil }
            return temporal
        }
        let declaredFairness = algorithm.components.compactMap { component -> FairnessCondition? in
            guard case .fairness(let fairness) = component else { return nil }
            return fairness
        }
        let declaredConstraint = algorithm.components.compactMap { component -> StateExpr? in
            guard case .stateConstraint(let constraint) = component else { return nil }
            return constraint
        }.reduce(nil) { partial, constraint in
            partial.map { .and($0, constraint) } ?? constraint
        }

        let sharedVariables = shared.map { state in
            if let initial = try? state.initial.evaluate(
                in: [:],
                formalOperatorDefinitions: formalOperatorDefinitions
            ) {
                NamedVar(name: state.root, initial: initial, initialSet: state.initialSet)
            } else {
                NamedVar(name: state.root, initial: .int(0), initExpr: state.initial)
            }
        }
        var procedureVariables: [NamedVar] = []
        for procedure in procedures {
            for parameter in procedure.parameters {
                procedureVariables.append(NamedVar(
                    name: parameter.root,
                    initial: try staticInitialValue(
                        parameter.initial,
                        named: parameter.root,
                        formalOperatorDefinitions: formalOperatorDefinitions
                    )
                ))
            }
            for local in procedure.locals {
                procedureVariables.append(NamedVar(
                    name: local.root,
                    initial: try staticInitialValue(
                        local.initial,
                        named: local.root,
                        formalOperatorDefinitions: formalOperatorDefinitions
                    )
                ))
            }
        }
        guard let first = steps.first else {
            return TLASpec(
                name: algorithm.name,
                variables: sharedVariables + procedureVariables,
                actions: [],
                invariants: declaredInvariants,
                temporalProperties: declaredTemporal,
                fairness: declaredFairness,
                definitions: algorithm.formalOperatorDefinitions.map {
                    .init(name: $0.name, text: FormalOperatorDecl($0).tlaText, dependencies: $0.plusCalDependencies)
                },
                constraint: declaredConstraint,
                formalOperatorDefinitions: formalOperatorDefinitions,
                sourceAlgorithms: [Algorithm(model: algorithm)]
            )
        }
        // Match PlusCal's declaration order so TLC emits comparable frame
        // records in its retained DOT graph.
        var variables = [NamedVar(name: controlVariable, initial: .string(first.label.name))]
            + sharedVariables
        if !procedures.isEmpty {
            variables.append(NamedVar(name: stackVariable, initial: .tuple([])))
        }
        variables += procedureVariables
        let variableNames = variables.map(\.name)

        var actions: [NamedAction] = []
        var generatedAssertionInvariants: [NamedInvariant] = []
        let actionSources = [(steps, Optional<AlgorithmProcedureModel>.none)]
            + procedures.map { ($0.steps, Optional($0)) }
        for (sourceSteps, owner) in actionSources {
            for (index, atomic) in sourceSteps.enumerated() {
            let nextLabel = sourceSteps.indices.contains(index + 1)
                ? emittedLabel(sourceSteps[index + 1].label.name, owner: owner)
                : (owner == nil ? doneLabel : emittedLabel(doneLabel, owner: owner))
            let label = emittedLabel(atomic.label.name, owner: owner)
            let statements = lowerSequential(
                atomic.statements,
                nextLabel: nextLabel,
                procedures: procedures,
                owner: owner
            )
            let body: ActionExpr
            if let condition = atomic.loopCondition {
                body = .ifElse(
                    condition,
                    completingSequentialControl(statements, fallthrough: label),
                    sequentialTransfer(to: nextLabel)
                )
            } else {
                body = completingSequentialControl(statements, fallthrough: nextLabel)
            }
            actions.append(NamedAction(
                name: label,
                body: completeAction(
                    .and(.guard_(.equal(.variable(controlVariable), .value(.string(label)))), body),
                    allVars: variableNames
                )
            ))
            generatedAssertionInvariants += sequentialAssertionInvariants(
                in: atomic.statements,
                label: label,
                executionCondition: atomic.loopCondition,
                pathCondition: .value(.bool(true))
            )
            }
        }

        let terminate = variableNames
            .map(ActionExpr.unchanged)
            .reduce(
                .guard_(.equal(.variable(controlVariable), .value(.string(doneLabel)))),
                ActionExpr.and
            )
        actions.append(NamedAction(name: terminatingAction, body: terminate))

        return TLASpec(
            name: algorithm.name,
            variables: variables,
            actions: actions,
            invariants: declaredInvariants + generatedAssertionInvariants,
            temporalProperties: declaredTemporal,
            fairness: declaredFairness,
            definitions: algorithm.formalOperatorDefinitions.map {
                .init(name: $0.name, text: FormalOperatorDecl($0).tlaText, dependencies: $0.plusCalDependencies)
            },
            constraint: declaredConstraint,
            formalOperatorDefinitions: formalOperatorDefinitions,
            sourceAlgorithms: [Algorithm(model: algorithm)]
        )
    }

    private static func sequentialTransfer(to label: String) -> ActionExpr {
        .assign(controlVariable, .value(.string(label)))
    }

    private static func emittedLabel(_ label: String, owner: AlgorithmProcedureModel?) -> String {
        guard let owner else { return label }
        return "procedure.\(owner.name).\(label)"
    }

    private static func completingSequentialControl(_ action: ActionExpr, fallthrough label: String) -> ActionExpr {
        let branches = distributeOr(action)
        let completed = branches.map { branch in
            assignedVars(branch).contains(controlVariable)
                ? branch
                : .and(branch, sequentialTransfer(to: label))
        }
        return completed.dropFirst().reduce(completed.first ?? sequentialTransfer(to: label), ActionExpr.or)
    }

    private static func lowerSequential(
        _ statements: [AlgorithmStatementModel],
        nextLabel: String,
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?
    ) -> ActionExpr {
        var result = ActionExpr.guard_(.value(.bool(true)))
        var index = 0
        while index < statements.count {
            if case .call(let target, let arguments) = statements[index],
               index + 1 < statements.count,
               case .return = statements[index + 1] {
                result = .and(result, tailCallAction(target: target, arguments: arguments, procedures: procedures))
                index += 2
            } else {
                result = .and(result, lowerSequential(
                    statements[index],
                    nextLabel: nextLabel,
                    procedures: procedures,
                    owner: owner
                ))
                index += 1
            }
        }
        return result
    }

    private static func lowerSequential(
        _ statement: AlgorithmStatementModel,
        nextLabel: String,
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?
    ) -> ActionExpr {
        switch statement {
        case .await(let condition): return .guard_(condition)
        case .assert: return .guard_(.value(.bool(true)))
        case .set(let target, let value):
            switch target {
            case .root(let root): return .assign(root, value)
            case .function(let root, let key): return .assign(root, .except(.variable(root), key, value))
            }
        case .letBinding(let variable, let value, let body):
            return .define(variable, value, lowerSequential(body, nextLabel: nextLabel, procedures: procedures, owner: owner))
        case .with(let variable, let source, let body):
            return .existsAction(variable, source, lowerSequential(body, nextLabel: nextLabel, procedures: procedures, owner: owner))
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(condition, lowerSequential(then, nextLabel: nextLabel, procedures: procedures, owner: owner), lowerSequential(otherwise, nextLabel: nextLabel, procedures: procedures, owner: owner))
        case .either(let first, let second):
            return .or(lowerSequential(first, nextLabel: nextLabel, procedures: procedures, owner: owner), lowerSequential(second, nextLabel: nextLabel, procedures: procedures, owner: owner))
        case .choose(let variable, let domain, let body):
            return .existsAction(variable, .setLiteral(domain.map(StateExpr.value)), lowerSequential(body, nextLabel: nextLabel, procedures: procedures, owner: owner))
        case .goto(let label): return sequentialTransfer(to: emittedLabel(label.name, owner: owner))
        case .call(let target, let arguments):
            return callAction(target: target, arguments: arguments, returnTo: nextLabel, procedures: procedures)
        case .return:
            return returnAction(owner: owner, procedures: procedures)
        case .stop: return sequentialTransfer(to: doneLabel)
        case .skip: return .guard_(.value(.bool(true)))
        }
    }

    private static func callAction(
        target: String,
        arguments: [StateExpr],
        returnTo: String,
        procedures: [AlgorithmProcedureModel]
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        // A frame captures every procedure-owned slot, not only the callee's.
        // That makes a tail call safe: it reuses the caller's continuation and
        // return restores the entire pre-call procedural environment at once.
        let frameFields = [
            (procedureField, StateExpr.value(.string(procedure.name))),
            (returnPCField, StateExpr.value(.string(returnTo)))
        ]
            + procedureSlots(procedures).map { ($0.root, StateExpr.variable($0.root)) }
        let push = ActionExpr.assign(
            stackVariable,
            .tupleConcatenate(.tupleLiteral([.recordLiteral(Dictionary(uniqueKeysWithValues: frameFields))]), .variable(stackVariable))
        )
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign($0.0.root, $0.1)
        }
        let localAssignments = procedure.locals.map { ActionExpr.assign($0.root, $0.initial) }
        return (parameterAssignments + localAssignments + [push, sequentialTransfer(to: emittedLabel(entry, owner: procedure))])
            .reduce(.guard_(.value(.bool(true))), ActionExpr.and)
    }

    private static func returnAction(
        owner: AlgorithmProcedureModel?,
        procedures: [AlgorithmProcedureModel]
    ) -> ActionExpr {
        guard owner != nil else { return .guard_(.value(.bool(false))) }
        let stack = StateExpr.variable(stackVariable)
        let frame = StateExpr.tupleHead(stack)
        let restore = (procedureSlots(procedures).map { ActionExpr.assign($0.root, .recordAccess(frame, $0.root)) }
            + [
                .assign(stackVariable, .tupleTail(stack)),
                .assign(controlVariable, .recordAccess(frame, returnPCField))
            ])
        return restore.reduce(
            .guard_(.greaterThan(.tupleLength(stack), .int(0))),
            ActionExpr.and
        )
    }

    private static func tailCallAction(
        target: String,
        arguments: [StateExpr],
        procedures: [AlgorithmProcedureModel]
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign($0.0.root, $0.1)
        }
        let localAssignments = procedure.locals.map { ActionExpr.assign($0.root, $0.initial) }
        return (parameterAssignments + localAssignments + [sequentialTransfer(to: emittedLabel(entry, owner: procedure))])
            .reduce(.guard_(.value(.bool(true))), ActionExpr.and)
    }

    private static func processCallAction(
        target: String,
        arguments: [StateExpr],
        returnTo: String,
        procedures: [AlgorithmProcedureModel]
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        let process = StateExpr.variable(processBinding)
        let stack = StateExpr.functionApply(.variable(stackVariable), process)
        let frameFields = [
            (procedureField, StateExpr.value(.string(procedure.name))),
            (returnPCField, StateExpr.value(.string(returnTo)))
        ]
            + procedureSlots(procedures).map {
                ($0.root, StateExpr.functionApply(.variable($0.root), process))
            }
        let push = ActionExpr.assign(
            stackVariable,
            .except(
                .variable(stackVariable),
                process,
                .tupleConcatenate(.tupleLiteral([.recordLiteral(Dictionary(uniqueKeysWithValues: frameFields))]), stack)
            )
        )
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign($0.0.root, .except(.variable($0.0.root), process, $0.1))
        }
        let localRoots = Set(procedureSlots(procedures).map(\.root))
        let localAssignments = procedure.locals.map {
            ActionExpr.assign($0.root, .except(.variable($0.root), process, rewrite($0.initial, localRoots: localRoots)))
        }
        return (parameterAssignments + localAssignments + [push, transfer(to: emittedLabel(entry, owner: procedure))])
            .reduce(.guard_(.value(.bool(true))), ActionExpr.and)
    }

    private static func processReturnAction(
        owner: AlgorithmProcedureModel?,
        procedures: [AlgorithmProcedureModel]
    ) -> ActionExpr {
        guard owner != nil else { return .guard_(.value(.bool(false))) }
        let process = StateExpr.variable(processBinding)
        let stack = StateExpr.functionApply(.variable(stackVariable), process)
        let frame = StateExpr.tupleHead(stack)
        let restore = procedureSlots(procedures).map {
            ActionExpr.assign($0.root, .except(.variable($0.root), process, .recordAccess(frame, $0.root)))
        } + [
            .assign(stackVariable, .except(.variable(stackVariable), process, .tupleTail(stack))),
            transfer(toExpression: .recordAccess(frame, returnPCField))
        ]
        return restore.reduce(
            .guard_(.greaterThan(.tupleLength(stack), .int(0))),
            ActionExpr.and
        )
    }

    private static func processTailCallAction(
        target: String,
        arguments: [StateExpr],
        procedures: [AlgorithmProcedureModel]
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        let process = StateExpr.variable(processBinding)
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign($0.0.root, .except(.variable($0.0.root), process, $0.1))
        }
        let localRoots = Set(procedureSlots(procedures).map(\.root))
        let localAssignments = procedure.locals.map {
            ActionExpr.assign($0.root, .except(.variable($0.root), process, rewrite($0.initial, localRoots: localRoots)))
        }
        return (parameterAssignments + localAssignments + [transfer(to: emittedLabel(entry, owner: procedure))])
            .reduce(.guard_(.value(.bool(true))), ActionExpr.and)
    }

    private static func procedureSlots(
        _ procedures: [AlgorithmProcedureModel]
    ) -> [(root: String, initial: StateExpr)] {
        procedures.flatMap { procedure in
            procedure.parameters.map { ($0.root, $0.initial) }
                + procedure.locals.map { ($0.root, $0.initial) }
        }
    }

    private static func sequentialAssertionInvariants(
        in statements: [AlgorithmStatementModel],
        label: String,
        executionCondition: StateExpr?,
        pathCondition: StateExpr
    ) -> [NamedInvariant] {
        let atLabel = StateExpr.equal(.variable(controlVariable), .value(.string(label)))
        let executed = StateExpr.and(executionCondition.map { .and(atLabel, $0) } ?? atLabel, pathCondition)
        return statements.enumerated().flatMap { index, statement in
            switch statement {
            case .assert(let condition):
                return [NamedInvariant(
                    name: "__pcal_assert_\(label)_\(index)",
                    body: .or(.not(executed), condition)
                )]
            case .ifElse(let condition, let then, let otherwise):
                return sequentialAssertionInvariants(in: then, label: label, executionCondition: executionCondition, pathCondition: .and(pathCondition, condition))
                    + sequentialAssertionInvariants(in: otherwise, label: label, executionCondition: executionCondition, pathCondition: .and(pathCondition, .not(condition)))
            case .either(let first, let second):
                return sequentialAssertionInvariants(in: first, label: label, executionCondition: executionCondition, pathCondition: pathCondition)
                    + sequentialAssertionInvariants(in: second, label: label, executionCondition: executionCondition, pathCondition: pathCondition)
            case .choose(let variable, let domain, let body):
                return sequentialAssertionInvariants(in: body, label: label, executionCondition: executionCondition, pathCondition: pathCondition)
                    .map { invariant in
                        NamedInvariant(name: invariant.name, body: .forAll(.setLiteral(domain.map(StateExpr.value)), variable, invariant.body))
                    }
            case .letBinding(let variable, let value, let body):
                return sequentialAssertionInvariants(
                    in: body.map { substituteAlgorithmVariable($0, name: variable, with: value) },
                    label: label,
                    executionCondition: executionCondition,
                    pathCondition: pathCondition
                )
            case .with(let variable, let source, let body):
                return sequentialAssertionInvariants(in: body, label: label, executionCondition: executionCondition, pathCondition: pathCondition)
                    .map { invariant in
                        NamedInvariant(name: invariant.name, body: .forAll(source, variable, invariant.body))
                    }
            case .await, .set, .goto, .call, .return, .stop, .skip: return []
            }
        }
    }

    /// Algorithm declarations are finite initial values. Keep the initial
    /// state concrete so the checker, parser tree, and generated State agree.
    private static func staticInitialValue(
        _ expression: StateExpr,
        named name: String,
        formalOperatorDefinitions: [FormalOperatorDefinition]
    ) throws -> TLAValue {
        do {
            return try expression.evaluate(
                in: [:],
                formalOperatorDefinitions: formalOperatorDefinitions
            )
        } catch {
            throw AlgorithmLoweringError.nonStaticInitialValue(name: name, underlying: error)
        }
    }

    private static func lower(
        _ statements: [AlgorithmStatementModel],
        localRoots: Set<String>,
        processDomain: [TLAValue],
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?,
        nextLabel: String
    ) -> ActionExpr {
        var result = ActionExpr.guard_(.value(.bool(true)))
        var index = 0
        while index < statements.count {
            if case .call(let target, let arguments) = statements[index],
               index + 1 < statements.count,
               case .return = statements[index + 1] {
                result = .and(result, processTailCallAction(
                    target: target,
                    arguments: arguments.map { rewrite($0, localRoots: localRoots) },
                    procedures: procedures
                ))
                index += 2
            } else {
                result = .and(result, lower(
                    statements[index],
                    localRoots: localRoots,
                    processDomain: processDomain,
                    procedures: procedures,
                    owner: owner,
                    nextLabel: nextLabel
                ))
                index += 1
            }
        }
        return result
    }

    private static func stopAction() -> ActionExpr {
        transfer(to: doneLabel)
    }

    private static func transfer(to label: String) -> ActionExpr {
        transfer(toExpression: .value(.string(label)))
    }

    private static func transfer(toExpression label: StateExpr) -> ActionExpr {
        .assign(
            controlVariable,
            .except(
                .variable(controlVariable),
                .variable(processBinding),
                label))
    }

    /// An `Each` machine continues to its next `Do` when it does not explicitly
    /// transfer control. Its final `Do` reaches the builder-owned `Done` state.
    private static func completingControl(_ action: ActionExpr, fallthrough label: String) -> ActionExpr {
        let branches = distributeOr(action)
        let completed = branches.map { branch in
            assignedVars(branch).contains(controlVariable)
                ? branch
                : .and(branch, transfer(to: label))
        }
        return completed.dropFirst().reduce(completed.first ?? transfer(to: label), ActionExpr.or)
    }

    private static func lower(
        _ statement: AlgorithmStatementModel,
        localRoots: Set<String>,
        processDomain: [TLAValue],
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?,
        nextLabel: String
    ) -> ActionExpr {
        switch statement {
        case .await(let condition):
            return .guard_(rewrite(condition, localRoots: localRoots))
        case .assert:
            // `Assert` is checked through a generated invariant at its program
            // location. It remains a no-op in the transition relation.
            return .guard_(.value(.bool(true)))
        case .set(let target, let value):
            let value = rewrite(value, localRoots: localRoots)
            switch target {
            case .root(let root) where localRoots.contains(root):
                return .assign(
                    root,
                    .except(.variable(root), .variable(processBinding), value))
            case .root(let root):
                return .assign(root, value)
            case .function(let root, let key):
                return .assign(
                    root,
                    .except(
                        .variable(root),
                        rewrite(key, localRoots: localRoots),
                        value))
            }
        case .letBinding(let variable, let value, let body):
            return .define(
                variable,
                rewrite(value, localRoots: localRoots),
                lower(body, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel)
            )
        case .with(let variable, let source, let body):
            return .existsAction(
                variable,
                rewrite(source, localRoots: localRoots),
                lower(body, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel))
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(
                rewrite(condition, localRoots: localRoots),
                lower(then, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel),
                lower(otherwise, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel))
        case .either(let first, let second):
            return .or(
                lower(first, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel),
                lower(second, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel))
        case .choose(let variable, let domain, let body):
            return .existsAction(
                variable,
                .setLiteral(domain.map { .value($0) }),
                lower(body, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel))
        case .goto(let label):
            return transfer(to: emittedLabel(label.name, owner: owner))
        case .call(let target, let arguments):
            return processCallAction(
                target: target,
                arguments: arguments.map { rewrite($0, localRoots: localRoots) },
                returnTo: nextLabel,
                procedures: procedures
            )
        case .return:
            return processReturnAction(owner: owner, procedures: procedures)
        case .stop:
            return stopAction()
        case .skip:
            return .guard_(.value(.bool(true)))
        }
    }

    private static func assertionInvariants(
        in statements: [AlgorithmStatementModel],
        process: AlgorithmProcessModel,
        label: String,
        localRoots: Set<String>,
        executionCondition: StateExpr?,
        pathCondition: StateExpr,
        quantifiedBindings: [(variable: String, source: StateExpr)]
    ) -> [NamedInvariant] {
        let pcAtLabel = StateExpr.equal(
            .functionApply(.variable(controlVariable), .variable(processBinding)),
            .value(.string(label))
        )
        let executedAtLabel = StateExpr.and(
            executionCondition.map { .and(pcAtLabel, $0) } ?? pcAtLabel,
            pathCondition
        )
        return statements.enumerated().flatMap { statementIndex, statement in
            switch statement {
            case .assert(let condition):
                return process.domain.enumerated().map { offset, identifier in
                    let assertion = quantifiedBindings.reversed().reduce(
                        rewrite(condition, localRoots: localRoots)
                    ) { predicate, binding in
                        .forAll(
                            rewrite(binding.source, localRoots: localRoots),
                            binding.variable,
                            predicate
                        )
                    }
                    let predicate = StateExpr.substituteVariable(
                        processBinding,
                        identifier,
                        in: .or(.not(executedAtLabel), assertion)
                    )
                    return NamedInvariant(
                        name: "__pcal_assert_\(label)_\(statementIndex)_\(offset)",
                        body: predicate
                    )
                }
            case .ifElse(let condition, let then, let otherwise):
                let condition = rewrite(condition, localRoots: localRoots)
                return assertionInvariants(
                    in: then,
                    process: process,
                    label: label,
                    localRoots: localRoots,
                    executionCondition: executionCondition,
                    pathCondition: .and(pathCondition, condition),
                    quantifiedBindings: quantifiedBindings
                ) + assertionInvariants(
                    in: otherwise,
                    process: process,
                    label: label,
                    localRoots: localRoots,
                    executionCondition: executionCondition,
                    pathCondition: .and(pathCondition, .not(condition)),
                    quantifiedBindings: quantifiedBindings
                )
            case .either(let then, let otherwise):
                return assertionInvariants(in: then, process: process, label: label, localRoots: localRoots, executionCondition: executionCondition, pathCondition: pathCondition, quantifiedBindings: quantifiedBindings)
                    + assertionInvariants(in: otherwise, process: process, label: label, localRoots: localRoots, executionCondition: executionCondition, pathCondition: pathCondition, quantifiedBindings: quantifiedBindings)
            case .choose(let variable, let domain, let body):
                return assertionInvariants(
                    in: body,
                    process: process,
                    label: label,
                    localRoots: localRoots,
                    executionCondition: executionCondition,
                    pathCondition: pathCondition,
                    quantifiedBindings: quantifiedBindings + [(variable, .setLiteral(domain.map(StateExpr.value)))]
                )
            case .letBinding(let variable, let value, let body):
                return assertionInvariants(
                    in: body.map {
                        substituteAlgorithmVariable(
                            $0,
                            name: variable,
                            with: rewrite(value, localRoots: localRoots)
                        )
                    },
                    process: process,
                    label: label,
                    localRoots: localRoots,
                    executionCondition: executionCondition,
                    pathCondition: pathCondition,
                    quantifiedBindings: quantifiedBindings
                )
            case .with(let variable, let source, let body):
                return assertionInvariants(
                    in: body,
                    process: process,
                    label: label,
                    localRoots: localRoots,
                    executionCondition: executionCondition,
                    pathCondition: pathCondition,
                    quantifiedBindings: quantifiedBindings + [(variable, source)]
                )
            case .await, .set, .goto, .call, .return, .stop, .skip:
                return []
            }
        }
    }

    private static func fairnessConditions(
        for action: NamedAction,
        policy: AlgorithmFairness
    ) -> [FairnessCondition] {
        switch policy {
        case .none:
            []
        case .weak:
            actionInvocations(action).map { .weakFairnessInvocation($0.invocation) }
        case .strong:
            actionInvocations(action).map { .strongFairnessInvocation($0.invocation) }
        }
    }

    private static func uniquelyNamed(_ invariants: [NamedInvariant]) -> [NamedInvariant] {
        var occurrences: [String: Int] = [:]
        return invariants.map { invariant in
            let occurrence = occurrences[invariant.name, default: 0]
            occurrences[invariant.name] = occurrence + 1
            guard occurrence > 0 else { return invariant }
            return NamedInvariant(name: "\(invariant.name)_\(occurrence)", body: invariant.body)
        }
    }

    /// Replaces a deterministic `Let` binding while deriving an assertion
    /// invariant. Action lowering keeps the binding as `LET ... IN`; an
    /// invariant is a state expression, so it needs the equivalent scoped
    /// substitution instead.
    private static func substituteAlgorithmVariable(
        _ statement: AlgorithmStatementModel,
        name: String,
        with replacement: StateExpr
    ) -> AlgorithmStatementModel {
        func expression(_ value: StateExpr) -> StateExpr {
            StateExpr.substituteVariable(name, with: replacement, in: value)
        }
        switch statement {
        case .await(let value): return .await(expression(value))
        case .assert(let value): return .assert(expression(value))
        case .set(let target, let value):
            let rewrittenTarget: AlgorithmLValueModel
            switch target {
            case .root: rewrittenTarget = target
            case .function(let root, let key):
                rewrittenTarget = .function(root: root, key: expression(key))
            }
            return .set(target: rewrittenTarget, value: expression(value))
        case .letBinding(let variable, let value, let body):
            return .letBinding(
                variable: variable,
                value: expression(value),
                variable == name
                    ? body
                    : body.map { substituteAlgorithmVariable($0, name: name, with: replacement) }
            )
        case .with(let variable, let source, let body):
            return .with(
                variable: variable,
                source: expression(source),
                variable == name
                    ? body
                    : body.map { substituteAlgorithmVariable($0, name: name, with: replacement) }
            )
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(
                expression(condition),
                then.map { substituteAlgorithmVariable($0, name: name, with: replacement) },
                otherwise.map { substituteAlgorithmVariable($0, name: name, with: replacement) }
            )
        case .either(let first, let second):
            return .either(
                first.map { substituteAlgorithmVariable($0, name: name, with: replacement) },
                second.map { substituteAlgorithmVariable($0, name: name, with: replacement) }
            )
        case .choose(let variable, let domain, let body):
            return .choose(
                variable: variable,
                domain: domain,
                variable == name
                    ? body
                    : body.map { substituteAlgorithmVariable($0, name: name, with: replacement) }
            )
        case .call(let target, let arguments): return .call(target: target, arguments: arguments.map(expression))
        case .goto, .return, .stop, .skip: return statement
        }
    }

    private static func rewrite(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
        func rewritten(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
            switch expression {
            case .value:
                return expression
            case .variable(let name):
                if name == builderProcessIdentifier { return .variable(processBinding) }
                if name.hasPrefix(algorithmLocalFamilyPrefix) {
                    let root = String(name.dropFirst(algorithmLocalFamilyPrefix.count))
                    return localRoots.contains(root) ? .variable(root) : expression
                }
                if localRoots.contains(name) {
                    return .functionApply(.variable(name), .variable(processBinding))
                }
                return expression
            case .add(let lhs, let rhs): return .add(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .subtract(let lhs, let rhs): return .subtract(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .multiply(let lhs, let rhs): return .multiply(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .divide(let lhs, let rhs): return .divide(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .modulo(let lhs, let rhs): return .modulo(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .negate(let value): return .negate(rewritten(value, localRoots: localRoots))
            case .integerDivide(let lhs, let rhs): return .integerDivide(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .equal(let lhs, let rhs): return .equal(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .notEqual(let lhs, let rhs): return .notEqual(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .lessThan(let lhs, let rhs): return .lessThan(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .lessOrEqual(let lhs, let rhs): return .lessOrEqual(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .greaterThan(let lhs, let rhs): return .greaterThan(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .greaterOrEqual(let lhs, let rhs): return .greaterOrEqual(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .and(let lhs, let rhs): return .and(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .or(let lhs, let rhs): return .or(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .not(let value): return .not(rewritten(value, localRoots: localRoots))
            case .ifThenElse(let condition, let then, let otherwise):
                return .ifThenElse(rewritten(condition, localRoots: localRoots), rewritten(then, localRoots: localRoots), rewritten(otherwise, localRoots: localRoots))
            case .setLiteral(let elements): return .setLiteral(elements.map { rewritten($0, localRoots: localRoots) })
            case .in(let value, let set): return .in(rewritten(value, localRoots: localRoots), rewritten(set, localRoots: localRoots))
            case .subset(let lhs, let rhs): return .subset(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .union(let lhs, let rhs): return .union(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .intersection(let lhs, let rhs): return .intersection(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .setDifference(let lhs, let rhs): return .setDifference(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .cardinality(let set): return .cardinality(rewritten(set, localRoots: localRoots))
            case .setFilter(let set, let variable, let predicate):
                return .setFilter(rewritten(set, localRoots: localRoots), variable, rewritten(predicate, localRoots: localRoots.subtracting([variable])))
            case .setMap(let value, let variable, let set):
                return .setMap(rewritten(value, localRoots: localRoots.subtracting([variable])), variable, rewritten(set, localRoots: localRoots))
            case .powerSet(let set): return .powerSet(rewritten(set, localRoots: localRoots))
            case .unionAll(let set): return .unionAll(rewritten(set, localRoots: localRoots))
            case .integerRange(let lower, let upper): return .integerRange(rewritten(lower, localRoots: localRoots), rewritten(upper, localRoots: localRoots))
            case .tupleLiteral(let elements): return .tupleLiteral(elements.map { rewritten($0, localRoots: localRoots) })
            case .tupleAccess(let tuple, let index): return .tupleAccess(rewritten(tuple, localRoots: localRoots), index)
            case .tupleDynamicAccess(let tuple, let index): return .tupleDynamicAccess(rewritten(tuple, localRoots: localRoots), rewritten(index, localRoots: localRoots))
            case .tupleLength(let tuple): return .tupleLength(rewritten(tuple, localRoots: localRoots))
            case .tupleAppend(let tuple, let value): return .tupleAppend(rewritten(tuple, localRoots: localRoots), rewritten(value, localRoots: localRoots))
            case .tupleHead(let tuple): return .tupleHead(rewritten(tuple, localRoots: localRoots))
            case .tupleTail(let tuple): return .tupleTail(rewritten(tuple, localRoots: localRoots))
            case .tupleConcatenate(let lhs, let rhs): return .tupleConcatenate(rewritten(lhs, localRoots: localRoots), rewritten(rhs, localRoots: localRoots))
            case .recordLiteral(let fields): return .recordLiteral(fields.mapValues { rewritten($0, localRoots: localRoots) })
            case .recordAccess(let record, let field): return .recordAccess(rewritten(record, localRoots: localRoots), field)
            case .domain(let function): return .domain(rewritten(function, localRoots: localRoots))
            case .functionLiteral(let domain, let variable, let body):
                return .functionLiteral(rewritten(domain, localRoots: localRoots), variable, rewritten(body, localRoots: localRoots.subtracting([variable])))
            case .functionApply(let function, let argument): return .functionApply(rewritten(function, localRoots: localRoots), rewritten(argument, localRoots: localRoots))
            case .except(let function, let key, let value):
                return .except(rewritten(function, localRoots: localRoots), rewritten(key, localRoots: localRoots), rewritten(value, localRoots: localRoots))
            case .caseExpr(let cases, let fallback):
                return .caseExpr(cases.map { rewritten($0, localRoots: localRoots) }, fallback.map { rewritten($0, localRoots: localRoots) })
            case .forAll(let set, let variable, let predicate):
                return .forAll(rewritten(set, localRoots: localRoots), variable, rewritten(predicate, localRoots: localRoots.subtracting([variable])))
            case .exists(let set, let variable, let predicate):
                return .exists(rewritten(set, localRoots: localRoots), variable, rewritten(predicate, localRoots: localRoots.subtracting([variable])))
            case .choose(let set, let variable, let predicate):
                return .choose(rewritten(set, localRoots: localRoots), variable, rewritten(predicate, localRoots: localRoots.subtracting([variable])))
            case .enabledAction:
                return expression
            case .sequenceFromSet(let set): return .sequenceFromSet(rewritten(set, localRoots: localRoots))
            case .setSum(let function, let set): return .setSum(rewritten(function, localRoots: localRoots), rewritten(set, localRoots: localRoots))
            case .functionSet(let domain, let range): return .functionSet(rewritten(domain, localRoots: localRoots), rewritten(range, localRoots: localRoots))
            case .foldFunction(let operation, let initial, let sequence):
                return .foldFunction(
                    FormalLambda(
                        parameters: operation.parameters,
                        body: rewritten(
                            operation.body,
                            localRoots: localRoots.subtracting(operation.parameters)
                        )
                    ),
                    initial: rewritten(initial, localRoots: localRoots),
                    sequence: rewritten(sequence, localRoots: localRoots)
                )
            case .operatorApplication(let operation, let arguments):
                let rewrittenOperator: FormalOperator
                switch operation {
                case .lambda(let lambda):
                    rewrittenOperator = .lambda(
                        FormalLambda(
                            parameters: lambda.parameters,
                            body: rewritten(
                                lambda.body,
                                localRoots: localRoots.subtracting(lambda.parameters)
                            )
                        )
                    )
                case .reference:
                    rewrittenOperator = operation
                }
                return .operatorApplication(
                    rewrittenOperator,
                    arguments.map { argument in
                        switch argument {
                        case .value(let value):
                            .value(rewritten(value, localRoots: localRoots))
                        case .operator(.reference(let name, let arity)):
                            .operator(.reference(name, arity: arity))
                        case .operator(.lambda(let lambda)):
                            .operator(.lambda(FormalLambda(
                                parameters: lambda.parameters,
                                body: rewritten(lambda.body, localRoots: localRoots)
                            )))
                        }
                    }
                )
            case .recursiveCall(let name, let arguments): return .recursiveCall(name, arguments.map { rewritten($0, localRoots: localRoots) })
            case .letValue(let name, let value, let body):
                return .letValue(
                    name,
                    rewritten(value, localRoots: localRoots),
                    rewritten(body, localRoots: localRoots.subtracting([name]))
                )
            case .letIn(let operators, let body):
                return .letIn(
                    operators.map { operation in
                        LocalOperator(
                            operation.name,
                            parameters: operation.parameters,
                            domain: operation.domain.map { rewritten($0, localRoots: localRoots) },
                            body: rewritten(
                                operation.body,
                                localRoots: localRoots.subtracting(operation.parameters)
                            )
                        )
                    },
                    rewritten(body, localRoots: localRoots)
                )
            }
        }

        return rewritten(expression, localRoots: localRoots)
    }
}
