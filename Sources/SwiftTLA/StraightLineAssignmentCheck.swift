enum StraightLineAssignmentCheck {
    private enum Term: Hashable {
        case prior(String)
        case parameter(String)
        case literal(TLAValue)
    }

    private struct Requirement: Hashable {
        let term: Term
        let value: Bool
    }

    private struct Delta: Hashable {
        let writes: [String: Term]
        let requirements: Set<Requirement>

        init(writes: [String: Term], requirements: Set<Requirement> = []) {
            self.writes = writes
            self.requirements = requirements
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.writes == rhs.writes && lhs.requirements == rhs.requirements
        }

        func hash(into hasher: inout Hasher) {
            for name in writes.keys.sorted() {
                hasher.combine(name)
                hasher.combine(writes[name])
            }
            hasher.combine(requirements)
        }

        func merging(_ other: Self) -> Self? {
            var combined = writes
            for (name, value) in other.writes {
                if let prior = combined[name], prior != value { return nil }
                combined[name] = value
            }
            for requirement in other.requirements where requirements.contains(
                .init(term: requirement.term, value: !requirement.value)) { return nil }
            return .init(writes: combined, requirements: requirements.union(other.requirements))
        }

        func requiring(_ term: Term, value: Bool) -> Self? {
            if case .literal(.bool(let literal)) = term { return literal == value ? self : nil }
            return merging(.init(writes: [:], requirements: [.init(term: term, value: value)]))
        }
    }

    private enum NormalizationVisit {
        case action(ActionExpr, [String: Term])
        case conjunction
        case alternative
        case conditional(Term)
    }

    private enum Visit {
        case action(ActionExpr)
        case unbind(String)
    }

    private enum CompiledVisit {
        case pair(ActionExpr, CompiledActionExpr)
        case unbind(String)
    }

    private enum ResolvedVisit {
        case scan(CompiledActionExpr)
        case pair(CompiledActionExpr, CompiledActionExpr)
        case unbind(BinderID)
    }

    static func verifyNormalization(_ source: ActionExpr, normalized: ActionExpr,
                                    stateRoots: Set<String>, at path: String) throws {
        func value(_ expression: StateExpr, bindings: [String: Term]) -> Term? {
            switch expression {
            case .variable(let name):
                if let bound = bindings[name] { return bound }
                return stateRoots.contains(name) ? .prior(name) : nil
            case .value(let literal):
                switch literal {
                case .int, .bool: return .literal(literal)
                default: return nil
                }
            default: return nil
            }
        }

        func boolean(_ expression: StateExpr, bindings: [String: Term]) -> Term? {
            guard let term = value(expression, bindings: bindings) else { return nil }
            switch term {
            case .prior, .literal(.bool): return term
            default: return nil
            }
        }

        func outcomes(_ action: ActionExpr) -> [Delta]? {
            var pending: [NormalizationVisit] = [.action(action, [:])]
            var results: [[Delta]] = []
            while let next = pending.popLast() {
                switch next {
                case .action(let node, let bindings):
                    switch node {
                    case .assign(.named(let name), let expression):
                        guard stateRoots.contains(name), let term = value(expression, bindings: bindings) else {
                            return nil
                        }
                        results.append([.init(writes: [name: term])])
                    case .unchanged(.named(let name)):
                        guard stateRoots.contains(name) else { return nil }
                        results.append([.init(writes: [name: .prior(name)])])
                    case .guard_(let predicate):
                        guard let term = boolean(predicate, bindings: bindings) else { return nil }
                        results.append(Delta(writes: [:]).requiring(term, value: true).map { [$0] } ?? [])
                    case .define(let name, let expression, let body):
                        guard let term = value(expression, bindings: bindings) else { return nil }
                        var scoped = bindings
                        scoped[name] = term
                        pending.append(.action(body, scoped))
                    case .and(let left, let right):
                        pending.append(.conjunction)
                        pending.append(.action(right, bindings))
                        pending.append(.action(left, bindings))
                    case .or(let left, let right):
                        pending.append(.alternative)
                        pending.append(.action(right, bindings))
                        pending.append(.action(left, bindings))
                    case .ifElse(let predicate, let yes, let no):
                        guard let term = boolean(predicate, bindings: bindings) else { return nil }
                        pending.append(.conditional(term))
                        pending.append(.action(no, bindings))
                        pending.append(.action(yes, bindings))
                    default: return nil
                    }
                case .conjunction:
                    let right = results.removeLast()
                    let left = results.removeLast()
                    results.append(left.flatMap { first in right.compactMap { first.merging($0) } })
                case .alternative:
                    let right = results.removeLast()
                    let left = results.removeLast()
                    results.append(left + right)
                case .conditional(let term):
                    let no = results.removeLast()
                    let yes = results.removeLast()
                    results.append(yes.compactMap { $0.requiring(term, value: true) } +
                        no.compactMap { $0.requiring(term, value: false) })
                }
            }
            return results.count == 1 ? results[0] : nil
        }

        guard let sourceOutcomes = outcomes(source) else { return }
        let expected = Set(sourceOutcomes.map { delta in
            Delta(writes: stateRoots.reduce(into: delta.writes) { writes, name in
                if writes[name] == nil { writes[name] = .prior(name) }
            }, requirements: delta.requirements)
        })
        guard let actual = outcomes(normalized),
              actual.allSatisfy({ Set($0.writes.keys) == stateRoots }),
              Set(actual) == expected else {
            throw CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: path,
                expected: "the same complete successor relation and frame as the source scalar action",
                actual: "action normalization changed a branch, assignment, or frame",
                nextSafeAction: "Report this action-normalization failure."
            )
        }
    }

    static func verifySequential(_ algorithm: AlgorithmModel, lowered: TLASpec,
                                 enumerateInitialControl: Bool) throws {
        let steps = algorithm.sequentialSteps
        guard steps.contains(where: { $0.loopCondition == nil }) else { return }
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "algorithms.\(algorithm.name).sequentialShape",
                expected: "the source variables, initial control, and labeled steps",
                actual: "the lowered sequential model has a different state or action inventory",
                nextSafeAction: "Report this sequential algorithm lowering failure."
            )
        }
        let shared = algorithm.components.compactMap { component -> AlgorithmStateModel? in
            guard case .shared(let state) = component else { return nil }
            return state
        }
        let owner = ControlOwner.sequential(algorithm: algorithm.name)
        let locations = steps.map { StateExpr.controlLocation(.init(owner: owner, sourceName: $0.label.name)) }
        let initialControl: VariableInitialization = enumerateInitialControl
            ? .memberOf(.setLiteral(locations)) : .expression(locations[0])
        guard lowered.variables.count == shared.count + 1,
              lowered.variables[0].origin == .programCounter,
              lowered.variables[0].name == CompilerControlSymbol.programCounter.rawValue,
              lowered.variables[0].initialization == initialControl,
              zip(lowered.variables.dropFirst(), shared).allSatisfy({ variable, source in
                  variable.origin == .source && variable.name == source.root &&
                  variable.initialization == source.initialization &&
                  variable.generatedSwiftType == source.swiftTypeName &&
                  variable.resolvedValueType == source.resolvedValueType &&
                  variable.displayLabel == source.displayLabel
              }),
              lowered.actions.count == steps.count + 1,
              lowered.actions.last?.isTermination == true,
              lowered.actions.last?.name == CompilerControlSymbol.terminatingAction.rawValue,
              zip(lowered.actions, steps).allSatisfy({ action, step in
                  !action.isTermination && action.name == step.label.name
              }) else { throw mismatch() }
        let roots = Set(shared.map(\.root))
        for (index, step) in steps.enumerated() where step.loopCondition == nil {
            let entry = ControlLocationReference(owner: owner, sourceName: step.label.name)
            let next = steps.indices.contains(index + 1)
                ? ControlLocationReference(owner: owner, sourceName: steps[index + 1].label.name)
                : ControlLocationReference(owner: .generated(algorithm: algorithm.name,
                    purpose: CompilerControlSymbol.done.rawValue),
                    sourceName: CompilerControlSymbol.done.rawValue)
            try verify(AtomicStep(model: step),
                lowered: lowered.actions[index].bindings.isEmpty ? lowered.actions[index].body : nil,
                stateRoots: roots, control: (entry, next))
        }
    }

    static func verify(_ step: AtomicStep, lowered: ActionExpr?, stateRoots: Set<String>,
                       control: (entry: ControlLocationReference, next: ControlLocationReference)? = nil) throws {
        let parameterNames = step.bindings.map(\.name)
        let parameters = Set(parameterNames)
        guard parameters.count == parameterNames.count,
              parameters.isDisjoint(with: stateRoots) else { return }
        try verifySingleAssignmentCapture(step, lowered: lowered, stateRoots: stateRoots,
            control: control)

        var source: [String: Term] = [:]
        for statement in step.model.statements {
            guard case .set(let target, let expression) = statement,
                  case .root(let root) = target, stateRoots.contains(root) else { return }
            switch expression {
            case .variable(let name) where stateRoots.contains(name):
                source[root] = source[name] ?? .prior(name)
            case .variable(let name) where parameters.contains(name):
                source[root] = .parameter(name)
            case .value(let literal):
                source[root] = .literal(literal)
            default:
                return
            }
        }

        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "actions.\(step.model.label.name).orderedAssignments",
                expected: "the complete symbolic result of the source assignments",
                actual: "the lowered action has a different result or unsupported operation",
                nextSafeAction: "Report this assignment lowering failure."
            )
        }

        func value(_ expression: StateExpr, bindings: [String: Term]) throws -> Term {
            switch expression {
            case .variable(let name):
                if let bound = bindings[name] { return bound }
                guard stateRoots.contains(name) else { throw mismatch() }
                return .prior(name)
            case .value(let literal):
                return .literal(literal)
            default:
                throw mismatch()
            }
        }

        var writes: [String: Term] = [:]
        var assignedRoots: Set<String> = []
        var bindings = Dictionary(uniqueKeysWithValues: parameterNames.map { ($0, Term.parameter($0)) })
        guard let lowered else { throw mismatch() }
        var sawControlGuard = false
        var sawControlWrite = false
        var pending: [Visit] = [.action(lowered)]
        while let next = pending.popLast() {
            guard case .action(let action) = next else {
                if case .unbind(let name) = next { bindings.removeValue(forKey: name) }
                continue
            }
            switch action {
            case .define(let name, let expression, let body):
                guard !stateRoots.contains(name), bindings[name] == nil else { throw mismatch() }
                bindings[name] = try value(expression, bindings: bindings)
                pending.append(.unbind(name))
                pending.append(.action(body))
            case .and(let left, let right):
                pending.append(.action(right))
                pending.append(.action(left))
            case .guard_(.value(.bool(true))):
                break
            case .guard_(.equal(.programCounter, .controlLocation(let location))):
                guard let control, location == control.entry, !sawControlGuard else { throw mismatch() }
                sawControlGuard = true
            case .assign(.programCounter, .controlLocation(let location)):
                guard let control, location == control.next, !sawControlWrite else { throw mismatch() }
                sawControlWrite = true
            case .assign(.named(let root), let expression):
                guard stateRoots.contains(root), assignedRoots.insert(root).inserted else {
                    throw mismatch()
                }
                let assigned = try value(expression, bindings: bindings)
                guard writes[root] == nil || writes[root] == assigned else { throw mismatch() }
                writes[root] = assigned
            case .unchanged(.named(let root)):
                guard stateRoots.contains(root),
                      writes[root] == nil || writes[root] == .prior(root) else { throw mismatch() }
                writes[root] = .prior(root)
            default:
                throw mismatch()
            }
        }

        if case .some = control, !(sawControlGuard && sawControlWrite) { throw mismatch() }
        guard assignedRoots == Set(source.keys),
              stateRoots.allSatisfy({ (writes[$0] ?? .prior($0)) == (source[$0] ?? .prior($0)) }) else {
            throw mismatch()
        }
    }

    private static func verifySingleAssignmentCapture(
        _ step: AtomicStep, lowered: ActionExpr?, stateRoots: Set<String>,
        control: (entry: ControlLocationReference, next: ControlLocationReference)?
    ) throws {
        guard step.model.statements.count == 1,
              case .set(let target, let expression) = step.model.statements[0],
              case .root(let root) = target, stateRoots.contains(root) else { return }
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "actions.\(step.model.label.name).singleAssignmentCapture",
                expected: "one guarded evaluation of the source expression followed by its captured write and unchanged frame",
                actual: "the lowered action changed the expression, capture, write, or frame",
                nextSafeAction: "Report this single-assignment lowering failure."
            )
        }
        guard let lowered else { throw mismatch() }
        var capture: String?
        var writes: [String: StateExpr] = [:]
        var sawControlGuard = false
        var sawControlWrite = false
        var pending: [(action: ActionExpr, activeCapture: String?)] = [(lowered, nil)]
        while let (action, activeCapture) = pending.popLast() {
            switch action {
            case .define(let name, let value, let body):
                guard capture == nil, activeCapture == nil, !stateRoots.contains(name),
                      !step.bindings.contains(where: { $0.name == name }),
                      !expression.freeVariableNames.contains(name),
                      control == nil || sawControlGuard,
                      value == expression else { throw mismatch() }
                capture = name
                pending.append((body, name))
            case .and(let left, let right):
                pending.append((right, activeCapture))
                pending.append((left, activeCapture))
            case .guard_(.value(.bool(true))):
                break
            case .guard_(.equal(.programCounter, .controlLocation(let location))):
                guard let control, location == control.entry, !sawControlGuard else { throw mismatch() }
                sawControlGuard = true
            case .assign(.programCounter, .controlLocation(let location)):
                guard let control, location == control.next, !sawControlWrite else { throw mismatch() }
                sawControlWrite = true
            case .assign(.named(let name), let value):
                guard stateRoots.contains(name),
                      name != root || activeCapture == capture && capture != nil,
                      writes.updateValue(value, forKey: name) == nil else {
                    throw mismatch()
                }
            case .unchanged(.named(let name)):
                guard stateRoots.contains(name),
                      writes.updateValue(.variable(name), forKey: name) == nil else {
                    throw mismatch()
                }
            default:
                throw mismatch()
            }
        }
        guard let capture, writes[root] == .variable(capture),
              writes.keys.allSatisfy({ stateRoots.contains($0) }),
              stateRoots.subtracting([root]).allSatisfy({ writes[$0] == nil || writes[$0] == .variable($0) }),
              control == nil || (sawControlGuard && sawControlWrite) else { throw mismatch() }
    }

    static func verifyCompiled(_ action: NamedAction, bindings compiledBindings: [CompiledActionBinding],
                               body: CompiledActionExpr,
                               layout: CompiledLayout) throws {
        guard action.bindings.allSatisfy({ binding in
            binding.literalMembers?.allSatisfy { member in
                if case .int = member { return true }
                if case .bool = member { return true }
                return false
            } == true
        }) else { return }
        let stateIDs = Dictionary(uniqueKeysWithValues: layout.variables.map {
            ($0.declaration.name, $0.id)
        })
        let parameterNames = Set(action.bindings.map(\.name))
        var pendingSource = [action.body]
        var definedNames: Set<String> = []
        var readNames: Set<String> = []
        while let node = pendingSource.popLast() {
            switch node {
            case .define(let name, let expression, let child):
                guard definedNames.insert(name).inserted else { return }
                guard simple(expression, reads: &readNames) else { return }
                pendingSource.append(child)
            case .and(let left, let right), .or(let left, let right):
                pendingSource.append(right)
                pendingSource.append(left)
            case .guard_(let predicate):
                guard simple(predicate, reads: &readNames) else { return }
            case .assign(.named, let expression):
                guard simple(expression, reads: &readNames) else { return }
            case .assign(.programCounter, let expression):
                guard simple(expression, reads: &readNames) else { return }
            case .unchanged(.named):
                break
            case .ifElse(let predicate, let yes, let no):
                guard simple(predicate, reads: &readNames) else { return }
                pendingSource.append(no)
                pendingSource.append(yes)
            default:
                return
            }
        }
        guard parameterNames.count == action.bindings.count,
              parameterNames.isDisjoint(with: Set(stateIDs.keys)),
              parameterNames.isDisjoint(with: definedNames),
              readNames.isSubset(of: Set(stateIDs.keys).union(definedNames).union(parameterNames))
        else { return }

        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "actions.\(action.name).compiledAssignments",
                expected: "the source assignment constructors, values, and identities",
                actual: "the compiled action differs from the source action",
                nextSafeAction: "Report this compiled assignment lowering failure."
            )
        }
        func matching(_ source: StateExpr, _ compiled: CompiledExpression,
                      bindings: [String: BinderID]) -> Bool {
            var pending = [(source, compiled)]
            while let (source, compiled) = pending.popLast() {
                switch source {
                case .add(let left, let right):
                    guard compiled.operation == .add, compiled.children.count == 2 else { return false }
                    pending.append((right, compiled.children[1]))
                    pending.append((left, compiled.children[0]))
                case .equal(let left, let right):
                    guard compiled.operation == .equal, compiled.children.count == 2 else { return false }
                    pending.append((right, compiled.children[1]))
                    pending.append((left, compiled.children[0]))
                case .programCounter:
                    guard compiled.children.isEmpty, let id = layout.programCounterID(),
                          compiled.operation == .stateVariable(id) else { return false }
                case .controlLocation(let reference):
                    let matches = layout.controlLocations.filter { location in
                        location.sourceName == reference.sourceName
                            && (reference.owner.map { $0 == location.owner } ?? true)
                    }
                    guard compiled.children.isEmpty, matches.count == 1,
                          let id = matches.first?.id,
                          compiled.operation == .controlLocation(id) else { return false }
                case .variable(let name):
                    guard compiled.children.isEmpty else { return false }
                    if let binder = bindings[name] {
                        guard compiled.operation == .boundValue(binder) else { return false }
                    } else {
                        guard let variable = stateIDs[name],
                              compiled.operation == .stateVariable(variable) else { return false }
                    }
                case .value(let value):
                    guard compiled.children.isEmpty,
                          compiled.operation == .value(CompiledValue(formal: value)) else { return false }
                default: return false
                }
            }
            return true
        }

        guard action.bindings.count == compiledBindings.count else { throw mismatch() }
        for (source, compiled) in zip(action.bindings, compiledBindings) {
            guard source.name == compiled.sourceName,
                  let sourceMembers = source.literalMembers,
                  let compiledMembers = compiled.literalMembers,
                  Set(sourceMembers.map(CompiledValue.init(formal:))) == Set(compiledMembers)
            else { throw mismatch() }
        }
        var usedBinders = Set(compiledBindings.map(\.binder))
        guard usedBinders.count == compiledBindings.count else { throw mismatch() }
        var bindings = Dictionary(uniqueKeysWithValues: zip(action.bindings, compiledBindings)
            .map { ($0.name, $1.binder) })
        var pending: [CompiledVisit] = [.pair(action.body, body)]
        while let next = pending.popLast() {
            switch next {
            case .unbind(let name):
                bindings.removeValue(forKey: name)
            case .pair(let source, let compiled):
                switch (source, compiled) {
                case (.define(let name, let expression, let child),
                      .define(let binder, let value, let compiledChild)):
                    guard bindings[name] == nil, usedBinders.insert(binder).inserted,
                          matching(expression, value, bindings: bindings) else { throw mismatch() }
                    bindings[name] = binder
                    pending.append(.unbind(name))
                    pending.append(.pair(child, compiledChild))
                case (.and(let left, let right), .and(let compiledLeft, let compiledRight)):
                    pending.append(.pair(right, compiledRight))
                    pending.append(.pair(left, compiledLeft))
                case (.or(let left, let right), .or(let compiledLeft, let compiledRight)):
                    pending.append(.pair(right, compiledRight))
                    pending.append(.pair(left, compiledLeft))
                case (.guard_(let predicate), .guard_(let value)):
                    guard matching(predicate, value, bindings: bindings) else { throw mismatch() }
                case (.ifElse(let predicate, let yes, let no),
                      .ifElse(let value, let compiledYes, let compiledNo)):
                    guard matching(predicate, value, bindings: bindings) else { throw mismatch() }
                    pending.append(.pair(no, compiledNo))
                    pending.append(.pair(yes, compiledYes))
                case (.assign(.named(let name), let expression), .assign(let id, let value)):
                    guard stateIDs[name] == id, matching(expression, value, bindings: bindings) else {
                        throw mismatch()
                    }
                case (.assign(.programCounter, let expression), .assign(let id, let value)):
                    guard id == layout.programCounterID(),
                          matching(expression, value, bindings: bindings) else { throw mismatch() }
                case (.unchanged(.named(let name)), .unchanged(let id)):
                    guard stateIDs[name] == id else { throw mismatch() }
                default:
                    throw mismatch()
                }
            }
        }
    }

    private static func simple(_ expression: StateExpr, reads: inout Set<String>) -> Bool {
        var pending = [expression]
        while let node = pending.popLast() {
            switch node {
            case .variable(let name): reads.insert(name)
            case .value: break
            case .add(let left, let right):
                pending.append(right)
                pending.append(left)
            case .equal(let left, let right):
                pending.append(right)
                pending.append(left)
            case .programCounter, .controlLocation: break
            default: return false
            }
        }
        return true
    }

    static func verifyResolved(_ original: CompiledAction, resolved: CompiledAction?,
                               variableTypes: [VariableID: CompiledValueType],
                               resolvedVariableTypes: [VariableID: CompiledValueType],
                               resolvedBindingTypes: [BinderID: CompiledValueType]) throws {
        func scalar(_ type: CompiledValueType?) -> Bool { type == .int || type == .bool }
        func parameterType(_ binding: CompiledActionBinding) -> CompiledValueType? {
            guard let members = binding.literalMembers, let first = members.first else { return nil }
            let type: CompiledValueType
            switch first {
            case .integer: type = .int
            case .boolean: type = .bool
            default: return nil
            }
            guard members.allSatisfy({ member in
                switch (type, member) {
                case (.int, .integer), (.bool, .boolean): true
                default: false
                }
            }) else { return nil }
            return type
        }
        guard original.bindings.allSatisfy({ parameterType($0) != nil }) else { return }
        let parameterIDs = Set(original.bindings.map(\.binder))
        guard parameterIDs.count == original.bindings.count else { return }
        let parameterTypes = Dictionary(uniqueKeysWithValues: original.bindings.map {
            ($0.binder, parameterType($0)!)
        })
        func nodeType(_ expression: CompiledExpression,
                      bindings: [BinderID: CompiledValueType]) -> CompiledValueType? {
            switch expression.operation {
            case .add: return expression.children.count == 2 ? .int : nil
            case .stateVariable(let id):
                guard expression.children.isEmpty else { return nil }
                guard let type = variableTypes[id] else { return nil }
                return type == .unknown ? resolvedVariableTypes[id] : type
            case .boundValue(let id): return expression.children.isEmpty ? bindings[id] : nil
            case .value(.integer): return expression.children.isEmpty ? .int : nil
            case .value(.boolean): return expression.children.isEmpty ? .bool : nil
            default: return nil
            }
        }
        func expressionType(_ expression: CompiledExpression,
                            bindings: [BinderID: CompiledValueType],
                            reads: inout Set<VariableID>) -> CompiledValueType? {
            guard let rootType = nodeType(expression, bindings: bindings) else { return nil }
            var pending = [(expression, rootType)]
            while let (node, expected) = pending.popLast() {
                guard nodeType(node, bindings: bindings) == expected else { return nil }
                if case .stateVariable(let id) = node.operation { reads.insert(id) }
                if case .add = node.operation {
                    pending.append((node.children[1], .int))
                    pending.append((node.children[0], .int))
                }
            }
            return rootType
        }

        var bindings = parameterTypes
        var seenBinders = parameterIDs
        var usedVariables: Set<VariableID> = []
        var inferredBindings = parameterTypes
        var pending: [ResolvedVisit] = [.scan(original.body)]
        while let next = pending.popLast() {
            switch next {
            case .unbind(let id): bindings.removeValue(forKey: id)
            case .pair: break
            case .scan(let node):
                switch node {
                case .define(let id, let value, let body):
                    guard seenBinders.insert(id).inserted,
                          let type = expressionType(value, bindings: bindings,
                              reads: &usedVariables), scalar(type) else { return }
                    bindings[id] = type
                    inferredBindings[id] = type
                    pending.append(.unbind(id))
                    pending.append(.scan(body))
                case .and(let left, let right), .or(let left, let right):
                    pending.append(.scan(right))
                    pending.append(.scan(left))
                case .assign(let id, let value):
                    guard let type = expressionType(value, bindings: bindings,
                                  reads: &usedVariables), scalar(type),
                          variableTypes[id] == type || (variableTypes[id] == .unknown
                              && resolvedVariableTypes[id] == type) else { return }
                    usedVariables.insert(id)
                case .unchanged(let id):
                    guard scalar(variableTypes[id])
                        || (variableTypes[id] == .unknown && scalar(resolvedVariableTypes[id])) else { return }
                    usedVariables.insert(id)
                case .guard_(let value):
                    guard expressionType(value, bindings: bindings,
                              reads: &usedVariables) == .bool else { return }
                case .ifElse(let value, let yes, let no):
                    guard expressionType(value, bindings: bindings,
                              reads: &usedVariables) == .bool else { return }
                    pending.append(.scan(no))
                    pending.append(.scan(yes))
                default: return
                }
            }
        }

        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "actions[\(original.id.ordinal)].resolvedAssignments",
                expected: "the same total scalar assignment rule with resolved Int/Boolean values",
                actual: "type checking or resolution changed an action, read, write, or value",
                nextSafeAction: "Report this typed assignment compilation failure."
            )
        }
        guard usedVariables.allSatisfy({ variableTypes[$0] == .unknown
                || resolvedVariableTypes[$0] == variableTypes[$0] }),
              inferredBindings.allSatisfy({ resolvedBindingTypes[$0.key] == $0.value }) else {
            throw mismatch()
        }
        guard let resolved, resolved.id == original.id,
              resolved.bindings.count == original.bindings.count else {
            throw mismatch()
        }
        for (before, after) in zip(original.bindings, resolved.bindings) {
            guard let type = parameterTypes[before.binder],
                  before.binder == after.binder,
                  before.sourceName == after.sourceName,
                  before.generatedSwiftType == after.generatedSwiftType,
                  after.domain.operation == .setLiteral,
                  after.domain.resultType == .set(type),
                  before.domain.children.count == after.domain.children.count,
                  zip(before.domain.children, after.domain.children).allSatisfy({ lhs, rhs in
                      lhs.children.isEmpty && rhs.children.isEmpty
                          && lhs.operation == rhs.operation && rhs.resultType == type
                  }) else { throw mismatch() }
        }
        func same(_ before: CompiledExpression, _ after: CompiledExpression,
                  bindings: [BinderID: CompiledValueType]) -> Bool {
            var reads: Set<VariableID> = []
            guard expressionType(before, bindings: bindings, reads: &reads) != nil else { return false }
            var pending = [(before, after)]
            while let (before, after) = pending.popLast() {
                guard let type = nodeType(before, bindings: bindings),
                      before.operation == after.operation,
                      before.children.count == after.children.count,
                      after.resultType == type else { return false }
                pending.append(contentsOf: zip(before.children, after.children))
            }
            return true
        }
        bindings = parameterTypes
        pending = [.pair(original.body, resolved.body)]
        while let next = pending.popLast() {
            switch next {
            case .unbind(let id): bindings.removeValue(forKey: id)
            case .scan: break
            case .pair(let before, let after):
                switch (before, after) {
                case (.define(let firstID, let firstValue, let firstBody),
                      .define(let secondID, let secondValue, let secondBody)):
                    guard firstID == secondID,
                          let type = nodeType(firstValue, bindings: bindings),
                          same(firstValue, secondValue, bindings: bindings) else { throw mismatch() }
                    bindings[firstID] = type
                    pending.append(.unbind(firstID))
                    pending.append(.pair(firstBody, secondBody))
                case (.and(let firstLeft, let firstRight), .and(let secondLeft, let secondRight)):
                    pending.append(.pair(firstRight, secondRight))
                    pending.append(.pair(firstLeft, secondLeft))
                case (.or(let firstLeft, let firstRight), .or(let secondLeft, let secondRight)):
                    pending.append(.pair(firstRight, secondRight))
                    pending.append(.pair(firstLeft, secondLeft))
                case (.assign(let firstID, let firstValue), .assign(let secondID, let secondValue)):
                    guard firstID == secondID,
                          same(firstValue, secondValue, bindings: bindings) else { throw mismatch() }
                case (.unchanged(let firstID), .unchanged(let secondID)):
                    guard firstID == secondID else { throw mismatch() }
                case (.guard_(let firstValue), .guard_(let secondValue)):
                    guard same(firstValue, secondValue, bindings: bindings) else { throw mismatch() }
                case (.ifElse(let firstValue, let firstYes, let firstNo),
                      .ifElse(let secondValue, let secondYes, let secondNo)):
                    guard same(firstValue, secondValue, bindings: bindings) else { throw mismatch() }
                    pending.append(.pair(firstNo, secondNo))
                    pending.append(.pair(firstYes, secondYes))
                default: throw mismatch()
                }
            }
        }
    }
}
