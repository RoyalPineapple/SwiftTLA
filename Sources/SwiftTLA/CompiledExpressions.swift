package struct CompiledRecordEntry: Hashable, Sendable {
    package let name: String
    package let value: CompiledExpression
}

package struct CompiledCaseBranch: Hashable, Sendable {
    package let condition: CompiledExpression
    package let value: CompiledExpression
}


private struct CompiledDependencyScope {
    var operatorBindings: [OperatorID: CompiledDependencyBinding<CompiledFormalOperator>] = [:]
    var valueBindings: [BinderID: CompiledDependencyBinding<CompiledExpression>] = [:]
}

private final class CompiledDependencyBinding<Value> {
    let value: Value
    let scope: CompiledDependencyScope

    init(_ value: Value, scope: CompiledDependencyScope) {
        self.value = value
        self.scope = scope
    }
}

private struct CompiledPendingDependencyCall {
    let arguments: [CompiledFormalCallArgument]
    let scope: CompiledDependencyScope
    var processedValues: Set<BinderID> = []
    var processedOperatorDemands = 0
}

private struct CompiledOperatorParameterDemand {
    let identity: Int
    let parameter: OperatorID
    let arguments: [CompiledFormalCallArgument]
    let scope: CompiledDependencyScope
}

private struct CompiledOperatorDemandKey: Hashable {
    let identity: Int
    let parameter: OperatorID
}

struct CompiledStateRequirements: Sendable {
    var variables: Set<VariableID> = []
    var enabledActions: Set<ActionID> = []
    var requiresCompleteState: Bool { !enabledActions.isEmpty }
}

extension CompiledExpression {
    /// Diagnostic-only reflection of the outer case, without rendering its payload.
    package var diagnosticName: String {
        operation.diagnosticName
    }

