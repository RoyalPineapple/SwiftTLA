enum AlgorithmLowerer {
    private enum CompilerBindingSymbol: String, Sendable {
        case process
    }

    // These frame keys match the official PlusCal translation so both tools
    // expose the same formal stack representation.

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
        processNames: [String],
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
        let procedureProcessType = Set(processes.map(\.typeName)).count == 1
            ? processes.first?.typeName
            : nil
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
        let declaredInvariants = algorithm.components.compactMap { component -> NamedStatePredicate? in
            guard case .invariant(let invariant) = component else { return nil }
            return invariant
        }
        let processInvariants = processes.flatMap { process -> [NamedStatePredicate] in
            let localRoots = Set(process.components.compactMap { component -> String? in
                guard case .local(let state) = component else { return nil }
                return state.root
            })
            let processDomain = process.domain
            return process.components.compactMap { component -> NamedStatePredicate? in
                guard case .invariant(let invariant) = component else { return nil }
                return NamedStatePredicate(
                    name: invariant.name,
                    body: .forAll(
                        processDomain,
                        processBinding.rawValue,
                        rewrite(invariant.body, localRoots: localRoots)
                    ),
                    reference: invariant.reference
                )
            }
        }
        let declaredTemporal = algorithm.components.compactMap { component -> NamedTemporal? in
            guard case .temporal(let temporal) = component else { return nil }
            return temporal
        }
        let processTemporal = processes.flatMap { process -> [NamedTemporal] in
            let localRoots = Set(process.components.compactMap { component -> String? in
                guard case .local(let state) = component else { return nil }
                return state.root
            })
            return process.components.compactMap { component -> NamedTemporal? in
                guard case .temporal(let temporal) = component else { return nil }
                return NamedTemporal(name: temporal.name,
                    expr: temporal.expr.map { rewrite($0, localRoots: localRoots) },
                    bindings: [ActionBinding(name: processBinding.rawValue, domain: process.domain,
                        generatedSwiftType: process.typeName)], reference: temporal.reference)
            }
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
                initialization: state.initialization,
                generatedSwiftType: state.swiftTypeName,
                origin: .source
            )
        }
        for process in processes {
            let localStates = process.components.compactMap { component -> AlgorithmStateModel? in
                guard case .local(let state) = component else { return nil }
                return state
            }
            let localRoots = Set(localStates.map(\.root))
            for state in localStates {
                let initial = deterministicInitialization(
                    state.initialization,
                    path: "processes.\(process.typeName).locals.\(state.root)"
                )
                variables.append(
                    NamedVar(
                        name: state.root,
                        initialization: .expression(constantFunction(
                            domain: process.domain,
                            value: initial,
                            localRoots: localRoots
                        )),
                        generatedSwiftType: state.swiftTypeName.map { "[\(process.typeName): \($0)]" },
                        origin: .compiler
                    ))
            }
        }

        if requiresProgramCounter {
            let controlBinding = "__pcal_initial_process"
            let controlDomain = processes
                .map(\.domain)
                .dropFirst()
                .reduce(
                    processes.first?.domain ?? .setLiteral([])
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
                        process.domain
                    ),
                    control.location(first.label.name)
                ]
            }
            variables.insert(NamedVar(
                name: CompilerControlSymbol.programCounter.rawValue,
                initialization: .expression(.functionLiteral(
                    controlDomain,
                    controlBinding,
                    .caseExpr(controlCases, nil)
                )),
                origin: .programCounter
            ), at: 0)
        }
        if !procedures.isEmpty {
            for slot in procedureSlots(procedures) {
                variables.append(NamedVar(
                    name: slot.root,
                    initialization: .expression(constantFunction(
                        domain: controlDomain(processes),
                        value: slot.initial,
                        localRoots: []
                    )),
                    generatedSwiftType: procedureProcessType.flatMap { processType in
                        slot.swiftTypeName.map { "[\(processType): \($0)]" }
                    },
                    origin: .compiler
                ))
            }
            variables.append(NamedVar(
                name: CompilerControlSymbol.stack.rawValue,
                initialization: .expression(constantFunction(
                    domain: controlDomain(processes),
                    value: .tupleLiteral([]),
                    localRoots: []
                )),
                origin: .procedureStack
            ))
        }

        let variableNames = variables.map(\.name)
        let localRoots = Set(localStates.map(\.root) + procedureSlots(procedures).map(\.root))
        var generatedAssertionInvariants: [NamedStatePredicate] = []
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
                    processLocalRoots: localRoots,
                    procedures: procedures,
                    owner: nil,
                    nextLabel: nextLabel,
                    control: control
                )
                let body: ActionExpr
                if !requiresProgramCounter {
                    body = loweredStatements.action
                } else if let loopCondition = atomic.loopCondition {
                    body = .ifElse(
                        rewrite(loopCondition, localRoots: localRoots),
                        completingControl(loweredStatements.action, fallthrough: control.location(atomic.label.name)),
                        transfer(to: nextLabel)
                    )
                } else {
                    body = completingControl(loweredStatements.action, fallthrough: nextLabel)
                }
                let generatedAction = NamedAction(
                    name: requiresProgramCounter ? atomic.label.name : processNames[processIndex],
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
                    bindings: [ActionBinding(
                        name: processBinding.rawValue,
                        domain: process.domain,
                        generatedSwiftType: process.typeName
                    )]
                )
                if requiresProgramCounter {
                    let atStep = StateExpr.equal(
                        .functionApply(.programCounter, .variable(processBinding.rawValue)),
                        control.location(atomic.label.name))
                    let enabled = atomic.loopCondition.map {
                        StateExpr.and(atStep, rewrite($0, localRoots: localRoots))
                    } ?? atStep
                    generatedAssertionInvariants += assertionInvariants(loweredStatements.assertions,
                        enabled: enabled, domain: process.domain)
                }
                fairness += fairnessConditions(for: generatedAction, domain: process.domain, policy: process.fairness)
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
                    processLocalRoots: localRoots,
                    procedures: procedures,
                    owner: procedure,
                    nextLabel: nextLabel,
                    control: control
                )
                let body = completingControl(loweredStatements.action, fallthrough: nextLabel)
                generatedAssertionInvariants += assertionInvariants(loweredStatements.assertions,
                    enabled: guardExpression, domain: controlDomain(processes))
                return NamedAction(
                    name: label,
                    body: ActionNormalization.complete(.and(.guard_(guardExpression), body), variables: variables),
                    bindings: [ActionBinding(
                        name: processBinding.rawValue,
                        domain: controlDomain(processes),
                        generatedSwiftType: procedureProcessType
                    )]
                )
            }
        }
        actions += procedureActions

        if requiresProgramCounter {
            let allDone = processes.reduce(StateExpr.value(.bool(true))) { condition, process in
                let members = process.domain
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
            actions.append(NamedAction(name: CompilerControlSymbol.terminatingAction.rawValue, body: unchanged, isTermination: true))
        }

        return lowered(TLASpec(
            name: algorithm.name,
            variables: variables,
            actions: actions,
            invariants: declaredInvariants + processInvariants
                + compilerOwnedAssertionInvariants(generatedAssertionInvariants),
            temporalProperties: declaredTemporal + processTemporal,
            fairness: fairness,
            constraint: declaredConstraint,
            formalOperatorDefinitions: resolvedFormalOperators,
            sourceAlgorithms: [Algorithm(model: algorithm)]))
    }

    private static func constantFunction(
        domain: StateExpr,
        value: StateExpr,
        localRoots: Set<String>
    ) -> StateExpr {
        let binding = "__pcal_initial_process"
        let initial = StateExpr.substituteVariable(
            processBinding.rawValue,
            with: .variable(binding),
            in: rewrite(value, localRoots: localRoots)
        )
        return .functionLiteral(
            domain,
            binding,
            initial
        )
    }

    private static func controlDomain(_ processes: [AlgorithmProcessModel]) -> StateExpr {
        let literals = processes.compactMap { $0.domain.literalSetMembers }
        if literals.count == processes.count {
            return .setLiteral(Array(Set(literals.flatMap { $0 })).sorted().map(StateExpr.value))
        }
        return processes.dropFirst().reduce(processes.first?.domain ?? .setLiteral([])) {
            .union($0, $1.domain)
        }
    }

    private static func assertionInvariants(_ assertions: [StateExpr], enabled: StateExpr, domain: StateExpr) -> [NamedStatePredicate] {
        if let members = domain.literalSetMembers {
            return members.flatMap { member in
                assertions.map { predicate in
                    NamedStatePredicate(name: "__pcal_assert", body: StateExpr.substituteVariables(
                        [processBinding.rawValue: .value(member)], in: .or(.not(enabled), predicate)))
                }
            }
        }
        return assertions.map {
            NamedStatePredicate(name: "__pcal_assert", body: .forAll(domain,
                processBinding.rawValue, .or(.not(enabled), $0)))
        }
    }

    /// A nonempty process machine with one unconditional control-free loop has no `pc`.
    private static func requiresProgramCounter(for algorithm: AlgorithmModel) -> Bool {
        guard !algorithm.processes.isEmpty, algorithm.procedures.isEmpty else {
            return true
        }
        return !algorithm.processes.allSatisfy { process in
            guard let members = process.domain.literalSetMembers, !members.isEmpty,
                  process.steps.count == 1,
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
            case .parallel:
                return false
            case .letBinding(_, _, let body), .with(_, _, let body), .choose(_, _, let body):
                return containsControlTransfer(body)
            case .ifElse(_, let then, let otherwise), .either(let then, let otherwise):
                return containsControlTransfer(then) || containsControlTransfer(otherwise)
            case .when, .set, .skip:
                return false
            }
        }
    }

    /// Lowers a PlusCal `begin ... end algorithm` body with scalar `pc` and
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
        let declaredInvariants = algorithm.components.compactMap { component -> NamedStatePredicate? in
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
                initialization: state.initialization,
                generatedSwiftType: state.swiftTypeName,
                origin: .source
            )
        }
        var procedureVariables: [NamedVar] = []
        for procedure in procedures {
            for parameter in procedure.parameters {
                procedureVariables.append(NamedVar(
                    name: parameter.root,
                    initialization: .expression(parameter.initial),
                    generatedSwiftType: parameter.swiftTypeName,
                    origin: .compiler
                ))
            }
            for local in procedure.locals {
                procedureVariables.append(NamedVar(
                    name: local.root,
                    initialization: .expression(deterministicInitialization(
                        local.initialization,
                        path: "procedures.\(procedure.name).locals.\(local.root)"
                    )),
                    generatedSwiftType: local.swiftTypeName,
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
            initialization: .expression(sequentialControl.location(first.label.name)),
            origin: .programCounter
        )]
            + sharedVariables
        if !procedures.isEmpty {
            variables.append(NamedVar(
                name: CompilerControlSymbol.stack.rawValue,
                initialization: .value(.tuple([])),
                origin: .procedureStack
            ))
        }
        variables += procedureVariables
        let variableNames = variables.map(\.name)

        var actions: [NamedAction] = []
        var generatedAssertionInvariants: [NamedStatePredicate] = []
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
            let statements = lower(
                atomic.statements,
                processLocalRoots: nil,
                procedures: procedures,
                owner: owner,
                nextLabel: nextLabel,
                control: control
            )
            let body: ActionExpr
            if let condition = atomic.loopCondition {
                body = .ifElse(
                    condition,
                    completingSequentialControl(statements.action, fallthrough: control.location(atomic.label.name)),
                    sequentialTransfer(to: nextLabel)
                )
            } else {
                body = completingSequentialControl(statements.action, fallthrough: nextLabel)
            }
            actions.append(NamedAction(
                name: label,
                body: ActionNormalization.complete(
                    .and(.guard_(.equal(.programCounter, control.location(atomic.label.name))), body),
                    variables: variables
                )
            ))
            let atStep = StateExpr.equal(.programCounter, control.location(atomic.label.name))
            let enabled = atomic.loopCondition.map { StateExpr.and(atStep, $0) } ?? atStep
            generatedAssertionInvariants += statements.assertions.map {
                NamedStatePredicate(name: "__pcal_assert", body: .or(.not(enabled), $0))
            }
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
        actions.append(NamedAction(name: CompilerControlSymbol.terminatingAction.rawValue, body: terminate, isTermination: true))

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

    private static func deterministicInitialization(
        _ initialization: VariableInitialization,
        path: String
    ) -> StateExpr {
        switch initialization {
        case .value(let value): return .value(value)
        case .expression(let expression): return expression
        case .memberOf:
            return .sourceIssue(.formalDeclaration(
                kind: "process-local initializer",
                name: path,
                problem: "nondeterministic local initialization is not supported"
            ))
        }
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

    private static func callAction(
        target: String,
        arguments: [StateExpr],
        returnTo: StateExpr?,
        procedures: [AlgorithmProcedureModel],
        control: ControlFlow
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        // A frame captures every procedure-owned slot. A tail call reuses the
        // caller's continuation, and return restores the pre-call environment.
        let push = returnTo.map { returnTo in
            let frameFields = [
                (CompilerControlSymbol.procedure.rawValue, StateExpr.value(.string(procedure.name))),
                (CompilerControlSymbol.programCounter.rawValue, returnTo)
            ]
                + procedureSlots(procedures).map { ($0.root, StateExpr.variable($0.root)) }
            return ActionExpr.assign(
                .procedureStack,
                .tupleConcatenate(.tupleLiteral([.recordLiteral(.init(orderedFields: frameFields.map {
                    .init(name: $0.0, value: $0.1)
                }))]), .procedureStack)
            )
        }
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign(.named($0.0.root), $0.1)
        }
        let localAssignments = procedure.locals.map {
            ActionExpr.assign(
                .named($0.root),
                deterministicInitialization($0.initialization, path: "procedures.\(procedure.name).locals.\($0.root)")
            )
        }
        var assignments = parameterAssignments + localAssignments
        if let push { assignments.append(push) }
        assignments.append(sequentialTransfer(to: control.procedure(procedure, location: entry)))
        return assignments.reduce(.guard_(.value(.bool(true))), ActionExpr.and)
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

    private static func processCallAction(
        target: String,
        arguments: [StateExpr],
        returnTo: StateExpr?,
        procedures: [AlgorithmProcedureModel],
        control: ControlFlow
    ) -> ActionExpr {
        guard let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name else {
            return .guard_(.value(.bool(false)))
        }
        let process = StateExpr.variable(processBinding.rawValue)
        let stack = StateExpr.functionApply(.procedureStack, process)
        let push = returnTo.map { returnTo in
            let frameFields = [
                (CompilerControlSymbol.procedure.rawValue, StateExpr.value(.string(procedure.name))),
                (CompilerControlSymbol.programCounter.rawValue, returnTo)
            ]
                + procedureSlots(procedures).map {
                    ($0.root, StateExpr.functionApply(.variable($0.root), process))
                }
            return ActionExpr.assign(
                .procedureStack,
                .except(
                    .procedureStack,
                    process,
                    .tupleConcatenate(.tupleLiteral([.recordLiteral(.init(orderedFields: frameFields.map {
                        .init(name: $0.0, value: $0.1)
                    }))]), stack)
                )
            )
        }
        let parameterAssignments = zip(procedure.parameters, arguments).map {
            ActionExpr.assign(.named($0.0.root), .except(.variable($0.0.root), process, $0.1))
        }
        let localRoots = Set(procedureSlots(procedures).map(\.root))
        let localAssignments = procedure.locals.map {
            let initial = deterministicInitialization(
                $0.initialization,
                path: "procedures.\(procedure.name).locals.\($0.root)"
            )
            return ActionExpr.assign(.named($0.root), .except(.variable($0.root), process, rewrite(initial, localRoots: localRoots)))
        }
        var assignments = parameterAssignments + localAssignments
        if let push { assignments.append(push) }
        assignments.append(transfer(to: control.procedure(procedure, location: entry)))
        return assignments.reduce(.guard_(.value(.bool(true))), ActionExpr.and)
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

    private static func procedureSlots(
        _ procedures: [AlgorithmProcedureModel]
    ) -> [(root: String, initial: StateExpr, swiftTypeName: String?)] {
        procedures.flatMap { procedure in
            procedure.parameters.map { ($0.root, $0.initial, $0.swiftTypeName) }
                + procedure.locals.map {
                    ($0.root, deterministicInitialization(
                        $0.initialization,
                        path: "procedures.\(procedure.name).locals.\($0.root)"
                    ), $0.swiftTypeName)
                }
        }
    }

    /// Lowers scheduled atomic branches, preserving their bindings and final writes.
    private static func lower(
        _ statements: [AlgorithmStatementModel],
        processLocalRoots: Set<String>?,
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?,
        nextLabel: StateExpr,
        control: ControlFlow
    ) -> (action: ActionExpr, assertions: [StateExpr]) {
        typealias Result = (action: ActionExpr, assertions: [StateExpr])
        func scoped(_ value: StateExpr) -> StateExpr {
            processLocalRoots.map { rewrite(value, localRoots: $0) } ?? value
        }
        func assignments(_ values: [String: StateExpr], excluding: Set<ActionTarget> = []) -> ActionExpr {
            values.sorted { $0.key < $1.key }
                .filter { !excluding.contains(.named($0.key)) }
                .reduce(.guard_(.bool(true))) {
                    .and($0, .assign(.named($1.key), $1.value))
                }
        }
        func defined(_ name: String, _ value: StateExpr, _ body: Result) -> Result {
            (.define(name, value, body.action), body.assertions.map {
                .letIn([LocalOperator(name, body: value)],
                    StateExpr.substituteVariable(name, with: .recursiveCall(name, []), in: $0))
            })
        }
        func guarded(_ condition: StateExpr, _ body: Result) -> Result {
            (.and(.guard_(condition), body.action), body.assertions.map { .or(.not(condition), $0) })
        }
        func run(_ remaining: ArraySlice<AlgorithmStatementModel>, _ values: [String: StateExpr]) -> Result {
            guard let statement = remaining.first else { return (assignments(values), []) }
            let rest = remaining.dropFirst()
            func continueWith(_ body: [AlgorithmStatementModel], _ values: [String: StateExpr]) -> Result {
                run((body + rest)[...], values)
            }
            switch statement {
            case .set, .choose:
                preconditionFailure("Atomic statements must be scheduled before lowering")
            case .parallel(let group):
                var next = values
                for assignment in group {
                    let root = assignment.target.root
                    let value = scoped(assignment.value)
                    switch assignment.target {
                    case .root where processLocalRoots?.contains(root) == true:
                        next[root] = .except(.variable(root), .variable(processBinding.rawValue), value)
                    case .root:
                        next[root] = value
                    case .function, .field:
                        preconditionFailure("Scheduled assignments must target complete roots")
                    }
                }
                return run(rest, next)
            case .when(let condition):
                return guarded(scoped(condition), run(rest, values))
            case .assert(let condition):
                let tail = run(rest, values)
                return (tail.action, [scoped(condition)] + tail.assertions)
            case .letBinding(let variable, let value, let body):
                return defined(variable, scoped(value), continueWith(body, values))
            case .with(let variable, let domain, let body):
                let source = scoped(domain)
                let nested = continueWith(body, values)
                return (.existsAction(variable, source, nested.action),
                    nested.assertions.map { .forAll(source, variable, $0) })
            case .ifElse(let condition, let then, let otherwise):
                let predicate = scoped(condition)
                let first = continueWith(then, values)
                let second = continueWith(otherwise, values)
                return (.ifElse(predicate, first.action, second.action),
                    first.assertions.map { .or(.not(predicate), $0) }
                        + second.assertions.map { .or(predicate, $0) })
            case .either(let first, let second):
                let lhs = continueWith(first, values)
                let rhs = continueWith(second, values)
                return (.or(lhs.action, rhs.action), lhs.assertions + rhs.assertions)
            case .skip:
                return run(rest, values)
            case .rejected:
                return (.guard_(.bool(false)), [])
            case .goto, .call, .return, .stop:
                let transfer: ActionExpr
                if case .call(let target, let arguments) = statement,
                   rest.first == .return {
                    transfer = processLocalRoots.map { roots in
                        processCallAction(target: target, arguments: arguments.map { rewrite($0, localRoots: roots) },
                            returnTo: nil, procedures: procedures, control: control)
                    } ?? callAction(target: target, arguments: arguments, returnTo: nil,
                        procedures: procedures, control: control)
                } else {
                    transfer = lower(statement, processLocalRoots: processLocalRoots,
                        procedures: procedures, owner: owner, nextLabel: nextLabel, control: control)
                }
                let effect = transfer.substitutingVariables(values)
                return (.and(assignments(values, excluding: assignedVars(effect)), effect), [])
            }
        }
        return run(statements[...], [:])
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

    /// An `Each` machine falls through to its next `Do`; its final `Do` reaches
    /// the builder-owned `Done` state.
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
        processLocalRoots: Set<String>?,
        procedures: [AlgorithmProcedureModel],
        owner: AlgorithmProcedureModel?,
        nextLabel: StateExpr,
        control: ControlFlow
    ) -> ActionExpr {
        func scoped(_ value: StateExpr) -> StateExpr {
            processLocalRoots.map { rewrite(value, localRoots: $0) } ?? value
        }
        func jump(to location: StateExpr) -> ActionExpr {
            processLocalRoots == nil ? sequentialTransfer(to: location) : transfer(to: location)
        }
        switch statement {
        case .goto(let label):
            return jump(to: control.location(label.name))
        case .call(let target, let arguments):
            if processLocalRoots != nil {
                return processCallAction(target: target, arguments: arguments.map(scoped), returnTo: nextLabel, procedures: procedures, control: control)
            }
            return callAction(target: target, arguments: arguments, returnTo: nextLabel, procedures: procedures, control: control)
        case .return:
            return processLocalRoots == nil
                ? returnAction(owner: owner, procedures: procedures)
                : processReturnAction(owner: owner, procedures: procedures)
        case .stop:
            return jump(to: .controlLocation(.init(
                owner: .generated(algorithm: control.algorithm, purpose: CompilerControlSymbol.done.rawValue),
                sourceName: CompilerControlSymbol.done.rawValue
            )))
        default:
            preconditionFailure("Only terminal statements reach control-transfer lowering")
        }
    }


    private static func fairnessConditions(
        for action: NamedAction,
        domain: StateExpr,
        policy: AlgorithmFairness
    ) -> [FairnessCondition] {
        if case .none = policy { return [] }
        guard let members = domain.literalSetMembers else {
            return [policy == .strong ? .strongFairnessEachAction(action.name) : .weakFairnessEachAction(action.name)]
        }
        return switch policy {
        case .none:
            []
        case .weak:
            members.map {
                .weakFairnessActionCall(.init(name: action.name, arguments: [$0]))
            }
        case .strong:
            members.map {
                .strongFairnessActionCall(.init(name: action.name, arguments: [$0]))
            }
        }
    }

    private static func compilerOwnedAssertionInvariants(
        _ invariants: [NamedStatePredicate]
    ) -> [NamedStatePredicate] {
        invariants.enumerated().map { ordinal, invariant in
            NamedStatePredicate(name: "__pcal_assert_\(ordinal)", body: invariant.body)
        }
    }

    private static func rewrite(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
        func rewritten(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
            switch expression {
            case .sourceIssue, .value, .parameter, .programCounter, .procedureStack, .controlLocation:
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
            case .assertView(let value, let shape): return .assertView(rewritten(value, localRoots: localRoots), shape)
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
            case .tupleRemoving(let tuple, let index):
                return .tupleRemoving(rewritten(tuple, localRoots: localRoots), rewritten(index, localRoots: localRoots))
            case .sequenceSelect(let sequence, let variable, let predicate):
                return .sequenceSelect(
                    rewritten(sequence, localRoots: localRoots),
                    variable,
                    rewritten(predicate, localRoots: localRoots.subtracting([variable]))
                )
            case .recordLiteral(let fields):
                return .recordLiteral(fields.mapValues { rewritten($0, localRoots: localRoots) })
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
