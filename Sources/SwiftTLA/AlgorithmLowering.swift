enum AlgorithmLowerer {
    private enum CompilerBindingSymbol: String, Sendable {
        case process
    }

    // These frame keys are the names emitted by the official PlusCal
    // translator.  The runtime stack remains an implementation detail, but
    // its formal representation must be comparable to the independent
    // translation rather than merely equivalent by convention.

    private struct ControlFlow {
        let algorithm: String
        let owner: ControlOwner

        func location(_ sourceName: String) -> StateExpr {
            .controlLocation(.init(owner: owner, sourceName: sourceName))
        }

        func procedure(_ procedure: AlgorithmProcedureModel, location sourceName: String) -> StateExpr {
            .controlLocation(.init(
                owner: .procedure(algorithm: algorithm, name: procedure.name),
                sourceName: sourceName
            ))
        }
    }
    private static let processBinding = CompilerBindingSymbol.process
    private static func lowered(_ specification: TLASpec) -> TLASpec {
        var specification = specification
        specification.algorithmPhase = .lowered
        return specification
    }

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
                        processBinding.rawValue,
                        rewrite(invariant.body, localRoots: localRoots)
                    )
                )
            }
        }
        let declaredTemporal = algorithm.components.compactMap { component -> NamedTemporal? in
            guard case .temporal(let temporal) = component else { return nil }
            return temporal
        }
        let declaredConstraint = algorithm.components.compactMap { component -> StateExpr? in
            guard case .stateConstraint(let constraint) = component else { return nil }
            return constraint
        }.reduce(nil) { partial, constraint in
            partial.map { .and($0, constraint) } ?? constraint
        }

        var variables = shared.map { state in
            NamedVar(
                name: state.root,
                initial: .int(0),
                initialSet: state.initialSet,
                initExpr: state.initialSet == nil ? state.initial : nil
            )
        }
        for process in processes {
            for local in process.components {
                guard case .local(let state) = local else { continue }
                variables.append(
                    NamedVar(
                        name: state.root,
                        initial: .int(0),
                        initExpr: constantFunction(domain: process.domain, value: state.initial),
                        origin: .compiler
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
            let controlCases = processes.enumerated().flatMap { processIndex, process -> [StateExpr] in
                guard let first = process.steps.first else { return [] }
                let control = ControlFlow(
                    algorithm: algorithm.name,
                    owner: .process(algorithm: algorithm.name, ordinal: processIndex, typeName: process.typeName)
                )
                return [
                    .in(
                        .variable(controlBinding),
                        .setLiteral(process.domain.map(StateExpr.value))
                    ),
                    control.location(first.label.name)
                ]
            }
            variables.insert(NamedVar(
                name: CompilerControlSymbol.programCounter.rawValue,
                initial: .function([:]),
                initExpr: .functionLiteral(
                    controlDomain,
                    controlBinding,
                    .caseExpr(controlCases, nil)
                ),
                origin: .programCounter
            ), at: 0)
        }
        if !procedures.isEmpty {
            for slot in procedureSlots(procedures) {
                variables.append(NamedVar(
                    name: slot.root,
                    initial: .int(0),
                    initExpr: constantFunction(domain: controlDomainValues(processes), value: slot.initial),
                    origin: .compiler
                ))
            }
            variables.append(NamedVar(
                name: CompilerControlSymbol.stack.rawValue,
                initial: .int(0),
                initExpr: constantFunction(domain: controlDomainValues(processes), value: .tupleLiteral([])),
                origin: .compiler
            ))
        }

        let variableNames = variables.map(\.name)
        let localRoots = Set(localStates.map(\.root) + procedureSlots(procedures).map(\.root))
        var generatedAssertionInvariants: [NamedInvariant] = []
        var fairness: [FairnessCondition] = []
        var actions = processes.enumerated().flatMap { processIndex, process in
            process.steps.enumerated().map { index, atomic in
                let controlOwner = ControlOwner.process(
                    algorithm: algorithm.name,
                    ordinal: processIndex,
                    typeName: process.typeName
                )
                let control = ControlFlow(algorithm: algorithm.name, owner: controlOwner)
                let nextLabel = process.steps.indices.contains(index + 1)
                    ? control.location(process.steps[index + 1].label.name)
                    : .controlLocation(.init(
                        owner: .generated(algorithm: algorithm.name, purpose: CompilerControlSymbol.done.rawValue),
                        sourceName: CompilerControlSymbol.done.rawValue
                    ))
                let loweredStatements = lower(
                    atomic.statements,
                    localRoots: localRoots,
                    processDomain: process.domain,
                    procedures: procedures,
                    owner: nil,
                    nextLabel: nextLabel,
                    control: control
                )
                let body: ActionExpr
                if !requiresProgramCounter {
                    body = loweredStatements
                } else if let loopCondition = atomic.loopCondition {
                    body = .ifElse(
                        rewrite(loopCondition, localRoots: localRoots),
                        completingControl(loweredStatements, fallthrough: control.location(atomic.label.name)),
                        transfer(to: nextLabel)
                    )
                } else {
                    body = completingControl(loweredStatements, fallthrough: nextLabel)
                }
                let generatedAction = NamedAction(
                    name: requiresProgramCounter ? atomic.label.name : translatedProcessNames[processIndex],
                    body: ActionNormalization.complete(
                        requiresProgramCounter
                            ? .and(
                                .guard_(.equal(
                                .functionApply(.programCounter, .variable(processBinding.rawValue)),
                                    control.location(atomic.label.name)
                                )),
                                body
                            )
                            : body,
                        variables: variables
                    ),
                    bindings: [ActionBinding(name: processBinding.rawValue, values: process.domain)],
                    controlOwner: controlOwner,
                    generatedBindingSwiftTypes: [processBinding.rawValue: process.typeName]
                )
                if requiresProgramCounter {
                    let actionAssertions = assertionInvariants(
                        in: atomic.statements,
                        process: process,
                        label: control.location(atomic.label.name),
                        localRoots: localRoots,
                        executionCondition: atomic.loopCondition.map { rewrite($0, localRoots: localRoots) },
                        pathCondition: .value(.bool(true)),
                        quantifiedBindings: []
                    )
                    generatedAssertionInvariants += actionAssertions
                }
                fairness += fairnessConditions(for: generatedAction, policy: process.fairness)
                return generatedAction
            }
        }

        let procedureActions = procedures.flatMap { procedure in
            procedure.steps.enumerated().map { index, atomic in
                let control = ControlFlow(
                    algorithm: algorithm.name,
                    owner: .procedure(algorithm: algorithm.name, name: procedure.name)
                )
                let label = emittedLabel(atomic.label.name, owner: procedure)
                let nextLabel = procedure.steps.indices.contains(index + 1)
                    ? control.location(procedure.steps[index + 1].label.name)
                    : .controlLocation(.init(
                        owner: .generated(algorithm: algorithm.name, purpose: CompilerControlSymbol.done.rawValue),
                        sourceName: CompilerControlSymbol.done.rawValue
                    ))
                let guardExpression = StateExpr.equal(
                    .functionApply(.programCounter, .variable(processBinding.rawValue)),
                    control.location(atomic.label.name)
                )
                let loweredStatements = lower(
                    atomic.statements,
                    localRoots: localRoots,
                    processDomain: controlDomainValues(processes),
                    procedures: procedures,
                    owner: procedure,
                    nextLabel: nextLabel,
                    control: control
                )
                let body = completingControl(loweredStatements, fallthrough: nextLabel)
                return NamedAction(
                    name: label,
                    body: ActionNormalization.complete(.and(.guard_(guardExpression), body), variables: variables),
                    bindings: [ActionBinding(name: processBinding.rawValue, values: controlDomainValues(processes))],
                    controlOwner: .procedure(algorithm: algorithm.name, name: procedure.name)
                )
            }
        }
        actions += procedureActions

        if requiresProgramCounter {
            let allDone = processes.reduce(StateExpr.value(.bool(true))) { condition, process in
                let members = StateExpr.setLiteral(process.domain.map(StateExpr.value))
                let processDone = StateExpr.forAll(
                    members,
                    processBinding.rawValue,
                    .equal(
                        .functionApply(.programCounter, .variable(processBinding.rawValue)),
                        .controlLocation(.init(
                            owner: .generated(algorithm: algorithm.name, purpose: CompilerControlSymbol.done.rawValue),
                            sourceName: CompilerControlSymbol.done.rawValue
                        ))
                    )
                )
                return .and(condition, processDone)
            }
            let unchanged = variableNames
                .map { .unchanged(.named($0)) }
                .reduce(.guard_(allDone), ActionExpr.and)
            actions.append(NamedAction(name: CompilerControlSymbol.terminatingAction.rawValue, body: unchanged))
        }

        return lowered(TLASpec(
            name: algorithm.name,
            variables: variables,
            actions: actions,
            invariants: declaredInvariants + processInvariants
                + compilerOwnedAssertionInvariants(generatedAssertionInvariants),
            temporalProperties: declaredTemporal,
            fairness: fairness,
            constraint: declaredConstraint,
            formalOperatorDefinitions: resolvedFormalOperators,
            sourceAlgorithms: [Algorithm(model: algorithm)]))
    }

    private static func constantFunction(domain: [TLAValue], value: StateExpr) -> StateExpr {
        let binding = "__pcal_initial_process"
        return .functionLiteral(
            .setLiteral(domain.map(StateExpr.value)),
            binding,
            value.replacingCurrentProcess(with: .variable(binding))
        )
    }

    private static func controlDomainValues(_ processes: [AlgorithmProcessModel]) -> [TLAValue] {
        Array(Set(processes.flatMap(\.domain))).sorted()
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
            case .rejected:
                return true
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
        let declaredConstraint = algorithm.components.compactMap { component -> StateExpr? in
            guard case .stateConstraint(let constraint) = component else { return nil }
            return constraint
        }.reduce(nil) { partial, constraint in
            partial.map { .and($0, constraint) } ?? constraint
        }

        let sharedVariables = shared.map { state in
            NamedVar(
                name: state.root,
                initial: .int(0),
                initialSet: state.initialSet,
                initExpr: state.initialSet == nil ? state.initial : nil
            )
        }
        var procedureVariables: [NamedVar] = []
        for procedure in procedures {
            for parameter in procedure.parameters {
                procedureVariables.append(NamedVar(
                    name: parameter.root,
                    initial: .int(0),
                    initExpr: parameter.initial,
                    origin: .compiler
                ))
            }
            for local in procedure.locals {
                procedureVariables.append(NamedVar(
                    name: local.root,
                    initial: .int(0),
                    initExpr: local.initial,
                    origin: .compiler
                ))
            }
        }
        guard let first = steps.first else {
            return lowered(TLASpec(
                name: algorithm.name,
                variables: sharedVariables + procedureVariables,
                actions: [],
                invariants: declaredInvariants,
                temporalProperties: declaredTemporal,
                fairness: sequentialFairnessConditions(for: algorithm.sequentialFairness),
                constraint: declaredConstraint,
                formalOperatorDefinitions: formalOperatorDefinitions,
                sourceAlgorithms: [Algorithm(model: algorithm)]
            ))
        }
        // Match PlusCal's declaration order so TLC emits comparable frame
        // records in its retained DOT graph.
        let sequentialControl = ControlFlow(
            algorithm: algorithm.name,
            owner: .sequential(algorithm: algorithm.name)
        )
        var variables = [NamedVar(
            name: CompilerControlSymbol.programCounter.rawValue,
            initial: .string(first.label.name),
            initExpr: sequentialControl.location(first.label.name),
            origin: .programCounter
        )]
            + sharedVariables
        if !procedures.isEmpty {
            variables.append(NamedVar(name: CompilerControlSymbol.stack.rawValue, initial: .tuple([]), origin: .procedureStack))
        }
        variables += procedureVariables
        let variableNames = variables.map(\.name)

        var actions: [NamedAction] = []
        var generatedAssertionInvariants: [NamedInvariant] = []
        let actionSources = [(steps, Optional<AlgorithmProcedureModel>.none)]
            + procedures.map { ($0.steps, Optional($0)) }
        for (sourceSteps, owner) in actionSources {
            let control = ControlFlow(
                algorithm: algorithm.name,
                owner: owner.map { .procedure(algorithm: algorithm.name, name: $0.name) }
                    ?? .sequential(algorithm: algorithm.name)
            )
            for (index, atomic) in sourceSteps.enumerated() {
            let nextLabel = sourceSteps.indices.contains(index + 1)
                ? control.location(sourceSteps[index + 1].label.name)
                : .controlLocation(.init(
                    owner: .generated(algorithm: algorithm.name, purpose: CompilerControlSymbol.done.rawValue),
                    sourceName: CompilerControlSymbol.done.rawValue
                ))
            let label = emittedLabel(atomic.label.name, owner: owner)
            let statements = lowerSequential(
                atomic.statements,
                nextLabel: nextLabel,
                procedures: procedures,
                owner: owner,
                control: control
            )
            let body: ActionExpr
            if let condition = atomic.loopCondition {
                body = .ifElse(
                    condition,
                    completingSequentialControl(statements, fallthrough: control.location(atomic.label.name)),
                    sequentialTransfer(to: nextLabel)
                )
            } else {
                body = completingSequentialControl(statements, fallthrough: nextLabel)
            }
            actions.append(NamedAction(
                name: label,
                body: ActionNormalization.complete(
                    .and(.guard_(.equal(.programCounter, control.location(atomic.label.name))), body),
                    variables: variables
                ),
                controlOwner: owner.map {
                    .procedure(algorithm: algorithm.name, name: $0.name)
                } ?? .sequential(algorithm: algorithm.name)
            ))
            generatedAssertionInvariants += sequentialAssertionInvariants(
                in: atomic.statements,
                label: control.location(atomic.label.name),
                executionCondition: atomic.loopCondition,
                pathCondition: .value(.bool(true))
            )
            }
        }

        let terminate = variableNames
            .map { .unchanged(.named($0)) }
            .reduce(
                .guard_(.equal(
                    .programCounter,
                    .controlLocation(.init(
                        owner: .generated(algorithm: algorithm.name, purpose: CompilerControlSymbol.done.rawValue),
                        sourceName: CompilerControlSymbol.done.rawValue
                    ))
                )),
                ActionExpr.and
            )
        actions.append(NamedAction(name: CompilerControlSymbol.terminatingAction.rawValue, body: terminate))

        return lowered(TLASpec(
            name: algorithm.name,
            variables: variables,
            actions: actions,
            invariants: declaredInvariants + compilerOwnedAssertionInvariants(generatedAssertionInvariants),
            temporalProperties: declaredTemporal,
            fairness: sequentialFairnessConditions(for: algorithm.sequentialFairness),
            constraint: declaredConstraint,
            formalOperatorDefinitions: formalOperatorDefinitions,
            sourceAlgorithms: [Algorithm(model: algorithm)]
        ))
    }

    private static func sequentialTransfer(to location: StateExpr) -> ActionExpr {
        .assign(.programCounter, location)
    }

    private static func sequentialFairnessConditions(
        for fairness: SequentialAlgorithmFairness
    ) -> [FairnessCondition] {
        switch fairness {
        case .none: []
        case .weak: [.weakFairnessNext]
        }
    }

    private static func emittedLabel(_ label: String, owner: AlgorithmProcedureModel?) -> String {
        guard let owner else { return label }
        return "procedure.\(owner.name).\(label)"
    }

    private static func completingSequentialControl(_ action: ActionExpr, fallthrough location: StateExpr) -> ActionExpr {
        let branches = ActionNormalization.branches(of: action)
        let completed = branches.map { branch in
            assignedVars(branch).contains(.programCounter)
                ? branch
                : .and(branch, sequentialTransfer(to: location))
        }
        return completed.dropFirst().reduce(completed.first ?? sequentialTransfer(to: location), ActionExpr.or)
    }

    private static func lowerSequential(
        _ statements: [AlgorithmStatementModel],
        nextLabel: StateExpr,
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?,
        control: ControlFlow
    ) -> ActionExpr {
        var result = ActionExpr.guard_(.value(.bool(true)))
        var index = 0
        while index < statements.count {
            if case .call(let target, let arguments) = statements[index],
               index + 1 < statements.count,
               case .return = statements[index + 1] {
                result = .and(result, tailCallAction(target: target, arguments: arguments, procedures: procedures, control: control))
                index += 2
            } else {
                result = .and(result, lowerSequential(
                    statements[index],
                    nextLabel: nextLabel,
                    procedures: procedures,
                    owner: owner,
                    control: control
                ))
                index += 1
            }
        }
        return result
    }

    private static func lowerSequential(
        _ statement: AlgorithmStatementModel,
        nextLabel: StateExpr,
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?,
        control: ControlFlow
    ) -> ActionExpr {
        switch statement {
        case .rejected:
            return .guard_(.value(.bool(false)))
        case .await(let condition): return .guard_(condition)
        case .assert: return .guard_(.value(.bool(true)))
        case .set(let target, let value):
            switch target {
            case .root(let root): return .assign(.named(root), value)
            case .function(let root, let key): return .assign(.named(root), .except(.variable(root), key, value))
            }
        case .letBinding(let variable, let value, let body):
            return .define(variable, value, lowerSequential(body, nextLabel: nextLabel, procedures: procedures, owner: owner, control: control))
        case .with(let variable, let source, let body):
            return .existsAction(variable, source, lowerSequential(body, nextLabel: nextLabel, procedures: procedures, owner: owner, control: control))
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(condition, lowerSequential(then, nextLabel: nextLabel, procedures: procedures, owner: owner, control: control), lowerSequential(otherwise, nextLabel: nextLabel, procedures: procedures, owner: owner, control: control))
        case .either(let first, let second):
            return .or(lowerSequential(first, nextLabel: nextLabel, procedures: procedures, owner: owner, control: control), lowerSequential(second, nextLabel: nextLabel, procedures: procedures, owner: owner, control: control))
        case .choose(let variable, let domain, let body):
            return .existsAction(variable, .setLiteral(domain.map(StateExpr.value)), lowerSequential(body, nextLabel: nextLabel, procedures: procedures, owner: owner, control: control))
        case .goto(let label): return sequentialTransfer(to: control.location(label.name))
        case .call(let target, let arguments):
            return callAction(target: target, arguments: arguments, returnTo: nextLabel, procedures: procedures, control: control)
        case .return:
            return returnAction(owner: owner, procedures: procedures)
        case .stop: return sequentialTransfer(to: .controlLocation(.init(
            owner: .generated(algorithm: control.algorithm, purpose: CompilerControlSymbol.done.rawValue),
            sourceName: CompilerControlSymbol.done.rawValue
        )))
        case .skip: return .guard_(.value(.bool(true)))
        }
    }

    private static func callAction(
        target: String,
        arguments: [StateExpr],
        returnTo: StateExpr,
        procedures: [AlgorithmProcedureModel],
        control: ControlFlow
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        // A frame captures every procedure-owned slot, not only the callee's.
        // That makes a tail call safe: it reuses the caller's continuation and
        // return restores the entire pre-call procedural environment at once.
        let frameFields = [
            (CompilerControlSymbol.procedure.rawValue, StateExpr.value(.string(procedure.name))),
            (CompilerControlSymbol.programCounter.rawValue, returnTo)
        ]
            + procedureSlots(procedures).map { ($0.root, StateExpr.variable($0.root)) }
        let push = ActionExpr.assign(
            .procedureStack,
            .tupleConcatenate(.tupleLiteral([StateExpr.record(Dictionary(uniqueKeysWithValues: frameFields))]), .procedureStack)
        )
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign(.named($0.0.root), $0.1)
        }
        let localAssignments = procedure.locals.map { ActionExpr.assign(.named($0.root), $0.initial) }
        return (parameterAssignments + localAssignments + [push, sequentialTransfer(to: control.procedure(procedure, location: entry))])
            .reduce(.guard_(.value(.bool(true))), ActionExpr.and)
    }

    private static func returnAction(
        owner: AlgorithmProcedureModel?,
        procedures: [AlgorithmProcedureModel]
    ) -> ActionExpr {
        guard owner != nil else { return .guard_(.value(.bool(false))) }
        let stack = StateExpr.procedureStack
        let frame = StateExpr.tupleHead(stack)
        let restore = (procedureSlots(procedures).map { ActionExpr.assign(.named($0.root), .recordAccess(frame, $0.root)) }
            + [
                .assign(.procedureStack, .tupleTail(stack)),
                .assign(.programCounter, .recordAccess(frame, CompilerControlSymbol.programCounter.rawValue))
            ])
        return restore.reduce(
            .guard_(.greaterThan(.tupleLength(stack), .int(0))),
            ActionExpr.and
        )
    }

    private static func tailCallAction(
        target: String,
        arguments: [StateExpr],
        procedures: [AlgorithmProcedureModel],
        control: ControlFlow
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign(.named($0.0.root), $0.1)
        }
        let localAssignments = procedure.locals.map { ActionExpr.assign(.named($0.root), $0.initial) }
        return (parameterAssignments + localAssignments + [sequentialTransfer(to: control.procedure(procedure, location: entry))])
            .reduce(.guard_(.value(.bool(true))), ActionExpr.and)
    }

    private static func processCallAction(
        target: String,
        arguments: [StateExpr],
        returnTo: StateExpr,
        procedures: [AlgorithmProcedureModel],
        control: ControlFlow
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        let process = StateExpr.variable(processBinding.rawValue)
        let stack = StateExpr.functionApply(.procedureStack, process)
        let frameFields = [
            (CompilerControlSymbol.procedure.rawValue, StateExpr.value(.string(procedure.name))),
            (CompilerControlSymbol.programCounter.rawValue, returnTo)
        ]
            + procedureSlots(procedures).map {
                ($0.root, StateExpr.functionApply(.variable($0.root), process))
            }
        let push = ActionExpr.assign(
            .procedureStack,
            .except(
                .procedureStack,
                process,
                .tupleConcatenate(.tupleLiteral([StateExpr.record(Dictionary(uniqueKeysWithValues: frameFields))]), stack)
            )
        )
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign(.named($0.0.root), .except(.variable($0.0.root), process, $0.1))
        }
        let localRoots = Set(procedureSlots(procedures).map(\.root))
        let localAssignments = procedure.locals.map {
            ActionExpr.assign(.named($0.root), .except(.variable($0.root), process, rewrite($0.initial, localRoots: localRoots)))
        }
        return (parameterAssignments + localAssignments + [push, transfer(to: control.procedure(procedure, location: entry))])
            .reduce(.guard_(.value(.bool(true))), ActionExpr.and)
    }

    private static func processReturnAction(
        owner: AlgorithmProcedureModel?,
        procedures: [AlgorithmProcedureModel]
    ) -> ActionExpr {
        guard owner != nil else { return .guard_(.value(.bool(false))) }
        let process = StateExpr.variable(processBinding.rawValue)
        let stack = StateExpr.functionApply(.procedureStack, process)
        let frame = StateExpr.tupleHead(stack)
        let restore = procedureSlots(procedures).map {
            ActionExpr.assign(.named($0.root), .except(.variable($0.root), process, .recordAccess(frame, $0.root)))
        } + [
            .assign(.procedureStack, .except(.procedureStack, process, .tupleTail(stack))),
            transfer(toExpression: .recordAccess(frame, CompilerControlSymbol.programCounter.rawValue))
        ]
        return restore.reduce(
            .guard_(.greaterThan(.tupleLength(stack), .int(0))),
            ActionExpr.and
        )
    }

    private static func processTailCallAction(
        target: String,
        arguments: [StateExpr],
        procedures: [AlgorithmProcedureModel],
        control: ControlFlow
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        let process = StateExpr.variable(processBinding.rawValue)
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign(.named($0.0.root), .except(.variable($0.0.root), process, $0.1))
        }
        let localRoots = Set(procedureSlots(procedures).map(\.root))
        let localAssignments = procedure.locals.map {
            ActionExpr.assign(.named($0.root), .except(.variable($0.root), process, rewrite($0.initial, localRoots: localRoots)))
        }
        return (parameterAssignments + localAssignments + [transfer(to: control.procedure(procedure, location: entry))])
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
        label: StateExpr,
        executionCondition: StateExpr?,
        pathCondition: StateExpr
    ) -> [NamedInvariant] {
        let atLabel = StateExpr.equal(.programCounter, label)
        let executed = StateExpr.and(executionCondition.map { .and(atLabel, $0) } ?? atLabel, pathCondition)
        return statements.flatMap { statement in
            switch statement {
            case .rejected:
                return [NamedInvariant]()
            case .assert(let condition):
                return [NamedInvariant(
                    name: "__pcal_assert",
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
                    in: body.map {
                        $0.substitutingVariable(
                            variable,
                            with: value,
                            assignmentTargets: .preserve
                        )
                    },
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

    private static func lower(
        _ statements: [AlgorithmStatementModel],
        localRoots: Set<String>,
        processDomain: [TLAValue],
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?,
        nextLabel: StateExpr,
        control: ControlFlow
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
                    procedures: procedures,
                    control: control
                ))
                index += 2
            } else {
                result = .and(result, lower(
                    statements[index],
                    localRoots: localRoots,
                    processDomain: processDomain,
                    procedures: procedures,
                    owner: owner,
                    nextLabel: nextLabel,
                    control: control
                ))
                index += 1
            }
        }
        return result
    }

    private static func transfer(to location: StateExpr) -> ActionExpr {
        transfer(toExpression: location)
    }

    private static func transfer(toExpression label: StateExpr) -> ActionExpr {
        .assign(
            .programCounter,
            .except(
                .programCounter,
                .variable(processBinding.rawValue),
                label))
    }

    /// An `Each` machine continues to its next `Do` when it does not explicitly
    /// transfer control. Its final `Do` reaches the builder-owned `Done` state.
    private static func completingControl(_ action: ActionExpr, fallthrough location: StateExpr) -> ActionExpr {
        let branches = ActionNormalization.branches(of: action)
        let completed = branches.map { branch in
            assignedVars(branch).contains(.programCounter)
                ? branch
                : .and(branch, transfer(to: location))
        }
        return completed.dropFirst().reduce(completed.first ?? transfer(to: location), ActionExpr.or)
    }

    private static func lower(
        _ statement: AlgorithmStatementModel,
        localRoots: Set<String>,
        processDomain: [TLAValue],
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?,
        nextLabel: StateExpr,
        control: ControlFlow
    ) -> ActionExpr {
        switch statement {
        case .rejected:
            return .guard_(.value(.bool(false)))
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
                    .named(root),
                    .except(.variable(root), .variable(processBinding.rawValue), value))
            case .root(let root):
                return .assign(.named(root), value)
            case .function(let root, let key):
                return .assign(
                    .named(root),
                    .except(
                        .variable(root),
                        rewrite(key, localRoots: localRoots),
                        value))
            }
        case .letBinding(let variable, let value, let body):
            return .define(
                variable,
                rewrite(value, localRoots: localRoots),
                lower(body, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel, control: control)
            )
        case .with(let variable, let source, let body):
            return .existsAction(
                variable,
                rewrite(source, localRoots: localRoots),
                lower(body, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel, control: control))
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(
                rewrite(condition, localRoots: localRoots),
                lower(then, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel, control: control),
                lower(otherwise, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel, control: control))
        case .either(let first, let second):
            return .or(
                lower(first, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel, control: control),
                lower(second, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel, control: control))
        case .choose(let variable, let domain, let body):
            return .existsAction(
                variable,
                .setLiteral(domain.map { .value($0) }),
                lower(body, localRoots: localRoots, processDomain: processDomain, procedures: procedures, owner: owner, nextLabel: nextLabel, control: control))
        case .goto(let label):
            return transfer(to: control.location(label.name))
        case .call(let target, let arguments):
            return processCallAction(
                target: target,
                arguments: arguments.map { rewrite($0, localRoots: localRoots) },
                returnTo: nextLabel,
                procedures: procedures,
                control: control
            )
        case .return:
            return processReturnAction(owner: owner, procedures: procedures)
        case .stop:
            return transfer(to: .controlLocation(.init(
                owner: .generated(algorithm: control.algorithm, purpose: CompilerControlSymbol.done.rawValue),
                sourceName: CompilerControlSymbol.done.rawValue
            )))
        case .skip:
            return .guard_(.value(.bool(true)))
        }
    }

    private static func assertionInvariants(
        in statements: [AlgorithmStatementModel],
        process: AlgorithmProcessModel,
        label: StateExpr,
        localRoots: Set<String>,
        executionCondition: StateExpr?,
        pathCondition: StateExpr,
        quantifiedBindings: [(variable: String, source: StateExpr)]
    ) -> [NamedInvariant] {
        let pcAtLabel = StateExpr.equal(
            .functionApply(.programCounter, .variable(processBinding.rawValue)),
            label
        )
        let executedAtLabel = StateExpr.and(
            executionCondition.map { .and(pcAtLabel, $0) } ?? pcAtLabel,
            pathCondition
        )
        return statements.flatMap { statement in
            switch statement {
            case .rejected:
                return [NamedInvariant]()
            case .assert(let condition):
                return process.domain.map { identifier in
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
                        processBinding.rawValue,
                        identifier,
                        in: .or(.not(executedAtLabel), assertion)
                    )
                    return NamedInvariant(
                        name: "__pcal_assert",
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
                        $0.substitutingVariable(
                            variable,
                            with: rewrite(value, localRoots: localRoots),
                            assignmentTargets: .preserve
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
            actionVariants(action).map {
                .weakFairnessActionCall(.init(name: action.name, arguments: $0.arguments))
            }
        case .strong:
            actionVariants(action).map {
                .strongFairnessActionCall(.init(name: action.name, arguments: $0.arguments))
            }
        }
    }

    private static func compilerOwnedAssertionInvariants(
        _ invariants: [NamedInvariant]
    ) -> [NamedInvariant] {
        invariants.enumerated().map { ordinal, invariant in
            NamedInvariant(name: "__pcal_assert_\(ordinal)", body: invariant.body)
        }
    }

    private static func rewrite(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
        func rewritten(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
            switch expression {
            case .sourceIssue, .value, .programCounter, .procedureStack, .controlLocation:
                return expression
            case .currentProcess:
                return .variable(processBinding.rawValue)
            case .variable(let name):
                if localRoots.contains(name) {
                    return .functionApply(.variable(name), .variable(processBinding.rawValue))
                }
                return expression
            case .processLocalFamily(let root):
                return localRoots.contains(root) ? .variable(root) : expression
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
            case .recordLiteral(let fields):
                return .recordLiteral(.init(fields.fields.map {
                    .init(name: $0.name, value: rewritten($0.value, localRoots: localRoots))
                }))
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