    func stateRequirements(operators: CompiledOperators) -> CompiledStateRequirements {
        var variables: Set<VariableID> = []
        var enabledActions: Set<ActionID> = []
        var activeOperators: Set<OperatorID> = []
        var activeValues: Set<BinderID> = []
        var demandedValues: [OperatorID: Set<BinderID>] = [:]
        var operatorDemands: [OperatorID: [CompiledOperatorParameterDemand]] = [:]
        var pendingCalls: [OperatorID: [CompiledPendingDependencyCall]] = [:]
        var operatorsApplyingDemands: Set<OperatorID> = []
        var operatorDemandKeys: Set<CompiledOperatorDemandKey> = []
        var nextOperatorDemandIdentity = 0
        var work: [() -> Void] = []

        func bind(
            _ parameters: [CompiledFormalParameter],
            to arguments: [CompiledFormalCallArgument],
            in scope: CompiledDependencyScope,
            from argumentScope: CompiledDependencyScope
        ) -> CompiledDependencyScope {
            var nested = scope
            for (parameter, argument) in zip(parameters, arguments) {
                switch (parameter, argument) {
                case (.value(let binder, _), .value(let expression)):
                    nested.valueBindings[binder] = .init(expression, scope: argumentScope)
                case (.operator(let id, _), .operator(let supplied)):
                    nested.operatorBindings[id] = .init(supplied, scope: argumentScope)
                default:
                    break
                }
            }
            return nested
        }

        func visitCall(
            _ operation: CompiledFormalOperator,
            arguments: [CompiledFormalCallArgument],
            scope: CompiledDependencyScope
        ) {
            visitCall(.init(operation, scope: scope), arguments: arguments, argumentScope: scope)
        }

        func visitCall(
            _ operation: CompiledDependencyBinding<CompiledFormalOperator>,
            arguments: [CompiledFormalCallArgument],
            argumentScope: CompiledDependencyScope
        ) {
            work.append { processCall(operation, arguments: arguments, argumentScope: argumentScope) }
        }

        func processCall(
            _ operation: CompiledDependencyBinding<CompiledFormalOperator>,
            arguments: [CompiledFormalCallArgument],
            argumentScope: CompiledDependencyScope
        ) {
            switch operation.value {
            case .lambda(let id, _):
                guard let lambda = operators[id] else { return }
                visit(
                    lambda.body,
                    scope: bind(lambda.parameters, to: arguments, in: operation.scope, from: argumentScope)
                )
            case .reference(let id, _):
                if let supplied = operation.scope.operatorBindings[id] {
                    if let owner = operators.operatorParameterOwners[id], operatorsApplyingDemands.contains(owner) == false {
                        let identity = nextOperatorDemandIdentity
                        nextOperatorDemandIdentity += 1
                        operatorDemandKeys.insert(.init(identity: identity, parameter: id))
                        operatorDemands[owner, default: []].append(.init(
                            identity: identity,
                            parameter: id,
                            arguments: arguments,
                            scope: operation.scope
                        ))
                    }
                    visitCall(supplied, arguments: arguments, argumentScope: operation.scope)
                    return
                }
                guard activeOperators.insert(id).inserted else {
                    pendingCalls[id, default: []].append(.init(arguments: arguments, scope: operation.scope))
                    return
                }
                demandedValues[id] = []
                operatorDemands[id] = []
                pendingCalls[id] = []
                work.append {
                    activeOperators.remove(id)
                    demandedValues.removeValue(forKey: id)
                    operatorDemands.removeValue(forKey: id)
                    pendingCalls.removeValue(forKey: id)
                }
                work.append { visitPendingCalls(for: id) }
                if let declaration = operators[id] {
                    let nested = bind(declaration.parameters, to: arguments, in: operation.scope, from: argumentScope)
                    visit(declaration.body, scope: nested)
                    if let domain = declaration.domain {
                        visit(domain, scope: nested)
                        if case .value(let parameter, _) = declaration.parameters.first {
                            demandedValues[id, default: []].insert(parameter)
                        }
                        if case .value(let argument) = arguments.first {
                            visit(argument, scope: argumentScope)
                        }
                    }
                    return
                }
            }
        }

        func visitPendingCalls(for operation: OperatorID) {
            guard let parameters = operators[operation]?.parameters else { return }

            func resolve(
                _ operation: CompiledFormalOperator,
                in scope: CompiledDependencyScope
            ) -> CompiledDependencyBinding<CompiledFormalOperator>? {
                var resolved = CompiledDependencyBinding(operation, scope: scope)
                var visited: Set<OperatorID> = []
                while case .reference(let id, _) = resolved.value {
                    guard let supplied = resolved.scope.operatorBindings[id] else { break }
                    guard visited.insert(id).inserted else { return nil }
                    resolved = supplied
                }
                return resolved
            }

            var calls = pendingCalls[operation, default: []]
            var valueWork: [(CompiledExpression, CompiledDependencyScope)] = []
            var operatorWork: [(CompiledDependencyBinding<CompiledFormalOperator>, [CompiledFormalCallArgument], CompiledDependencyScope)] = []
            for index in calls.indices {
                for (parameter, argument) in zip(parameters, calls[index].arguments) {
                    switch (parameter, argument) {
                    case (.value(let binder, _), .value(let expression))
                        where demandedValues[operation, default: []].contains(binder)
                            && calls[index].processedValues.insert(binder).inserted:
                        valueWork.append((expression, calls[index].scope))
                    default:
                        break
                    }
                }
                let demands = operatorDemands[operation, default: []]
                while calls[index].processedOperatorDemands < demands.count {
                    let demand = demands[calls[index].processedOperatorDemands]
                    calls[index].processedOperatorDemands += 1
                    var supplied: CompiledFormalOperator?
                    for (parameter, argument) in zip(parameters, calls[index].arguments) {
                        guard case .operator(let id, _) = parameter,
                              id == demand.parameter,
                              case .operator(let argument) = argument
                        else { continue }
                        supplied = argument
                        break
                    }
                    guard let supplied else { continue }
                    if case .reference(let parameter, _) = supplied,
                       operators.operatorParameterOwners[parameter] == operation,
                       operatorDemandKeys.insert(.init(
                           identity: demand.identity,
                           parameter: parameter
                       )).inserted {
                        operatorDemands[operation, default: []].append(.init(
                            identity: demand.identity,
                            parameter: parameter,
                            arguments: demand.arguments,
                            scope: demand.scope
                        ))
                    }
                    guard let supplied = resolve(supplied, in: calls[index].scope)
                    else { continue }
                    let argumentScope = bind(
                        parameters,
                        to: calls[index].arguments,
                        in: demand.scope,
                        from: calls[index].scope
                    )
                    operatorWork.append((supplied, demand.arguments, argumentScope))
                }
            }
            pendingCalls[operation] = calls
            guard valueWork.isEmpty == false || operatorWork.isEmpty == false else {
                pendingCalls.removeValue(forKey: operation)
                return
            }
            work.append { visitPendingCalls(for: operation) }
            for call in operatorWork.reversed() {
                work.append { operatorsApplyingDemands.remove(operation) }
                visitCall(call.0, arguments: call.1, argumentScope: call.2)
                work.append { operatorsApplyingDemands.insert(operation) }
            }
            valueWork.reversed().forEach { visit($0.0, scope: $0.1) }
        }

        func visit(_ expression: CompiledExpression, scope: CompiledDependencyScope) {
            work.append { process(expression, scope: scope) }
        }

        func process(_ expression: CompiledExpression, scope: CompiledDependencyScope) {
            switch expression.operation {
            case .value, .controlLocation:
                return
            case .boundValue(let binder):
                if let owner = operators.valueParameterOwners[binder], operatorsApplyingDemands.contains(owner) == false {
                    demandedValues[owner, default: []].insert(binder)
                }
                guard let binding = scope.valueBindings[binder], activeValues.insert(binder).inserted
                else { return }
                work.append { activeValues.remove(binder) }
                visit(binding.value, scope: binding.scope)
            case .enabledAction(let action):
                enabledActions.insert(action)
            case .stateVariable(let variable):
                variables.insert(variable)
            case .operatorReference(let id):
                visitCall(.reference(id, arity: 0), arguments: [], scope: scope)
            case .functionApply where expression.children[0].referencedOperator != nil:
                let id = expression.children[0].referencedOperator!
                let argument = expression.children[1]
                visitCall(.reference(id, arity: 1), arguments: [.value(argument)], scope: scope)
            case .operatorApplication(let operation, let arguments):
                visitCall(operation, arguments: arguments, scope: scope)
            case .letValue(let binder):
                let value = expression.children[0]
                let body = expression.children[1]

                var nested = scope
                nested.valueBindings[binder] = .init(value, scope: scope)
                visit(body, scope: nested)

            default:
                expression.children.forEach { visit($0, scope: scope) }
            }
        }

        visit(self, scope: .init())
        while let next = work.popLast() { next() }
        return .init(variables: variables, enabledActions: enabledActions)
    }
}

