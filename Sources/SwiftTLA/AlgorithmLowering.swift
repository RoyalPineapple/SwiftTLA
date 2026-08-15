extension Algorithm {
    /// Lowers a validated bounded algorithm into the ordinary executable TLA+ model.
    public func lower() throws -> TLASpec {
        try requireValid()
        return AlgorithmLowerer.lower(model)
    }
}

enum AlgorithmLowerer {
    private static let controlVariable = "pc"
    private static let processBinding = "process"
    private static let builderProcessIdentifier = "__pcal_self"
    private static let doneLabel = "Done"
    private static let terminatingAction = "Terminating"

    static func lower(_ algorithm: AlgorithmModel) -> TLASpec {
        let processes = algorithm.processes
        if processes.isEmpty, !algorithm.sequentialSteps.isEmpty {
            return lowerSequential(algorithm)
        }
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

        var variables = shared.map { state in
            if let initial = try? state.initial.evaluate(in: [:]) {
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
                        initial: staticInitialValue(
                            constantFunction(domain: process.domain, value: state.initial),
                            named: state.root
                        )
                    ))
            }
        }

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
        let controlInitial = StateExpr.functionLiteral(
            controlDomain,
            controlBinding,
            .caseExpr(controlCases, nil)
        )
        variables.append(NamedVar(
            name: controlVariable,
            initial: .function([:]),
            initExpr: controlInitial
        ))

        let variableNames = variables.map(\.name)
        let localRoots = Set(localStates.map(\.root))
        var generatedAssertionInvariants: [NamedInvariant] = []
        var fairness: [FairnessCondition] = []
        var actions = processes.flatMap { process in
            process.steps.enumerated().map { index, atomic in
                let guardExpression = StateExpr.equal(
                    .functionApply(.variable(controlVariable), .variable(processBinding)),
                    .value(.string(atomic.label.name)))
                let nextLabel = process.steps.indices.contains(index + 1)
                    ? process.steps[index + 1].label.name
                    : doneLabel
                let loweredStatements = lower(
                    atomic.statements,
                    localRoots: localRoots,
                    processDomain: process.domain
                )
                let body: ActionExpr
                if let loopCondition = atomic.loopCondition {
                    body = .ifElse(
                        rewrite(loopCondition, localRoots: localRoots),
                        completingControl(loweredStatements, fallthrough: atomic.label.name),
                        transfer(to: nextLabel)
                    )
                } else {
                    body = completingControl(loweredStatements, fallthrough: nextLabel)
                }
                let generatedAction = NamedAction(
                    name: atomic.label.name,
                    body: completeAction(.and(.guard_(guardExpression), body), allVars: variableNames),
                    bindings: [ActionBinding(name: processBinding, values: process.domain)]
                )
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
                fairness += fairnessConditions(for: generatedAction, policy: process.fairness)
                return generatedAction
            }
        }

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

        return TLASpec(
            name: algorithm.name,
            variables: variables,
            actions: actions,
            invariants: declaredInvariants + generatedAssertionInvariants,
            temporalProperties: declaredTemporal,
            fairness: declaredFairness + fairness)
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

    /// Lowers a PlusCal `begin ... end algorithm` body. This is deliberately
    /// not a one-element process: PlusCal gives this form a scalar `pc` and
    /// unparameterized action labels.
    private static func lowerSequential(_ algorithm: AlgorithmModel) -> TLASpec {
        let steps = algorithm.sequentialSteps
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

        var variables = shared.map { state in
            if let initial = try? state.initial.evaluate(in: [:]) {
                NamedVar(name: state.root, initial: initial, initialSet: state.initialSet)
            } else {
                NamedVar(name: state.root, initial: .int(0), initExpr: state.initial)
            }
        }
        guard let first = steps.first else {
            return TLASpec(
                name: algorithm.name,
                variables: variables,
                actions: [],
                invariants: declaredInvariants,
                temporalProperties: declaredTemporal,
                fairness: declaredFairness
            )
        }
        variables.append(NamedVar(name: controlVariable, initial: .string(first.label.name)))
        let variableNames = variables.map(\.name)

        var actions: [NamedAction] = []
        var generatedAssertionInvariants: [NamedInvariant] = []
        for (index, atomic) in steps.enumerated() {
            let nextLabel = steps.indices.contains(index + 1)
                ? steps[index + 1].label.name
                : doneLabel
            let statements = lowerSequential(atomic.statements)
            let body: ActionExpr
            if let condition = atomic.loopCondition {
                body = .ifElse(
                    condition,
                    completingSequentialControl(statements, fallthrough: atomic.label.name),
                    sequentialTransfer(to: nextLabel)
                )
            } else {
                body = completingSequentialControl(statements, fallthrough: nextLabel)
            }
            actions.append(NamedAction(
                name: atomic.label.name,
                body: completeAction(
                    .and(.guard_(.equal(.variable(controlVariable), .value(.string(atomic.label.name)))), body),
                    allVars: variableNames
                )
            ))
            generatedAssertionInvariants += sequentialAssertionInvariants(
                in: atomic.statements,
                label: atomic.label.name,
                executionCondition: atomic.loopCondition,
                pathCondition: .value(.bool(true))
            )
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
            fairness: declaredFairness
        )
    }

    private static func sequentialTransfer(to label: String) -> ActionExpr {
        .assign(controlVariable, .value(.string(label)))
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

    private static func lowerSequential(_ statements: [AlgorithmStatementModel]) -> ActionExpr {
        statements.reduce(.guard_(.value(.bool(true)))) { partial, statement in
            .and(partial, lowerSequential(statement))
        }
    }

    private static func lowerSequential(_ statement: AlgorithmStatementModel) -> ActionExpr {
        switch statement {
        case .await(let condition): return .guard_(condition)
        case .assert: return .guard_(.value(.bool(true)))
        case .set(let target, let value):
            switch target {
            case .root(let root): return .assign(root, value)
            case .function(let root, let key): return .assign(root, .except(.variable(root), key, value))
            }
        case .letBinding(let variable, let value, let body):
            return .define(variable, value, lowerSequential(body))
        case .with(let variable, let source, let body):
            return .existsAction(variable, source, lowerSequential(body))
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(condition, lowerSequential(then), lowerSequential(otherwise))
        case .either(let first, let second):
            return .or(lowerSequential(first), lowerSequential(second))
        case .choose(let variable, let domain, let body):
            return .existsAction(variable, .setLiteral(domain.map(StateExpr.value)), lowerSequential(body))
        case .goto(let label): return sequentialTransfer(to: label.name)
        case .stop: return sequentialTransfer(to: doneLabel)
        case .skip: return .guard_(.value(.bool(true)))
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
            case .await, .set, .goto, .stop, .skip: return []
            }
        }
    }

    /// Algorithm declarations are finite initial values. Keep the initial
    /// state concrete so the checker, parser tree, and generated State agree.
    private static func staticInitialValue(_ expression: StateExpr, named name: String) -> TLAValue {
        guard let value = try? expression.evaluate(in: [:]) else {
            preconditionFailure("Algorithm variable '\(name)' needs a closed formal initial expression.")
        }
        return value
    }

    private static func lower(
        _ statements: [AlgorithmStatementModel],
        localRoots: Set<String>,
        processDomain: [TLAValue]
    ) -> ActionExpr {
        statements.reduce(.guard_(.value(.bool(true)))) { partial, statement in
            .and(partial, lower(statement, localRoots: localRoots, processDomain: processDomain))
        }
    }

    private static func stopAction() -> ActionExpr {
        transfer(to: doneLabel)
    }

    private static func transfer(to label: String) -> ActionExpr {
        .assign(
            controlVariable,
            .except(
                .variable(controlVariable),
                .variable(processBinding),
                .value(.string(label))))
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
        processDomain: [TLAValue]
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
                lower(body, localRoots: localRoots, processDomain: processDomain)
            )
        case .with(let variable, let source, let body):
            return .existsAction(
                variable,
                rewrite(source, localRoots: localRoots),
                lower(body, localRoots: localRoots, processDomain: processDomain))
        case .ifElse(let condition, let then, let otherwise):
            return .ifElse(
                rewrite(condition, localRoots: localRoots),
                lower(then, localRoots: localRoots, processDomain: processDomain),
                lower(otherwise, localRoots: localRoots, processDomain: processDomain))
        case .either(let first, let second):
            return .or(
                lower(first, localRoots: localRoots, processDomain: processDomain),
                lower(second, localRoots: localRoots, processDomain: processDomain))
        case .choose(let variable, let domain, let body):
            return .existsAction(
                variable,
                .setLiteral(domain.map { .value($0) }),
                lower(body, localRoots: localRoots, processDomain: processDomain))
        case .goto(let label):
            return .assign(
                controlVariable,
                .except(
                    .variable(controlVariable),
                    .variable(processBinding),
                    .value(.string(label.name))))
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
            case .await, .set, .goto, .stop, .skip:
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
        case .goto, .stop, .skip: return statement
        }
    }

    private static func rewrite(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
        func rewritten(_ expression: StateExpr, localRoots: Set<String>) -> StateExpr {
            switch expression {
            case .value:
                return expression
            case .variable(let name):
                if name == builderProcessIdentifier { return .variable(processBinding) }
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
            case .recursiveCall(let name, let arguments): return .recursiveCall(name, arguments.map { rewritten($0, localRoots: localRoots) })
            }
        }

        return rewritten(expression, localRoots: localRoots)
    }
}
