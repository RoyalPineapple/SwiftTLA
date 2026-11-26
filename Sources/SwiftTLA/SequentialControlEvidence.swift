package struct SequentialControlEvidence: Sendable {
    package struct Machine: Sendable, Equatable {
        package let initial: ControlLocationReference
        package let actions: [Action]

        package func canonicalTraces(sourceWrites: Bool) -> Machine? {
            var observed: [Action] = []
            for action in actions {
                let branches = action.branches.compactMap { $0.canonicalTrace(sourceWrites: sourceWrites) }
                guard branches.count == action.branches.count else { return nil }
                observed.append(.init(label: action.label, branches: branches))
            }
            return .init(initial: initial, actions: observed)
        }
    }

    package struct Action: Sendable, Equatable {
        package let label: String
        package let branches: [Branch]
    }

    package struct Branch: Sendable, Equatable {
        package let observations: [Observation]
        package let control: Control

        package func canonicalTrace(sourceWrites: Bool) -> Branch? {
            var effects: [Observation] = []
            var captures: [String: [StateExpr]] = [:]
            var boundNames: Set<String> = []
            var writes: [String: StateExpr] = [:]

            func value(_ expression: StateExpr) -> StateExpr? {
                let lexical = captures.compactMapValues(\.last)
                let visible = sourceWrites ? writes.merging(lexical) { _, captured in captured } : lexical
                guard expression.freeVariableNames.isDisjoint(with: boundNames.subtracting(visible.keys)) else { return nil }
                return StateExpr.substituteVariables(visible, in: expression)
            }

            for observation in observations {
                switch observation {
                case .guardValue(let expression):
                    guard let evaluated = value(expression) else { return nil }
                    effects.append(.guardValue(evaluated))
                case .capture(let name, let expression):
                    guard let evaluated = value(expression) else { return nil }
                    boundNames.insert(name)
                    captures[name, default: []].append(evaluated)
                    effects.append(.capture("", evaluated))
                case .endCapture(let name):
                    guard captures[name]?.popLast() != nil else { return nil }
                case .write(let name, let expression):
                    guard let evaluated = value(expression), sourceWrites || writes[name] == nil else { return nil }
                    if sourceWrites { effects.append(.capture("", evaluated)) }
                    writes[name] = evaluated
                }
            }
            // Captures are compared by value and visit order. Final writes are simultaneous.
            effects += writes.sorted(by: { $0.key < $1.key }).map { .write($0.key, $0.value) }
            return .init(observations: effects, control: control)
        }
    }

    package enum Observation: Sendable, Equatable {
        case guardValue(StateExpr)
        case capture(String, StateExpr)
        case endCapture(String)
        case write(String, StateExpr)
    }

    package enum Control: Sendable, Equatable {
        case transfer(ControlLocationReference)
        case unchanged
    }

    package let authored: Machine
    package let compilerAuthoredSteps: [AlgorithmStepModel]
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
        guard let authored = authoredMachine(steps: algorithm.sequentialSteps, algorithmName: algorithm.name),
              let scheduled = authoredMachine(steps: plan.sequentialSteps, algorithmName: algorithm.name) else { return nil }
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
        return .init(authored: authored, compilerAuthoredSteps: algorithm.sequentialSteps, scheduled: scheduled,
                     lowered: .init(initial: initial, actions: loweredActions))
    }

    package static func authoredMachine(steps: [AlgorithmStepModel], algorithmName: String) -> Machine? {
        guard !steps.isEmpty else { return nil }
        let doneLabel = CompilerControlSymbol.done.rawValue
        let done = ControlLocationReference(owner: .generated(algorithm: algorithmName, purpose: doneLabel),
                                            sourceName: doneLabel)
        let owner = ControlOwner.sequential(algorithm: algorithmName)
        let entries = steps.map { ControlLocationReference(owner: owner, sourceName: $0.label.name) }
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
        return .init(initial: entries[0], actions: actions)
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
            case .set(.root(let target), let value): observed.append(.write(target, value))
            case .parallel(let assignments):
                for assignment in assignments {
                    guard case .root(let target) = assignment.target else { return nil }
                    observed.append(.write(target, assignment.value))
                }
            case .assert, .skip: continue
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

    private enum LoweredPathMember {
        case expression(ActionExpr)
        case endCapture(String)
    }

    private static func loweredBranch(_ branch: ActionExpr, counter: String) -> Branch? {
        var nodes: [LoweredPathMember] = [.expression(branch)]
        var observations: [Observation] = []
        var transfer: ControlLocationReference?
        var unchanged = false
        while let member = nodes.popLast() {
            guard case .expression(let node) = member else {
                if case .endCapture(let name) = member { observations.append(.endCapture(name)) }
                continue
            }
            switch node {
            case .and(let left, let right):
                nodes.append(.expression(right))
                nodes.append(.expression(left))
            case .guard_(.value(.bool(true))): continue
            case .guard_(let condition): observations.append(.guardValue(condition))
            case .define(let name, let value, let body):
                observations.append(.capture(name, value))
                nodes.append(.endCapture(name))
                nodes.append(.expression(body))
            case .assign(.programCounter, .controlLocation(let location)) where transfer == nil && !unchanged:
                transfer = location
            case .unchanged(.programCounter): unchanged = true
            case .unchanged(.named(let name)) where name == counter: unchanged = true
            case .assign(.named(let name), let expression) where name != counter:
                observations.append(.write(name, expression))
            case .unchanged(.named): continue
            default: return nil
            }
        }
        if let transfer, !unchanged { return .init(observations: observations, control: .transfer(transfer)) }
        if transfer == nil, unchanged { return .init(observations: observations, control: .unchanged) }
        return nil
    }
}