/// An operator reference; bodies and captures belong to the declaration table.
package enum CompiledFormalOperator: Hashable, Sendable {
    case lambda(OperatorID, arity: Int)
    case reference(OperatorID, arity: Int)

    package var declarationID: OperatorID {
        switch self {
        case .lambda(let id, _), .reference(let id, _): id
        }
    }

    package var arity: Int {
        switch self {
        case .lambda(_, let arity), .reference(_, let arity): return arity
        }
    }
}

package enum CompiledFormalCallArgument: Hashable, Sendable {
    case value(CompiledExpression)
    case `operator`(CompiledFormalOperator)
}

/// A named or anonymous operator with one owned body and capture declaration.
package struct CompiledOperatorDefinition: Sendable {
    package let id: OperatorID
    package let parameters: [CompiledFormalParameter]
    package let domain: CompiledExpression?
    package let body: CompiledExpression
    package let isRecursive: Bool
    /// Lexically enclosing values read by this declaration, including nested bodies.
    package let capturedBindings: Set<BinderID>
    /// Calls can also depend on the captures of other local declarations.
    package let referencedOperators: Set<OperatorID>
}

/// The shared transition structure over compiled expressions.
package indirect enum CompiledActionExpr: Sendable {
    case assign(VariableID, CompiledExpression)
    case unchanged(VariableID)
    case guard_(CompiledExpression)
    case existsAction(BinderID, CompiledExpression, Self)
    case ifElse(CompiledExpression, Self, Self)
    case define(BinderID, CompiledExpression, Self)
    case and(Self, Self)
    case or(Self, Self)

    package func map(_ transform: (CompiledExpression) throws -> CompiledExpression) rethrows -> CompiledActionExpr {
        switch self {
        case .assign(let id, let value): return .assign(id, try transform(value))
        case .unchanged(let id): return .unchanged(id)
        case .guard_(let predicate): return .guard_(try transform(predicate))
        case .existsAction(let id, let domain, let body):
            return .existsAction(id, try transform(domain), try body.map(transform))
        case .define(let id, let value, let body):
            return .define(id, try transform(value), try body.map(transform))
        case .ifElse(let condition, let yes, let no):
            return .ifElse(try transform(condition), try yes.map(transform), try no.map(transform))
        case .and(let lhs, let rhs): return .and(try lhs.map(transform), try rhs.map(transform))
        case .or(let lhs, let rhs): return .or(try lhs.map(transform), try rhs.map(transform))
        }
    }
}

