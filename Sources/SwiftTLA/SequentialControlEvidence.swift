package struct SequentialControlEvidence: Sendable {
    package struct Machine: Sendable, Equatable {
        package let initial: ControlLocationReference
        package let actions: [Action]
    }

    package struct Action: Sendable, Equatable {
        package let label: String
        package let branches: [Branch]
    }

    package struct Branch: Sendable, Equatable {
        package let observations: [Observation]
        package let control: Control
    }

    package enum Observation: Sendable, Equatable {
        case guardValue(StateExpr)
        case capture(String, StateExpr)
    }

    package enum Control: Sendable, Equatable {
        case transfer(ControlLocationReference)
        case unchanged
    }

    package let authored: Machine
    package let scheduled: Machine
    package let lowered: Machine

    // shortcut: Scalar control only. The control-free endless loop, processes, procedures and selections have distinct owners.
    package static func capture(source: TLASpec, lowered: TLASpec) -> Self? {
        guard source.sourceAlgorithms.count == 1, let algorithm = source.sourceAlgorithms.first?.model,
              algorithm.processes.isEmpty, algorithm.procedures.isEmpty,
              source.sourceAtomicSteps.isEmpty, source.initialInvariantSelections.isEmpty,
              let plan = lowered.authoredPlusCalAlgorithmPlan,
              let first = algorithm.sequentialSteps.first,
              algorithm.sequentialSteps.count > 1 || first.loopCondition != .value(.bool(true)),
              plan.sequentialSteps.map(\.label) == algorithm.sequentialSteps.map(\.label) else { return nil }
        let doneLabel = CompilerControlSymbol.done.rawValue
        let done = ControlLocationReference(owner: .generated(algorithm: algorithm.name, purpose: doneLabel),
                                            sourceName: doneLabel)
        let owner = ControlOwner.sequential(algorithm: algorithm.name)
        let entries = algorithm.sequentialSteps.map { ControlLocationReference(owner: owner, sourceName: $0.label.name) }
        func actions(for steps: [AlgorithmStepModel]) -> [Action]? {
            var actions: [Action] = []
            for (index, step) in steps.enumerated() {
                let entry = entries[index]
                let next = index + 1 < entries.count ? entries[index + 1] : done
                let fallback = step.loopCondition == nil ? next : entry
                guard let body = sourceBranches(step.statements[...], owner: owner, done: done,
                                                fallback: fallback) else { return nil }
                let branches: [Branch]
                if let condition = step.loopCondition {
                    branches = guarded(condition, body)
                        + guarded(.not(condition), [.init(observations: [], control: .transfer(next))])
                } else {
                    branches = body
                }
                actions.append(.init(label: step.label.name, branches: guarded(entryGuard(entry), branches)))
            }
            actions.append(.init(label: CompilerControlSymbol.terminatingAction.rawValue,
                                 branches: [.init(observations: [.guardValue(entryGuard(done))], control: .unchanged)]))
            return actions
        }
        guard let authoredActions = actions(for: algorithm.sequentialSteps),
              let scheduledActions = actions(for: plan.sequentialSteps) else { return nil }
        let counters = lowered.variables.filter { $0.origin == .programCounter }
        guard counters.count == 1, let counter = counters.first,
              case .expression(.controlLocation(let initial)) = counter.initialization else { return nil }
        var loweredActions: [Action] = []
        for action in lowered.actions {
            guard action.bindings.isEmpty else { return nil }
            let paths = ActionNormalization.branches(of: action.body)
            let branches = paths.compactMap { loweredBranch($0, counter: counter.name) }
            guard branches.count == paths.count else { return nil }
            loweredActions.append(.init(label: action.name, branches: branches))
        }
        return .init(authored: .init(initial: entries[0], actions: authoredActions),
                     scheduled: .init(initial: entries[0], actions: scheduledActions),
                     lowered: .init(initial: initial, actions: loweredActions))
    }

    private static func entryGuard(_ location: ControlLocationReference) -> StateExpr {
        .equal(.programCounter, .controlLocation(location))
    }

    private static func guarded(_ condition: StateExpr, _ branches: [Branch]) -> [Branch] {
        switch condition {
        case .value(.bool(true)): return branches
        case .value(.bool(false)): return []
        default: return branches.map { .init(observations: [.guardValue(condition)] + $0.observations, control: $0.control) }
        }
    }

    private static func sourceBranches(_ statements: ArraySlice<AlgorithmStatementModel>,
                                       owner: ControlOwner, done: ControlLocationReference,
                                       fallback: ControlLocationReference) -> [Branch]? {
        var remaining = statements
        var observed: [Observation] = []
        while let statement = remaining.popFirst() {
            switch statement {
            case .when(.value(.bool(false))): return []
            case .when(.value(.bool(true))): continue
            case .when(let condition): observed.append(.guardValue(condition))
            case .set, .parallel, .assert, .skip: continue
            case .goto(let label):
                return [.init(observations: observed,
                              control: .transfer(.init(owner: owner, sourceName: label.name)))]
            case .stop: return [.init(observations: observed, control: .transfer(done))]
            case .letBinding(let name, let value, let body):
                observed.append(.capture(name, value))
                remaining = (body + remaining)[...]
            case .ifElse(let condition, let yes, let no):
                guard let trueBranches = sourceBranches((yes + remaining)[...], owner: owner,
                                                        done: done, fallback: fallback),
                      let falseBranches = sourceBranches((no + remaining)[...], owner: owner,
                                                         done: done, fallback: fallback) else { return nil }
                return (guarded(condition, trueBranches) + guarded(.not(condition), falseBranches)).map {
                    .init(observations: observed + $0.observations, control: $0.control)
                }
            default: return nil
            }
        }
        return [.init(observations: observed, control: .transfer(fallback))]
    }

    private static func loweredBranch(_ branch: ActionExpr, counter: String) -> Branch? {
        var nodes = [branch]
        var observations: [Observation] = []
        var transfer: ControlLocationReference?
        var unchanged = false
        while let node = nodes.popLast() {
            switch node {
            case .and(let left, let right):
                nodes.append(right)
                nodes.append(left)
            case .guard_(.value(.bool(true))): continue
            case .guard_(let condition): observations.append(.guardValue(condition))
            case .define(let name, let value, let body):
                observations.append(.capture(name, value))
                nodes.append(body)
            case .assign(.programCounter, .controlLocation(let location)) where transfer == nil && !unchanged:
                transfer = location
            case .unchanged(.programCounter): unchanged = true
            case .unchanged(.named(let name)) where name == counter: unchanged = true
            case .assign(.named(let name), _) where name != counter: continue
            case .unchanged(.named): continue
            default: return nil
            }
        }
        if let transfer, !unchanged { return .init(observations: observations, control: .transfer(transfer)) }
        if transfer == nil, unchanged { return .init(observations: observations, control: .unchanged) }
        return nil
    }
}
