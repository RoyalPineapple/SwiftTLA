package enum StraightLineAssignmentCheck {
    package struct ScalarCopyReceipt: Sendable {
        package enum Reference: Equatable, Sendable {
            case state(String)
            case capture(Int)
        }

        package let reads: [Reference]
        package let writes: [String: Reference]
    }

    private struct VerifiedSequentialIntAction {
        let scalarCopy: ScalarCopyReceipt?
    }

    package enum OrderedIntNode: Equatable, Sendable {
        case literal(Int)
        case read(String)
        case add(Int, Int)
        case equal(Int, Int)
        case range(Int, Int)
        case integerSet
        case members([Int])
        case conditional(Int, Int, Int)
    }

    package struct OrderedIntCertificate: Sendable {
        package let source: [OrderedIntNode]
        package let nodes: [OrderedIntNode]
        package let origins: [Int]
        package let indices: [Int]

        fileprivate init(source: [OrderedIntNode], nodes: [OrderedIntNode], origins: [Int], indices: [Int]) {
            self.source = source
            self.nodes = nodes
            self.origins = origins
            self.indices = indices
        }
    }

    package static func orderedIntCertificate(_ root: StateExpr, reads: Set<String>) -> OrderedIntCertificate? {
        // Occurrences, not expression equality: repeated subtrees keep distinct identities.
        var expressions = [root]
        var source: [OrderedIntNode] = []
        var position = 0
        while position < expressions.count {
            switch expressions[position] {
            case .value(.int(let value)): source.append(.literal(value))
            case .variable(let name) where reads.contains(name): source.append(.read(name))
            case .add(let left, let right):
                expressions.append(left)
                let leftOrigin = expressions.count
                expressions.append(right)
                source.append(.add(leftOrigin, expressions.count))
            default: return nil
            }
            position += 1
        }
        var pending = [(origin: 1, expanded: false)]
        var nodes: [OrderedIntNode] = []
        var origins: [Int] = []
        var indices = Array(repeating: 0, count: source.count)
        var completed: [Int] = []
        while let (origin, expanded) = pending.popLast() {
            let node: OrderedIntNode
            switch source[origin - 1] {
            case .literal(let value): node = .literal(value)
            case .read(let name): node = .read(name)
            case .add(let left, let right):
                if !expanded {
                    appendOrderedIntExpansion(origin: origin, left: left, right: right, to: &pending)
                    continue
                }
                guard completed.count >= 2,
                      completed[completed.count - 2] == left,
                      completed[completed.count - 1] == right,
                      indices[left - 1] > 0, indices[right - 1] > 0 else { return nil }
                node = .add(indices[left - 1], indices[right - 1])
                completed.removeLast(2)
            default: return nil
            }
            guard indices[origin - 1] == 0 else { return nil }
            nodes.append(node)
            origins.append(origin)
            indices[origin - 1] = nodes.count
            completed.append(origin)
        }
        guard completed == [1], !indices.contains(0), origins.last == 1 else { return nil }
        return OrderedIntCertificate(source: source, nodes: nodes, origins: origins, indices: indices)
    }

    private static func appendOrderedIntExpansion(origin: Int, left: Int, right: Int,
                                                  to pending: inout [(origin: Int, expanded: Bool)]) {
        pending.append((origin, true))
        pending.append((right, false))
        pending.append((left, false))
    }

    package static func orderedIntPlan(_ root: StateExpr, reads: Set<String>,
                                       renaming: [String: String] = [:],
                                       type: CompiledValueType = .int) -> [OrderedIntNode]? {
        if type == .int {
            return orderedIntCertificate(root, reads: reads)?.nodes.map { node in
                guard case .read(let name) = node else { return node }
                return .read(renaming[name] ?? name)
            }
        }
        var pending = [(root, type, false)]
        var indices: [Int] = []
        var nodes: [OrderedIntNode] = []
        while let (expression, type, expanded) = pending.popLast() {
            let children: [(StateExpr, CompiledValueType)]
            switch (expression, type) {
            case (.integerSet, .set(.int)):
                nodes.append(.integerSet)
                indices.append(nodes.count)
                continue
            case (.value(.int(let value)), .int):
                nodes.append(.literal(value))
                indices.append(nodes.count)
                continue
            case (.variable(let name), .int) where reads.contains(name):
                nodes.append(.read(renaming[name] ?? name))
                indices.append(nodes.count)
                continue
            case (.add(let left, let right), .int),
                 (.equal(let left, let right), .bool),
                 (.integerRange(let left, let right), .set(.int)):
                children = [(left, .int), (right, .int)]
            case (.setLiteral(let values), .set(.int)):
                children = values.map { ($0, .int) }
            case (.ifThenElse(let condition, let yes, let no), .set(.int)):
                children = [(condition, .bool), (yes, .set(.int)), (no, .set(.int))]
            default: return nil
            }
            if !expanded {
                pending.append((expression, type, true))
                pending.append(contentsOf: children.reversed().map { ($0.0, $0.1, false) })
                continue
            }
            guard indices.count >= children.count else { return nil }
            let operands = Array(indices.suffix(children.count))
            indices.removeLast(children.count)
            switch expression {
            case .add: nodes.append(.add(operands[0], operands[1]))
            case .equal: nodes.append(.equal(operands[0], operands[1]))
            case .integerRange: nodes.append(.range(operands[0], operands[1]))
            case .setLiteral: nodes.append(.members(operands))
            case .ifThenElse: nodes.append(.conditional(operands[0], operands[1], operands[2]))
            default: return nil
            }
            indices.append(nodes.count)
        }
        return indices.count == 1 ? nodes : nil
    }

    package static func orderedIntPlan(_ root: CompiledExpression,
                                       names: [VariableID: String],
                                       type: CompiledValueType = .int,
                                       requireTypes: Bool = false) -> [OrderedIntNode]? {
        var pending = [(root, type, false)]
        var indices: [Int] = []
        var nodes: [OrderedIntNode] = []
        while let (expression, type, expanded) = pending.popLast() {
            guard !requireTypes || expression.resultType == type else { return nil }
            let children: [(CompiledExpression, CompiledValueType)]
            switch (expression.operation, type) {
            case (.integerSet, .set(.int)) where expression.children.isEmpty:
                nodes.append(.integerSet)
                indices.append(nodes.count)
                continue
            case (.value(.integer(let value)), .int) where expression.children.isEmpty:
                nodes.append(.literal(value))
                indices.append(nodes.count)
                continue
            case (.stateVariable(let id), .int) where expression.children.isEmpty:
                guard let name = names[id] else { return nil }
                nodes.append(.read(name))
                indices.append(nodes.count)
                continue
            case (.add, .int), (.equal, .bool), (.integerRange, .set(.int)):
                guard expression.children.count == 2 else { return nil }
                children = expression.children.map { ($0, .int) }
            case (.setLiteral, .set(.int)):
                children = expression.children.map { ($0, .int) }
            case (.ifThenElse, .set(.int)):
                guard expression.children.count == 3 else { return nil }
                children = [(expression.children[0], .bool),
                    (expression.children[1], .set(.int)), (expression.children[2], .set(.int))]
            default: return nil
            }
            if !expanded {
                pending.append((expression, type, true))
                pending.append(contentsOf: children.reversed().map { ($0.0, $0.1, false) })
                continue
            }
            guard indices.count >= children.count else { return nil }
            let operands = Array(indices.suffix(children.count))
            indices.removeLast(children.count)
            switch expression.operation {
            case .add: nodes.append(.add(operands[0], operands[1]))
            case .equal: nodes.append(.equal(operands[0], operands[1]))
            case .integerRange: nodes.append(.range(operands[0], operands[1]))
            case .setLiteral: nodes.append(.members(operands))
            case .ifThenElse: nodes.append(.conditional(operands[0], operands[1], operands[2]))
            default: return nil
            }
            indices.append(nodes.count)
        }
        return indices.count == 1 ? nodes : nil
    }

    static func verifyInitialIntExpression(_ source: VariableInitialization,
                                           lowered: CompiledVariableInitialization,
                                           layout: CompiledLayout, at path: String) throws {
        let value: StateExpr
        let type: CompiledValueType
        switch source {
        case .value(.int(let integer)): value = .value(.int(integer)); type = .int
        case .expression(let expression): value = expression; type = .int
        case .memberOf(let domain): value = domain; type = .set(.int)
        default: return
        }
        let names = Dictionary(uniqueKeysWithValues: layout.variables.map {
            ($0.id, $0.declaration.name)
        })
        guard Set(names.values).count == names.count else { throw initialIntMismatch(at: path) }
        // shortcut: other domain and child constructors stay unchecked here; extend with independent constructor rules.
        guard let sourcePlan = orderedIntPlan(value, reads: Set(names.values), type: type) else { return }
        let expression: CompiledExpression
        switch (source, lowered) {
        case (.memberOf, .memberOf(let domain)): expression = domain
        case (.value, .value(let scalar)), (.expression, .value(let scalar)): expression = scalar
        default: throw initialIntMismatch(at: path)
        }
        guard orderedIntPlan(expression, names: names, type: type) == sourcePlan else {
            throw initialIntMismatch(at: path)
        }
    }

    static func verifyResolvedInitialIntExpression(_ original: CompiledVariableInitialization,
                                                   checked: CompiledVariableInitialization?,
                                                   resolved: CompiledVariableInitialization?, at path: String) throws {
        let source: CompiledExpression
        let type: CompiledValueType
        switch original {
        case .value(let expression): source = expression; type = .int
        case .memberOf(let domain): source = domain; type = .set(.int)
        }
        var pending = [source]
        var names: [VariableID: String] = [:]
        while let node = pending.popLast() {
            if case .stateVariable(let id) = node.operation, names[id] == nil {
                names[id] = "state\(names.count)"
            }
            pending.append(contentsOf: node.children)
        }
        guard let sourcePlan = orderedIntPlan(source, names: names, type: type) else { return }
        if case .memberOf = original {
            guard case .memberOf(let domain)? = checked else { throw initialIntMismatch(at: path) }
            // Raw Int enum cases are nominal; establish this Int fragment from source types before resolution.
            guard let checkedPlan = orderedIntPlan(domain, names: names, type: type, requireTypes: true) else { return }
            guard checkedPlan == sourcePlan else { throw initialIntMismatch(at: path) }
        }
        let expression: CompiledExpression
        switch (original, resolved) {
        case (.value, .value(let scalar)?): expression = scalar
        case (.memberOf, .memberOf(let domain)?): expression = domain
        default: throw initialIntMismatch(at: path)
        }
        guard orderedIntPlan(expression, names: names, type: type, requireTypes: true) == sourcePlan else {
            throw initialIntMismatch(at: path)
        }
    }

    private static func initialIntMismatch(at path: String) -> CompilationDiagnostic {
        CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: path, expected: "the same typed Int expression as the source initializer",
            actual: "the compiled initializer changed its value, shape, or type",
            nextSafeAction: "Report this initializer translation failure.")
    }

    static func verifyInitialControlLocation(_ source: VariableInitialization,
                                             lowered: CompiledVariableInitialization,
                                             layout: CompiledLayout, at path: String) throws {
        guard case .expression(.controlLocation(let reference)) = source else { return }
        let matches = layout.controlLocations.filter { location in
            location.sourceName == reference.sourceName &&
                (reference.owner.map { $0 == location.owner } ?? true)
        }
        guard matches.count == 1,
              case .value(let expression) = lowered,
              case .controlLocation(let actual) = expression.operation,
              actual == matches[0].id,
              expression.children.isEmpty else {
            throw initialControlMismatch(at: path)
        }
    }

    static func verifyResolvedInitialControlLocation(_ original: CompiledVariableInitialization,
                                                     resolved: CompiledVariableInitialization?, at path: String) throws {
        guard case .value(let source) = original,
              case .controlLocation(let location) = source.operation,
              source.children.isEmpty else { return }
        guard case .value(let expression)? = resolved,
              case .controlLocation(let actual) = expression.operation,
              actual == location,
              expression.children.isEmpty,
              expression.resultType == .controlLocation else {
            throw initialControlMismatch(at: path)
        }
    }

    private static func initialControlMismatch(at path: String) -> CompilationDiagnostic {
        CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: path, expected: "the source initial control location and type",
            actual: "the compiled initializer changed its location, shape, or type",
            nextSafeAction: "Report this control-location translation failure.")
    }

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

    private enum BranchVisit {
        case action(ActionExpr)
        case conjunction
        case alternative
        case conditional(StateExpr)
    }

    private enum BranchStep: Equatable {
        case action(ActionExpr)
        case conditional(StateExpr, Bool)
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
                                    variables: [NamedVar], at path: String) throws {
        try verifyOrderedBranchNormalization(source, normalized: normalized,
            variables: variables, at: path)
        let stateRoots = Set(variables.map(\.name))
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

    private static func verifyOrderedBranchNormalization(
        _ source: ActionExpr, normalized: ActionExpr, variables: [NamedVar], at path: String
    ) throws {
        func words(_ action: ActionExpr) -> [[BranchStep]]? {
            var pending: [BranchVisit] = [.action(action)]
            var results: [[[BranchStep]]] = []
            while let task = pending.popLast() {
                switch task {
                case .action(let node):
                    switch node {
                    case .assign, .unchanged, .guard_:
                        results.append([[.action(node)]])
                    case .and(let left, let right):
                        pending.append(.conjunction)
                        pending.append(.action(right))
                        pending.append(.action(left))
                    case .or(let left, let right):
                        pending.append(.alternative)
                        pending.append(.action(right))
                        pending.append(.action(left))
                    case .ifElse(let condition, let yes, let no):
                        pending.append(.conditional(condition))
                        pending.append(.action(no))
                        pending.append(.action(yes))
                    case .existsAction, .define:
                        // shortcut: binder trees need their own proved branch rules.
                        return nil
                    }
                case .conjunction:
                    let right = results.removeLast()
                    let left = results.removeLast()
                    results.append(left.flatMap { prefix in
                        if prefix.last == .action(.guard_(.value(.bool(false)))) { return [prefix] }
                        return right.map { prefix + $0 }
                    })
                case .alternative:
                    let right = results.removeLast()
                    let left = results.removeLast()
                    results.append(left + right)
                case .conditional(let condition):
                    let no = results.removeLast()
                    let yes = results.removeLast()
                    results.append(yes.map { [.conditional(condition, true)] + $0 } +
                        no.map { [.conditional(condition, false)] + $0 })
                }
            }
            return results.count == 1 ? results[0] : nil
        }

        guard let expected = words(source) else { return }
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: path, expected: "the source branch order, expression sites, and complete state frame",
                actual: "normalization changed an action branch, evaluation order, or frame",
                nextSafeAction: "Report this action-normalization failure.")
        }
        guard let actual = words(normalized), actual.count == expected.count else { throw mismatch() }
        func identity(_ target: ActionTarget) -> ActionTarget {
            guard case .named(let name) = target,
                  let variable = variables.first(where: { $0.name == name }) else { return target }
            return switch variable.origin {
            case .source, .compiler: .named(variable.name)
            case .programCounter: .programCounter
            case .procedureStack: .procedureStack
            }
        }
        let stateTargets = Set(variables.map { identity(.named($0.name)) })
        for (sourceBranch, normalizedBranch) in zip(expected, actual) {
            guard normalizedBranch.count >= sourceBranch.count,
                  Array(normalizedBranch.prefix(sourceBranch.count)) == sourceBranch else { throw mismatch() }
            var defined: Set<ActionTarget> = []
            var explicitlyUnchanged: Set<ActionTarget> = []
            for action in sourceBranch {
                switch action {
                case .action(.assign(let target, _)):
                    let target = identity(target)
                    guard stateTargets.contains(target) else { return }
                    defined.insert(target)
                case .action(.unchanged(let target)):
                    let target = identity(target)
                    guard stateTargets.contains(target) else { return }
                    defined.insert(target)
                    explicitlyUnchanged.insert(target)
                default: break
                }
            }
            let missing = stateTargets.subtracting(defined)
            let suffix = normalizedBranch.dropFirst(sourceBranch.count)
            let frames = suffix.compactMap { action -> ActionTarget? in
                if case .action(.unchanged(let target)) = action { return identity(target) }
                return nil
            }
            let disabled = sourceBranch.last == .action(.guard_(.value(.bool(false))))
            guard (disabled && suffix.isEmpty) || (!disabled && frames.count == suffix.count &&
                  missing.isSubset(of: Set(frames)) &&
                  Set(frames).subtracting(missing).isSubset(of: explicitlyUnchanged)) else { throw mismatch() }
        }
    }

    static func verifySequential(_ algorithm: AlgorithmModel, lowered: TLASpec,
                                 enumerateInitialControl: Bool) throws -> Set<String> {
        try verifySequential(algorithm, scheduledCopies: [:], lowered: lowered,
            enumerateInitialControl: enumerateInitialControl).actionNames
    }

    static func verifySequential(_ algorithm: AlgorithmModel, scheduledCopies: [String: ScalarCopyReceipt],
                                 lowered: TLASpec, enumerateInitialControl: Bool,
                                 scheduledTargets: [String: [String: String]]? = nil)
        throws -> (actionNames: Set<String>, scalarCopies: [String: ScalarCopyReceipt]) {
        let steps = algorithm.sequentialSteps
        guard steps.contains(where: { $0.loopCondition == nil }) else { return ([], [:]) }
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
              lowered.variables[0].name == StateExpr.freshBoundName(
                  CompilerControlSymbol.programCounter.rawValue, avoiding: Set(shared.map(\.root))),
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
        var orderedIntSteps = !enumerateInitialControl
            && steps.allSatisfy { $0.loopCondition == nil }
            && shared.allSatisfy { $0.swiftTypeName == "Int" }
        var scalarCopies: [String: ScalarCopyReceipt] = [:]
        for (index, step) in steps.enumerated() where step.loopCondition == nil {
            let entry = ControlLocationReference(owner: owner, sourceName: step.label.name)
            let next = steps.indices.contains(index + 1)
                ? ControlLocationReference(owner: owner, sourceName: steps[index + 1].label.name)
                : ControlLocationReference(owner: .generated(algorithm: algorithm.name,
                    purpose: CompilerControlSymbol.done.rawValue),
                    sourceName: CompilerControlSymbol.done.rawValue)
            let atomic = AtomicStep(model: step)
            let action = lowered.actions[index].bindings.isEmpty ? lowered.actions[index].body : nil
            if let verified = try verifySequentialIntAssignments(atomic, lowered: action,
                stateRoots: roots, control: (entry, next), scheduledCopy: scheduledCopies[step.label.name],
                scheduledTargets: orderedIntSteps ? scheduledTargets.map { $0[step.label.name] ?? [:] } : nil) {
                scalarCopies[step.label.name] = verified.scalarCopy
                continue
            }
            orderedIntSteps = false
            try verify(atomic, lowered: action, stateRoots: roots, control: (entry, next))
        }
        if orderedIntSteps {
            let done = StateExpr.controlLocation(.init(
                owner: .generated(algorithm: algorithm.name,
                    purpose: CompilerControlSymbol.done.rawValue),
                sourceName: CompilerControlSymbol.done.rawValue))
            var missingFrames = Set(lowered.variables.map { ActionTarget.named($0.name) })
            var sawDoneGuard = false
            var sawResolvedControlFrame = false
            guard let termination = lowered.actions.last, termination.bindings.isEmpty else { throw mismatch() }
            var pendingTermination = [termination.body]
            while let node = pendingTermination.popLast() {
                switch node {
                case .and(let left, let right):
                    pendingTermination.append(right)
                    pendingTermination.append(left)
                case .guard_(let condition)
                    where condition == .equal(.programCounter, done) && !sawDoneGuard:
                    sawDoneGuard = true
                case .unchanged(.programCounter) where !sawResolvedControlFrame:
                    sawResolvedControlFrame = true
                case .unchanged(let target):
                    guard missingFrames.remove(target) != nil else { throw mismatch() }
                default: throw mismatch()
                }
            }
            guard sawDoneGuard, missingFrames.isEmpty else { throw mismatch() }
        }
        guard orderedIntSteps else { return ([], [:]) }
        return (Set(steps.map(\.label.name) + [CompilerControlSymbol.terminatingAction.rawValue]), scalarCopies)
    }

    static func verify(_ step: AtomicStep, lowered: ActionExpr?, stateRoots: Set<String>,
                       control: (entry: ControlLocationReference, next: ControlLocationReference)? = nil) throws {
        if try verifySequentialIntAssignments(step, lowered: lowered, stateRoots: stateRoots,
                                              control: control) != nil { return }
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

    package struct AtomicBranchContinuationReceipt: Sendable {
        package struct Definition: Sendable {
            package let name: String
            package let rhs: StateExpr
            package let target: String
            package let incomingBindings: [String: StateExpr]
        }

        package struct Branch: Sendable {
            package let definitions: [Definition]?
            package let captures: [[TLAValue]]
            package let sourceCaptures: [[TLAValue]]
            package let targets: [String]
            package let writes: [(root: String, reference: TLAValue)]
        }

        package let fields: Set<String>
        package let prefix: [[TLAValue]]
        package let condition: [TLAValue]?
        package let suffixLength: Int
        package let first: Branch
        package let second: Branch
    }

    private static func atomicBranchTerm(_ expression: StateExpr,
                                         read: (String) -> TLAValue?) -> [TLAValue]? {
        var pending = [expression]
        var terms: [TLAValue] = []
        while let next = pending.popLast() {
            switch next {
            case .variable(let root):
                guard let reference = read(root) else { return nil }
                terms.append(reference)
            case .value(.int(let value)):
                terms.append(.tuple([.string("literal"), .int(value)]))
            case .value(.bool(let value)):
                terms.append(.tuple([.string("literal"), .bool(value)]))
            case .not(let child):
                terms.append(.tuple([.string("not")]))
                pending.append(child)
            case .add(let left, let right), .divide(let left, let right), .modulo(let left, let right),
                 .equal(let left, let right), .lessThan(let left, let right):
                let tag: String = switch next {
                case .add: "add"
                case .divide: "divide"
                case .modulo: "modulo"
                case .lessThan: "lessThan"
                default: "equal"
                }
                terms.append(.tuple([.string(tag)]))
                pending.append(right)
                pending.append(left)
            default:
                return nil
            }
        }
        return terms
    }

    package static func checkedAtomicBranchContinuations(
        _ step: AtomicStep, lowered: ActionExpr, stateRoots: Set<String>, retainingDefinitions: Bool,
        scheduledAssignments: [String: ScheduledAtomicAssignment]? = nil
    ) throws -> AtomicBranchContinuationReceipt? {
        let statements = step.model.statements
        guard step.bindings.isEmpty, let fork = statements.firstIndex(where: {
            if case .ifElse = $0 { return true }
            if case .either = $0 { return true }
            return false
        }) else { return nil }

        let condition: StateExpr?
        let arms: ([AlgorithmStatementModel], [AlgorithmStatementModel])
        switch statements[fork] {
        case .ifElse(let test, let yes, let no):
            condition = test
            arms = (yes, no)
        case .either(let first, let second):
            condition = nil
            arms = (first, second)
        default:
            return nil
        }

        func initial(_ root: String) -> TLAValue? {
            stateRoots.contains(root) ? .tuple([.string("state"), .string(root)]) : nil
        }
        func writes(_ statements: some Sequence<AlgorithmStatementModel>) -> [AlgorithmAssignmentModel]? {
            var assignments: [AlgorithmAssignmentModel] = []
            for statement in statements {
                guard case .set(let target, let expression) = statement,
                      case .root(let root) = target, stateRoots.contains(root),
                      atomicBranchTerm(expression, read: initial) != nil else { return nil }
                assignments.append(.init(target: target, value: expression))
            }
            return assignments
        }
        if let condition, atomicBranchTerm(condition, read: initial) == nil { return nil }
        guard let prefix = writes(statements[..<fork]),
              let yes = writes(arms.0), let no = writes(arms.1),
              let suffix = writes(statements[(fork + 1)...]) else { return nil }

        let failure = CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "actions.\(step.model.label.name).branchContinuations",
            expected: "the authored capture occurrences, selected arm, common continuation, and latest root writes",
            actual: "the lowered branch changed a capture reference, evaluation site, continuation, or frame",
            nextSafeAction: "Report this atomic scheduling failure.")
        let sourceNames = statements.algorithmScopeNames

        struct Captures {
            var remaining: ActionExpr
            var authored: [String: TLAValue] = [:]
            var physical: [String: TLAValue] = [:]
            var plans: [[TLAValue]] = []
            var sourcePlans: [[TLAValue]] = []
            var targets: [String] = []
            var definitions: [AtomicBranchContinuationReceipt.Definition]?
        }
        // StateExpr.replace preserves the constructor tokens for binder-free expressions.
        // Only a source read takes one lookup in the incoming writer map.
        func applyingWrites(_ writes: [String: TLAValue], to source: [TLAValue]) -> [TLAValue] {
            guard !writes.isEmpty else { return source }
            return source.map { term in
                guard case .tuple(let parts) = term, parts.count == 2, parts[0] == .string("state"),
                      case .string(let name) = parts[1] else { return term }
                return writes[name] ?? term
            }
        }
        func advance(_ assignments: [AlgorithmAssignmentModel], from before: Captures) throws -> Captures {
            var result = before
            for assignment in assignments {
                guard case .define(let name, let rhs, let rest) = result.remaining,
                      !sourceNames.contains(name), result.physical[name] == nil,
                      let source = atomicBranchTerm(assignment.value, read: initial),
                      let actual = atomicBranchTerm(rhs, read: { result.physical[$0] ?? initial($0) }),
                      actual == applyingWrites(result.authored, to: source) else { throw failure }
                result.plans.append(actual)
                result.sourcePlans.append(source)
                let target = assignment.target.root
                result.targets.append(target)
                if result.definitions != nil {
                    guard let scheduled = scheduledAssignments?[name],
                          scheduled.target.utf8.elementsEqual(target.utf8) else { throw failure }
                    result.definitions?.append(.init(name: name, rhs: rhs, target: scheduled.target,
                        incomingBindings: scheduled.incomingBindings))
                }
                let reference: TLAValue = .tuple([.string("capture"), .int(result.plans.count)])
                result.authored[target] = reference
                result.physical[name] = reference
                result.remaining = rest
            }
            return result
        }

        func publish(_ branch: Captures) throws -> AtomicBranchContinuationReceipt.Branch {
            var published: [String: TLAValue] = [:]
            var ordered: [(String, TLAValue)] = []
            var pending = [branch.remaining]
            while let node = pending.popLast() {
                let root: String
                let reference: TLAValue
                switch node {
                case .and(let left, let right):
                    pending.append(right)
                    pending.append(left)
                    continue
                case .guard_(.value(.bool(true))):
                    continue
                case .assign(.named(let name), .variable(let capture)):
                    guard let resolved = branch.physical[capture] else { throw failure }
                    root = name
                    reference = resolved
                case .unchanged(.named(let name)):
                    guard let original = initial(name) else { throw failure }
                    root = name
                    reference = original
                default:
                    throw failure
                }
                guard published.updateValue(reference, forKey: root) == nil else { throw failure }
                ordered.append((root, reference))
            }
            var expected = branch.authored
            for root in stateRoots where expected[root] == nil { expected[root] = initial(root) }
            guard published == expected else { throw failure }
            return .init(definitions: branch.definitions, captures: branch.plans,
                         sourceCaptures: branch.sourcePlans, targets: branch.targets, writes: ordered)
        }

        let preceding = try advance(prefix, from: .init(remaining: lowered,
            definitions: retainingDefinitions ? [] : nil))
        let predicate: [TLAValue]?
        let actual: (ActionExpr, ActionExpr)
        switch (condition, preceding.remaining) {
        case (.some(let test), .ifElse(let rendered, let first, let second)):
            guard let source = atomicBranchTerm(test, read: initial),
                  let observed = atomicBranchTerm(rendered, read: { preceding.physical[$0] ?? initial($0) }),
                  observed == applyingWrites(preceding.authored, to: source) else { throw failure }
            predicate = observed
            actual = (first, second)
        case (.none, .or(let first, let second)):
            predicate = nil
            actual = (first, second)
        default:
            throw failure
        }

        func finish(_ instructions: [AlgorithmAssignmentModel], using action: ActionExpr) throws
            -> AtomicBranchContinuationReceipt.Branch {
            var input = preceding
            input.remaining = action
            return try publish(advance(instructions, from: input))
        }
        return try .init(fields: stateRoots, prefix: preceding.plans, condition: predicate, suffixLength: suffix.count,
            first: finish(yes + suffix, using: actual.0), second: finish(no + suffix, using: actual.1))
    }

    private static func verifySequentialIntAssignments(
        _ step: AtomicStep, lowered: ActionExpr?, stateRoots: Set<String>,
        control: (entry: ControlLocationReference, next: ControlLocationReference)?,
        scheduledCopy: ScalarCopyReceipt? = nil, scheduledTargets: [String: String]? = nil
    ) throws -> VerifiedSequentialIntAction? {
        guard control != nil, step.bindings.isEmpty, !step.model.statements.isEmpty else { return nil }
        var source: [(root: String, expression: StateExpr)] = []
        for statement in step.model.statements {
            guard case .set(.root(let root), let expression) = statement,
                  stateRoots.contains(root),
                  orderedIntPlan(expression, reads: stateRoots) != nil else { return nil }
            source.append((root, expression))
        }
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "actions.\(step.model.label.name).orderedAssignments",
                expected: "ordered Int captures, complete root writes, and exact control transfer",
                actual: "the lowered action changes an ordered value, write, or control location",
                nextSafeAction: "Report this sequential assignment lowering failure.")
        }
        guard let lowered, let control else { throw mismatch() }
        var current = Dictionary(uniqueKeysWithValues: stateRoots.map { ($0, $0) })
        func matches(_ authored: StateExpr, _ actual: StateExpr) -> Bool {
            guard Set(current.values).count == current.count else { return false }
            if case .variable(let sourceRoot) = authored, case .variable(let actualName) = actual {
                return current[sourceRoot] == actualName
            }
            let roots = Set(current.keys)
            let inverse = Dictionary(uniqueKeysWithValues: current.map { ($0.value, $0.key) })
            guard let sourcePlan = orderedIntPlan(authored, reads: roots),
                  let loweredPlan = orderedIntPlan(actual, reads: Set(inverse.keys),
                                                   renaming: inverse) else { return false }
            return sourcePlan == loweredPlan
        }
        var captured = 0
        var capturePositions: [String: Int] = [:]
        func reference(_ name: String) -> ScalarCopyReceipt.Reference {
            if let position = capturePositions[name] { return .capture(position) }
            return .state(name)
        }
        var guardSeen = false
        var controlWriteSeen = false
        var writes: [String: String] = [:]
        var pending = [lowered]
        while let action = pending.popLast() {
            switch action {
            case .and(let left, let right):
                pending.append(right)
                pending.append(left)
            case .guard_(.equal(.programCounter, .controlLocation(let location))):
                guard !guardSeen, captured == 0, location == control.entry else { throw mismatch() }
                guardSeen = true
            case .guard_(.value(.bool(true))): break
            case .define(let name, let value, let body):
                guard guardSeen, captured < source.count, writes.isEmpty,
                      !stateRoots.contains(name),
                      capturePositions[name] == nil,
                      matches(source[captured].expression, value) else { throw mismatch() }
                if let scheduledTargets {
                    guard scheduledTargets[name]?.utf8.elementsEqual(source[captured].root.utf8) == true
                    else { throw mismatch() }
                }
                if let scheduledCopy {
                    guard case .variable(let read) = value,
                          scheduledCopy.reads.indices.contains(captured),
                          scheduledCopy.reads[captured] == reference(read) else { throw mismatch() }
                }
                current[source[captured].root] = name
                captured += 1
                capturePositions[name] = captured
                pending.append(body)
            case .assign(.programCounter, .controlLocation(let location)):
                guard captured == source.count, !controlWriteSeen,
                      location == control.next else { throw mismatch() }
                controlWriteSeen = true
            case .assign(.named(let root), .variable(let value)):
                guard captured == source.count, stateRoots.contains(root),
                      writes.updateValue(value, forKey: root) == nil else { throw mismatch() }
            case .unchanged(.named(let root)):
                guard captured == source.count, stateRoots.contains(root),
                      writes.updateValue(root, forKey: root) == nil else { throw mismatch() }
            default: throw mismatch()
            }
        }
        guard guardSeen, controlWriteSeen, captured == source.count,
              writes.count == stateRoots.count,
              stateRoots.allSatisfy({ writes[$0] == current[$0] }) else { throw mismatch() }
        if let scheduledTargets {
            guard scheduledTargets.count == captured else { throw mismatch() }
        }
        if let scheduledCopy {
            guard scheduledCopy.reads.count == captured,
                  scheduledCopy.writes == writes.mapValues(reference) else { throw mismatch() }
        }
        return VerifiedSequentialIntAction(scalarCopy: scheduledCopy)
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

    @discardableResult
    static func verifyCompiled(_ action: NamedAction, bindings compiledBindings: [CompiledActionBinding],
                               body: CompiledActionExpr,
                               layout: CompiledLayout, bodyBinderOrdinals: Range<Int>? = nil) throws -> Range<Int>? {
        let stateIDs = Dictionary(uniqueKeysWithValues: layout.variables.map {
            ($0.declaration.name, $0.id)
        })
        func targetID(_ target: ActionTarget) -> VariableID? {
            switch target {
            case .named(let name): return stateIDs[name]
            case .programCounter: return layout.programCounterID()
            case .procedureStack: return layout.procedureStackID()
            }
        }
        func frameMismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "actions.\(action.name).compiledFrames",
                expected: "the source action structure and state-variable targets",
                actual: "the compiled action changes a constructor or state-variable target",
                nextSafeAction: "Report this action lowering failure.")
        }
        var actionPairs: [(ActionExpr, CompiledActionExpr)] = [(action.body, body)]
        while let (source, compiled) = actionPairs.popLast() {
            switch (source, compiled) {
            case (.assign(let target, _), .assign(let id, _)),
                 (.unchanged(let target), .unchanged(let id)):
                guard targetID(target) == id else { throw frameMismatch() }
            case (.guard_, .guard_): break
            case (.existsAction(_, _, let child), .existsAction(_, _, let lowered)),
                 (.define(_, _, let child), .define(_, _, let lowered)):
                actionPairs.append((child, lowered))
            case (.ifElse(_, let yes, let no), .ifElse(_, let loweredYes, let loweredNo)):
                actionPairs.append((no, loweredNo))
                actionPairs.append((yes, loweredYes))
            case (.and(let left, let right), .and(let loweredLeft, let loweredRight)),
                 (.or(let left, let right), .or(let loweredLeft, let loweredRight)):
                actionPairs.append((right, loweredRight))
                actionPairs.append((left, loweredLeft))
            default: throw frameMismatch()
            }
        }
        guard action.bindings.allSatisfy({ binding in
            binding.literalMembers?.allSatisfy { member in
                if case .int = member { return true }
                if case .bool = member { return true }
                return false
            } == true
        }) else { return nil }
        let parameterNames = Set(action.bindings.map(\.name))
        var pendingSource = [action.body]
        var definedNames: Set<String> = []
        var readNames: Set<String> = []
        let checkingBodyBinderOrdinals = bodyBinderOrdinals != nil
        while let node = pendingSource.popLast() {
            switch node {
            case .define(let name, let expression, let child):
                guard definedNames.insert(name).inserted,
                      simple(expression, reads: &readNames, checkingBodyBinderOrdinals: checkingBodyBinderOrdinals)
                else { return nil }
                pendingSource.append(child)
            case .and(let left, let right), .or(let left, let right):
                pendingSource.append(right)
                pendingSource.append(left)
            case .guard_(let predicate):
                guard simple(predicate, reads: &readNames, checkingBodyBinderOrdinals: checkingBodyBinderOrdinals)
                else { return nil }
            case .assign(.named, let expression), .assign(.programCounter, let expression):
                guard simple(expression, reads: &readNames, checkingBodyBinderOrdinals: checkingBodyBinderOrdinals)
                else { return nil }
            case .unchanged(.named):
                break
            case .ifElse(let predicate, let yes, let no):
                guard simple(predicate, reads: &readNames, checkingBodyBinderOrdinals: checkingBodyBinderOrdinals)
                else { return nil }
                pendingSource.append(no)
                pendingSource.append(yes)
            default:
                return nil
            }
        }
        guard parameterNames.count == action.bindings.count,
              parameterNames.isDisjoint(with: Set(stateIDs.keys)),
              parameterNames.isDisjoint(with: definedNames),
              readNames.isSubset(of: Set(stateIDs.keys).union(definedNames).union(parameterNames))
        else { return nil }

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
                case .lessThan(let left, let right) where checkingBodyBinderOrdinals:
                    guard compiled.operation == .lessThan, compiled.children.count == 2 else { return false }
                    pending.append((right, compiled.children[1]))
                    pending.append((left, compiled.children[0]))
                case .divide(let left, let right), .modulo(let left, let right):
                    let operation: CompiledOperation = switch source {
                    case .divide: .divide
                    default: .modulo
                    }
                    guard compiled.operation == operation, compiled.children.count == 2 else { return false }
                    pending.append((right, compiled.children[1]))
                    pending.append((left, compiled.children[0]))
                case .equal(let left, let right), .and(let left, let right), .or(let left, let right),
                     .tupleAppend(let left, let right), .tupleConcatenate(let left, let right),
                     .in(let left, let right), .integerRange(let left, let right):
                    let operation: CompiledOperation = switch source {
                    case .and: .and
                    case .or: .or
                    case .tupleAppend: .tupleAppend
                    case .tupleConcatenate: .tupleConcatenate
                    case .in: .in
                    case .integerRange: .integerRange
                    default: .equal
                    }
                    guard compiled.operation == operation, compiled.children.count == 2 else { return false }
                    pending.append((right, compiled.children[1]))
                    pending.append((left, compiled.children[0]))
                case .not(let child):
                    guard compiled.operation == .not, compiled.children.count == 1 else { return false }
                    pending.append((child, compiled.children[0]))
                case .domain(let child):
                    guard compiled.operation == .domain, compiled.children.count == 1 else { return false }
                    pending.append((child, compiled.children[0]))
                case .ifThenElse(let condition, let yes, let no):
                    guard compiled.operation == .ifThenElse, compiled.children.count == 3 else { return false }
                    pending.append((no, compiled.children[2]))
                    pending.append((yes, compiled.children[1]))
                    pending.append((condition, compiled.children[0]))
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
                case .parameter(let reference):
                    let parameters = layout.parameters.filter { $0.reference == reference }
                    guard parameters.count == 1, compiled.children.isEmpty,
                          compiled.operation == .boundValue(parameters[0].binder) else { return false }
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
        var usedBinders = Set(layout.parameters.map(\.binder))
        guard usedBinders.count == layout.parameters.count else { throw mismatch() }
        for binding in compiledBindings {
            guard usedBinders.insert(binding.binder).inserted else { throw mismatch() }
        }
        var bindings = Dictionary(uniqueKeysWithValues: zip(action.bindings, compiledBindings)
            .map { ($0.name, $1.binder) })
        var expectedBodyBinders = bodyBinderOrdinals?.makeIterator()
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
                    if checkingBodyBinderOrdinals, expectedBodyBinders?.next() != binder.ordinal { throw mismatch() }
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
        guard expectedBodyBinders?.next() == nil else { throw mismatch() }
        return bodyBinderOrdinals
    }

    private static func simple(_ expression: StateExpr, reads: inout Set<String>, checkingBodyBinderOrdinals: Bool) -> Bool {
        var pending = [expression]
        while let node = pending.popLast() {
            switch node {
            case .variable(let name): reads.insert(name)
            case .value, .parameter: break
            case .add(let left, let right), .divide(let left, let right),
                 .modulo(let left, let right):
                pending.append(right)
                pending.append(left)
            case .lessThan(let left, let right) where checkingBodyBinderOrdinals:
                pending.append(right)
                pending.append(left)
            case .equal(let left, let right), .and(let left, let right), .or(let left, let right),
                 .tupleAppend(let left, let right), .tupleConcatenate(let left, let right),
                 .in(let left, let right), .integerRange(let left, let right):
                pending.append(right)
                pending.append(left)
            case .not(let child), .domain(let child):
                pending.append(child)
            case .ifThenElse(let condition, let yes, let no):
                pending.append(no)
                pending.append(yes)
                pending.append(condition)
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
            case .add, .divide, .modulo: return expression.children.count == 2 ? .int : nil
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
                if node.operation == .add || node.operation == .divide || node.operation == .modulo {
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