package struct CompiledAction: Sendable {
    package let id: ActionID
    package let bindings: [CompiledActionBinding]
    package let body: CompiledActionExpr
    package let collection: VariableID?

    package func map(
        _ transform: (CompiledExpression) throws -> CompiledExpression
    ) rethrows -> CompiledAction {
        .init(id: id, bindings: bindings, body: try body.map(transform), collection: collection)
    }
}

package struct CompiledActionBinding: Sendable {
    package let binder: BinderID
    package let sourceName: String
    package let values: [CompiledValue]
    package let generatedSwiftType: String?
}

/// A state expression and the action enabledness it requires, analyzed once.
package struct CompiledStateQuery: Sendable {
    package let expression: CompiledExpression
    package let enabledActions: Set<ActionID>

    package func map(
        _ transform: (CompiledExpression) throws -> CompiledExpression
    ) rethrows -> CompiledStateQuery {
        .init(expression: try transform(expression), enabledActions: enabledActions)
    }
}

package struct CompiledInvariant: Sendable {
    package let id: PropertyID
    package let name: String
    package let predicate: CompiledStateQuery

    package func map(
        _ transform: (CompiledExpression) throws -> CompiledExpression
    ) rethrows -> CompiledInvariant {
        .init(id: id, name: name, predicate: try predicate.map(transform))
    }
}

package enum CompiledTemporalExpr<Expression: Sendable>: Sendable {
    case always(Expression)
    case eventually(Expression)
    case alwaysEventually(Expression)
    case eventuallyAlways(Expression)
    case leadsTo(Expression, Expression)

    package func map<Result: Sendable>(
        _ transform: (Expression) throws -> Result
    ) rethrows -> CompiledTemporalExpr<Result> {
        switch self {
        case .always(let predicate): .always(try transform(predicate))
        case .eventually(let predicate): .eventually(try transform(predicate))
        case .alwaysEventually(let predicate): .alwaysEventually(try transform(predicate))
        case .eventuallyAlways(let predicate): .eventuallyAlways(try transform(predicate))
        case .leadsTo(let source, let target): .leadsTo(try transform(source), try transform(target))
        }
    }
}

package struct CompiledTemporal<Expression: Sendable>: Sendable {
    package let id: PropertyID
    package let name: String
    package let expression: CompiledTemporalExpr<Expression>

    package func map<Result: Sendable>(
        _ transform: (Expression) throws -> Result
    ) rethrows -> CompiledTemporal<Result> {
        .init(id: id, name: name, expression: try expression.map(transform))
    }
}

package struct CompiledActionCall: Hashable, Sendable {
    package let action: ActionID
    package let arguments: [CompiledValue]
}