extension SequentialControlEvidence {
    package struct ProcedureActionDomain: Sendable {
        package let label: String
        package let workers: Set<TLAValue>?
        package let owner: ControlOwner
        package let step: AlgorithmStepModel?
        package let following: String?
    }

    package static func procedureActionDomains(in algorithm: AlgorithmModel) -> [ProcedureActionDomain]? {
        let processes = algorithm.processes
        let sequential = algorithm.sequentialSteps
        guard !algorithm.procedures.isEmpty, processes.isEmpty || sequential.isEmpty else { return nil }
        let domains = processes.compactMap { process in
            process.domain.literalSetMembers.map { Set($0) }
        }
        guard domains.count == processes.count else { return nil }
        func rows(_ steps: [AlgorithmStepModel], owner: ControlOwner, workers: Set<TLAValue>?,
                  prefix: String = "") -> [ProcedureActionDomain] {
            steps.enumerated().map { index, step in
                .init(label: prefix + step.label.name, workers: workers, owner: owner, step: step,
                      following: steps.indices.contains(index + 1) ? steps[index + 1].label.name : nil)
            }
        }
        var routes = rows(sequential, owner: .sequential(algorithm: algorithm.name), workers: nil)
        for (index, process) in processes.enumerated() {
            routes += rows(process.steps,
                owner: .process(algorithm: algorithm.name, ordinal: index, typeName: process.typeName),
                workers: domains[index])
        }
        let workers = processes.isEmpty ? nil : domains.reduce(into: Set<TLAValue>()) { $0.formUnion($1) }
        for procedure in algorithm.procedures {
            routes += rows(procedure.steps, owner: .procedure(algorithm: algorithm.name, name: procedure.name),
                           workers: workers, prefix: "procedure.\(procedure.name).")
        }
        routes.append(.init(label: CompilerControlSymbol.terminatingAction.rawValue, workers: nil,
                            owner: .generated(algorithm: algorithm.name, purpose: CompilerControlSymbol.done.rawValue),
                            step: nil, following: nil))
        return routes
    }

