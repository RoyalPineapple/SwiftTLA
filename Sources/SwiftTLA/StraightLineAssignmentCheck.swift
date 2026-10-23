enum StraightLineAssignmentCheck {
    private enum Term: Hashable {
        case prior(String)
        case parameter(String)
        case literal(TLAValue)
    }

    private struct Delta: Hashable {
        let writes: [String: Term]

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.writes == rhs.writes }

        func hash(into hasher: inout Hasher) {
            for name in writes.keys.sorted() {
                hasher.combine(name)
                hasher.combine(writes[name])
            }
        }

        func merging(_ other: Self) -> Self? {
            var combined = writes
            for (name, value) in other.writes {
                if let prior = combined[name], prior != value { return nil }
                combined[name] = value
            }
            return .init(writes: combined)
        }
    }

    private enum NormalizationVisit {
        case action(ActionExpr, [String: Term])
        case conjunction
        case alternative
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
                    case .guard_(.value(.bool(let enabled))):
                        results.append(enabled ? [.init(writes: [:])] : [])
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
                }
            }
            return results.count == 1 ? results[0] : nil
        }

        guard let sourceOutcomes = outcomes(source) else { return }
        let expected = Set(sourceOutcomes.map { delta in
            Delta(writes: stateRoots.reduce(into: delta.writes) { writes, name in
                if writes[name] == nil { writes[name] = .prior(name) }
            })
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

    static func verify(_ step: AtomicStep, lowered: ActionExpr, stateRoots: Set<String>) throws {
        let parameterNames = step.bindings.map(\.name)
        let parameters = Set(parameterNames)
        guard parameters.count == parameterNames.count,
              parameters.isDisjoint(with: stateRoots) else { return }

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
        var bindings = Dictionary(uniqueKeysWithValues: parameterNames.map { ($0, Term.parameter($0)) })
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
            case .assign(.named(let root), let expression):
                guard stateRoots.contains(root) else { throw mismatch() }
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

        guard stateRoots.allSatisfy({ (writes[$0] ?? .prior($0)) == (source[$0] ?? .prior($0)) }) else {
            throw mismatch()
        }
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
            case .guard_(.value(.bool(true))):
                break
            case .assign(.named, let expression):
                guard simple(expression, reads: &readNames) else { return }
            case .unchanged(.named):
                break
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
            guard compiled.children.isEmpty else { return false }
            switch source {
            case .variable(let name):
                if let binder = bindings[name] { return compiled.operation == .boundValue(binder) }
                guard let variable = stateIDs[name] else { return false }
                return compiled.operation == .stateVariable(variable)
            case .value(.int(let number)):
                return compiled.operation == .value(.integer(number))
            case .value(.bool(let value)):
                return compiled.operation == .value(.boolean(value))
            default:
                return false
            }
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
                case (.guard_(.value(.bool(true))), .guard_(let value)):
                    guard matching(.value(.bool(true)), value, bindings: bindings) else { throw mismatch() }
                case (.assign(.named(let name), let expression), .assign(let id, let value)):
                    guard stateIDs[name] == id, matching(expression, value, bindings: bindings) else {
                        throw mismatch()
                    }
                case (.unchanged(.named(let name)), .unchanged(let id)):
                    guard stateIDs[name] == id else { throw mismatch() }
                default:
                    throw mismatch()
                }
            }
        }
    }

    private static func simple(_ expression: StateExpr, reads: inout Set<String>) -> Bool {
        switch expression {
        case .variable(let name):
            reads.insert(name)
            return true
        case .value(.int), .value(.bool):
            return true
        default:
            return false
        }
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
        func leafType(_ expression: CompiledExpression,
                      bindings: [BinderID: CompiledValueType]) -> CompiledValueType? {
            guard expression.children.isEmpty else { return nil }
            switch expression.operation {
            case .stateVariable(let id): return variableTypes[id]
            case .boundValue(let id): return bindings[id]
            case .value(.integer): return .int
            case .value(.boolean): return .bool
            default: return nil
            }
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
                          let type = leafType(value, bindings: bindings), scalar(type) else { return }
                    if case .stateVariable(let read) = value.operation { usedVariables.insert(read) }
                    bindings[id] = type
                    inferredBindings[id] = type
                    pending.append(.unbind(id))
                    pending.append(.scan(body))
                case .and(let left, let right), .or(let left, let right):
                    pending.append(.scan(right))
                    pending.append(.scan(left))
                case .assign(let id, let value):
                    guard let type = leafType(value, bindings: bindings), scalar(type),
                          variableTypes[id] == type || (variableTypes[id] == .unknown
                              && resolvedVariableTypes[id] == type) else { return }
                    usedVariables.insert(id)
                    if case .stateVariable(let read) = value.operation { usedVariables.insert(read) }
                case .unchanged(let id):
                    guard scalar(variableTypes[id]) else { return }
                    usedVariables.insert(id)
                case .guard_(let value):
                    guard value.children.isEmpty,
                          value.operation == .value(.boolean(true)) else { return }
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
            guard let type = leafType(before, bindings: bindings) else { return false }
            return after.children.isEmpty && before.operation == after.operation && after.resultType == type
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
                          let type = leafType(firstValue, bindings: bindings),
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
                default: throw mismatch()
                }
            }
        }
    }
}