package struct CompiledFairnessCondition: Sendable {
    package enum Scope: Hashable, Sendable {
        case next
        case action(ActionID)
        case actionCall(CompiledActionCall)
    }

    package let scope: Scope
    package let isStrong: Bool
}

package enum CompiledFormalParameter: Hashable, Sendable {
    case value(BinderID, typeName: String? = nil)
    case `operator`(OperatorID, arity: Int)

    var valueBinder: BinderID? {
        if case .value(let binder, _) = self { return binder }
        return nil
    }
}

package enum CompiledVariableInitialization: Sendable {
    case value(CompiledExpression)
    case memberOf(CompiledExpression)

    package func map(
        _ transform: (CompiledExpression) throws -> CompiledExpression
    ) rethrows -> CompiledVariableInitialization {
        switch self {
        case .value(let expression): .value(try transform(expression))
        case .memberOf(let expression): .memberOf(try transform(expression))
        }
    }
}

struct CompiledFormalModuleReplacement: Sendable {
    let moduleName: String
    let operatorName: String
    let definitionName: String
    let expression: CompiledExpression
}

struct CompiledModuleArgument: Sendable {
    let parameter: String
    let value: CompiledExpression
}

struct CompiledModuleInstance: Sendable {
    let id: ModuleInstanceID
    let arguments: [CompiledModuleArgument]
}

struct CompiledSymmetrySet: Sendable {
    let values: Set<CompiledValue>
}

/// Transitive lexical requirements, independent of a particular checking scope.
struct CompiledOperatorDependencies: Equatable, Sendable {
    let bindings: Set<BinderID>
    let operators: Set<OperatorID>
}

/// Declaration order and parameter ownership recorded during lowering.
package struct CompiledOperators: Sendable {
    private(set) var definitions: [OperatorID: CompiledOperatorDefinition] = [:]
    private(set) var dependencies: [OperatorID: CompiledOperatorDependencies] = [:]

    subscript(id: OperatorID) -> CompiledOperatorDefinition? { definitions[id] }

    package var formalDefinitionIDs: [OperatorID] = []
    package var recursiveFunctionIDs: [OperatorID] = []
    private(set) var valueParameterOwners: [BinderID: OperatorID] = [:]
    private(set) var operatorParameterOwners: [OperatorID: OperatorID] = [:]

    mutating func register(_ definition: CompiledOperatorDefinition) {
        definitions[definition.id] = definition
        for parameter in definition.parameters {
            switch parameter {
            case .value(let binder, _): valueParameterOwners[binder] = definition.id
            case .operator(let id, _): operatorParameterOwners[id] = definition.id
            }
        }
    }

    /// Run after all module, algorithm, and refinement declarations have been lowered.
    mutating func resolveDependencies() {
        var dependencies = definitions.mapValues {
            CompiledOperatorDependencies(bindings: $0.capturedBindings, operators: $0.referencedOperators)
        }
        var callers: [OperatorID: Set<OperatorID>] = [:]
        for declaration in definitions.values {
            for dependency in declaration.referencedOperators where definitions[dependency] != nil {
                callers[dependency, default: []].insert(declaration.id)
            }
        }
        var pending = Set(definitions.keys)
        while let dependency = pending.popFirst() {
            guard let required = dependencies[dependency] else { continue }
            for caller in callers[dependency, default: []] {
                guard let previous = dependencies[caller] else { continue }
                let combined = CompiledOperatorDependencies(
                    bindings: previous.bindings.union(required.bindings),
                    operators: previous.operators.union(required.operators))
                if combined != previous {
                    dependencies[caller] = combined
                    pending.insert(caller)
                }
            }
        }
        self.dependencies = dependencies
    }
}

package struct CompiledSemantics: Sendable {
    package let behavior: CompiledBehavior
    package var operators: CompiledOperators
    let formalModuleReplacements: [CompiledFormalModuleReplacement]
    let moduleInstances: [CompiledModuleInstance]
    let symmetrySets: [CompiledSymmetrySet]
}