    /// A registered procedure While observed by the source frontend before scheduling.
    package struct ProcedureLoopSource: Sendable {
        package let owner: ControlOwner
        package let procedure: String
        package let labels: [String]
        package let slot: Int
        package let sourceOffset: Int
        package let localRoots: Set<String>
        package let condition: StateExpr
        package let body: Branch?
        package let algorithm: AlgorithmModel
        package let fallsThrough: Bool
        package let ownsConfiguredAssertions: Bool

        package var action: String { "procedure.\(procedure).\(labels[slot])" }
    }

    package static func captureProcedureLoops(
        source: TLASpec, declarationOffset: (String) -> Int?
    ) -> [ProcedureLoopSource] {
        guard source.sourceAlgorithms.count == 1, let algorithm = source.sourceAlgorithms.first?.model,
              !algorithm.processes.isEmpty else { return [] }
        func containsOccurrence(
            _ statements: [AlgorithmStatementModel], matching predicate: (AlgorithmStatementModel) -> Bool
        ) -> Bool {
            statements.contains { statement in
                if predicate(statement) { return true }
                switch statement {
                case .letBinding(_, _, let body), .choose(_, _, let body), .with(_, _, let body):
                    return containsOccurrence(body, matching: predicate)
                case .ifElse(_, let yes, let no), .either(let yes, let no):
                    return containsOccurrence(yes, matching: predicate) || containsOccurrence(no, matching: predicate)
                default: return false
                }
            }
        }
        func hasAssertion(_ statements: [AlgorithmStatementModel]) -> Bool {
            containsOccurrence(statements) { statement in
                if case .assert = statement { return true }
                return false
            }
        }
        func hasExplicitTransfer(_ statements: [AlgorithmStatementModel]) -> Bool {
            containsOccurrence(statements) { statement in
                switch statement {
                case .goto, .call, .return, .stop: return true
                default: return false
                }
            }
        }
        // Capture authored write order for the optional straight-line action proof.
        func directWrites(_ statements: [AlgorithmStatementModel], roots: Set<String>) -> [Observation]? {
            var writes: [Observation] = []
            for statement in statements {
                switch statement {
                case .assert: continue // Lowering collects assertions as separate state checks.
                case .skip: continue
                case .set(.root(let target), let value) where roots.contains(target):
                    switch value {
                    case .value(.int), .value(.bool): break
                    case .variable(let read) where roots.contains(read): break
                    default: return nil
                    }
                    writes.append(.write(target, value))
                default: return nil
                }
            }
            return writes
        }
        let sharedRoots = Set(algorithm.components.compactMap { component -> String? in
            guard case .shared(let shared) = component else { return nil }
            return shared.root
        })
        let assertionOwners = (algorithm.sequentialSteps + algorithm.processes.flatMap(\.steps)
                               + algorithm.procedures.flatMap(\.steps)).filter { hasAssertion($0.statements) }.count
        return algorithm.procedures.flatMap { procedure in
            let labels = procedure.steps.map(\.label.name)
            let roots = Set(procedure.parameters.map(\.root) + procedure.locals.map(\.root))
            return procedure.steps.enumerated().compactMap { index, step -> ProcedureLoopSource? in
                guard let condition = step.loopCondition, index + 1 < labels.count,
                      let offset = declarationOffset("procedure.\(procedure.name).\(step.label.name)")
                else { return nil }
                let owner = ControlOwner.procedure(algorithm: algorithm.name, name: procedure.name)
                let entry = ControlLocationReference(owner: owner, sourceName: labels[index])
                let body = directWrites(step.statements, roots: sharedRoots.union(roots)).map {
                    Branch(observations: $0, control: .transfer(entry))
                }
                return .init(owner: owner, procedure: procedure.name, labels: labels, slot: index,
                    sourceOffset: offset, localRoots: roots, condition: condition, body: body, algorithm: algorithm,
                    fallsThrough: !hasExplicitTransfer(step.statements),
                    ownsConfiguredAssertions: assertionOwners == 1 && hasAssertion(step.statements))
            }
        }
    }
}
