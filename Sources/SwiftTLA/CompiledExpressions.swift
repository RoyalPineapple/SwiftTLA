struct CompiledRecordExpression: Sendable {
    struct Field: Sendable {
        let id: FieldID
        let key: CompiledValue
        let value: CompiledStateExpr
    }

    let fields: [Field]

    init(_ fields: [Field]) {
        self.fields = fields
    }
}

struct CompiledCaseBranch: Sendable {
    let condition: CompiledStateExpr
    let value: CompiledStateExpr
}

indirect enum CompiledStateExpr: Sendable {
    case value(TLAValue)
    case stateVariable(VariableID)
    case boundValue(BinderID)
    case controlLocation(ControlLocationID)
    case operatorReference(OperatorID)

    case add(CompiledStateExpr, CompiledStateExpr)
    case subtract(CompiledStateExpr, CompiledStateExpr)
    case multiply(CompiledStateExpr, CompiledStateExpr)
    case divide(CompiledStateExpr, CompiledStateExpr)
    case modulo(CompiledStateExpr, CompiledStateExpr)
    case negate(CompiledStateExpr)
    case integerDivide(CompiledStateExpr, CompiledStateExpr)
    case equal(CompiledStateExpr, CompiledStateExpr)
    case notEqual(CompiledStateExpr, CompiledStateExpr)
    case lessThan(CompiledStateExpr, CompiledStateExpr)
    case lessOrEqual(CompiledStateExpr, CompiledStateExpr)
    case greaterThan(CompiledStateExpr, CompiledStateExpr)
    case greaterOrEqual(CompiledStateExpr, CompiledStateExpr)
    case and(CompiledStateExpr, CompiledStateExpr)
    case or(CompiledStateExpr, CompiledStateExpr)
    case not(CompiledStateExpr)
    case ifThenElse(CompiledStateExpr, CompiledStateExpr, CompiledStateExpr)

    case setLiteral([CompiledStateExpr])
    case `in`(CompiledStateExpr, CompiledStateExpr)
    case subset(CompiledStateExpr, CompiledStateExpr)
    case union(CompiledStateExpr, CompiledStateExpr)
    case intersection(CompiledStateExpr, CompiledStateExpr)
    case setDifference(CompiledStateExpr, CompiledStateExpr)
    case cardinality(CompiledStateExpr)
    case setFilter(CompiledStateExpr, BinderID, CompiledStateExpr)
    case setMap(CompiledStateExpr, BinderID, CompiledStateExpr)
    case powerSet(CompiledStateExpr)
    case unionAll(CompiledStateExpr)
    case integerRange(CompiledStateExpr, CompiledStateExpr)

    case tupleLiteral([CompiledStateExpr])
    case tupleAccess(CompiledStateExpr, Int)
    case tupleDynamicAccess(CompiledStateExpr, CompiledStateExpr)
    case tupleLength(CompiledStateExpr)
    case tupleAppend(CompiledStateExpr, CompiledStateExpr)
    case tupleHead(CompiledStateExpr)
    case tupleTail(CompiledStateExpr)
    case tupleConcatenate(CompiledStateExpr, CompiledStateExpr)

    case recordLiteral(CompiledRecordExpression)
    case recordAccess(CompiledStateExpr, FieldID, CompiledValue)
    case domain(CompiledStateExpr)
    case functionLiteral(CompiledStateExpr, BinderID, CompiledStateExpr)
    case functionApply(CompiledStateExpr, CompiledStateExpr)
    case except(CompiledStateExpr, CompiledStateExpr, CompiledStateExpr)
    case caseExpr(CompiledCaseBranch, [CompiledCaseBranch], otherwise: CompiledStateExpr?)

    case forAll(CompiledStateExpr, BinderID, CompiledStateExpr)
    case exists(CompiledStateExpr, BinderID, CompiledStateExpr)
    case choose(CompiledStateExpr, BinderID, CompiledStateExpr)
    case enabledAction(ActionID)
    case sequenceFromSet(CompiledStateExpr)
    case setSum(CompiledStateExpr, CompiledStateExpr)
    case functionSet(CompiledStateExpr, CompiledStateExpr)
    case foldFunction(CompiledFormalLambda, initial: CompiledStateExpr, sequence: CompiledStateExpr)
    case lambdaApplication(CompiledFormalLambda, [CompiledStateExpr])
    case operatorApplication(OperatorID, [CompiledFormalCallArgument])
    case recursiveCall(OperatorID, [CompiledStateExpr])
    case letValue(BinderID, CompiledStateExpr, CompiledStateExpr)
    case letIn([CompiledLocalOperator], CompiledStateExpr)
}

private struct CompiledDependencyScope {
    var localOperators: [OperatorID: CompiledLocalOperator] = [:]
    var operatorBindings: [OperatorID: CompiledDependencyBinding<CompiledFormalOperator>] = [:]
    var valueBindings: [BinderID: CompiledDependencyBinding<CompiledStateExpr>] = [:]
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

extension CompiledStateExpr {
    func stateRequirements(
        formalOperators: [CompiledFormalOperatorDefinition],
        recursiveFunctions: [CompiledRecursiveFunction]
    ) -> (variables: Set<VariableID>, requiresCompleteState: Bool) {
        let formalOperators = Dictionary(uniqueKeysWithValues: formalOperators.map { ($0.id, $0) })
        let recursiveFunctions = Dictionary(uniqueKeysWithValues: recursiveFunctions.map { ($0.id, $0) })
        var variables: Set<VariableID> = []
        var requiresCompleteState = false
        var activeOperators: Set<OperatorID> = []
        var activeValues: Set<BinderID> = []
        var parametersByOperator: [OperatorID: [CompiledFormalParameter]] = [:]
        var valueParameterOwners: [BinderID: OperatorID] = [:]
        var operatorParameterOwners: [OperatorID: OperatorID] = [:]
        var demandedValues: [OperatorID: Set<BinderID>] = [:]
        var operatorDemands: [OperatorID: [CompiledOperatorParameterDemand]] = [:]
        var pendingCalls: [OperatorID: [CompiledPendingDependencyCall]] = [:]
        var operatorsApplyingDemands: Set<OperatorID> = []
        var operatorDemandKeys: Set<CompiledOperatorDemandKey> = []
        var nextOperatorDemandIdentity = 0

        func register(_ parameters: [CompiledFormalParameter], for operation: OperatorID) {
            parametersByOperator[operation] = parameters
            for parameter in parameters {
                switch parameter {
                case .value(let binder): valueParameterOwners[binder] = operation
                case .operator(let id, _): operatorParameterOwners[id] = operation
                }
            }
        }

        formalOperators.values.forEach { register($0.parameters, for: $0.id) }
        recursiveFunctions.values.forEach {
            register($0.parameters.map(CompiledFormalParameter.value), for: $0.id)
        }

        func bind(
            _ parameters: [BinderID],
            to arguments: [CompiledFormalCallArgument],
            in scope: CompiledDependencyScope,
            from argumentScope: CompiledDependencyScope
        ) -> CompiledDependencyScope {
            var nested = scope
            for (parameter, argument) in zip(parameters, arguments) {
                if case .value(let expression) = argument {
                    nested.valueBindings[parameter] = .init(expression, scope: argumentScope)
                }
            }
            return nested
        }

        func bind(
            _ parameters: [CompiledFormalParameter],
            to arguments: [CompiledFormalCallArgument],
            in scope: CompiledDependencyScope,
            from argumentScope: CompiledDependencyScope
        ) -> CompiledDependencyScope {
            var nested = scope
            for (parameter, argument) in zip(parameters, arguments) {
                switch (parameter, argument) {
                case (.value(let binder), .value(let expression)):
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
            switch operation.value {
            case .lambda(let lambda):
                visit(
                    lambda.body,
                    scope: bind(lambda.parameters, to: arguments, in: operation.scope, from: argumentScope)
                )
            case .reference(let id, _):
                if let supplied = operation.scope.operatorBindings[id] {
                    if let owner = operatorParameterOwners[id], operatorsApplyingDemands.contains(owner) == false {
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
                defer {
                    activeOperators.remove(id)
                    demandedValues.removeValue(forKey: id)
                    operatorDemands.removeValue(forKey: id)
                    pendingCalls.removeValue(forKey: id)
                }
                if let local = operation.scope.localOperators[id] {
                    let nested = bind(local.parameters, to: arguments, in: operation.scope, from: argumentScope)
                    if let domain = local.domain {
                        if let parameter = local.parameters.first {
                            demandedValues[id, default: []].insert(parameter)
                        }
                        if case .value(let argument) = arguments.first {
                            visit(argument, scope: argumentScope)
                        }
                        visit(domain, scope: nested)
                    }
                    visit(local.body, scope: nested)
                    visitPendingCalls(for: id)
                    return
                }
                if let function = recursiveFunctions[id] {
                    visit(
                        function.body,
                        scope: bind(function.parameters, to: arguments, in: operation.scope, from: argumentScope)
                    )
                    visitPendingCalls(for: id)
                    return
                }
                guard let definition = formalOperators[id] else { return }
                let nested = bind(definition.parameters, to: arguments, in: operation.scope, from: argumentScope)
                visit(definition.body, scope: nested)
                visitPendingCalls(for: id)
            }
        }

        func visitPendingCalls(for operation: OperatorID) {
            guard let parameters = parametersByOperator[operation] else { return }

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

            while true {
                var calls = pendingCalls[operation, default: []]
                var valueWork: [(CompiledStateExpr, CompiledDependencyScope)] = []
                var operatorWork: [(CompiledDependencyBinding<CompiledFormalOperator>, [CompiledFormalCallArgument], CompiledDependencyScope)] = []
                for index in calls.indices {
                    for (parameter, argument) in zip(parameters, calls[index].arguments) {
                        switch (parameter, argument) {
                        case (.value(let binder), .value(let expression))
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
                           operatorParameterOwners[parameter] == operation,
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
                valueWork.forEach { visit($0.0, scope: $0.1) }
                for work in operatorWork {
                    operatorsApplyingDemands.insert(operation)
                    visitCall(work.0, arguments: work.1, argumentScope: work.2)
                    operatorsApplyingDemands.remove(operation)
                }
            }
        }

        func visit(_ expression: CompiledStateExpr, scope: CompiledDependencyScope) {
            switch expression {
            case .value, .controlLocation:
                return
            case .boundValue(let binder):
                if let owner = valueParameterOwners[binder], operatorsApplyingDemands.contains(owner) == false {
                    demandedValues[owner, default: []].insert(binder)
                }
                guard let binding = scope.valueBindings[binder], activeValues.insert(binder).inserted
                else { return }
                defer { activeValues.remove(binder) }
                visit(binding.value, scope: binding.scope)
            case .enabledAction:
                requiresCompleteState = true
            case .stateVariable(let variable):
                variables.insert(variable)
            case .operatorReference(let id):
                visitCall(.reference(id, arity: 0), arguments: [], scope: scope)
            case .negate(let value), .not(let value), .cardinality(let value),
                 .powerSet(let value), .unionAll(let value), .tupleAccess(let value, _),
                 .tupleLength(let value), .tupleHead(let value), .tupleTail(let value),
                 .recordAccess(let value, _, _), .domain(let value), .sequenceFromSet(let value):
                visit(value, scope: scope)
            case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
                 .divide(let lhs, let rhs), .modulo(let lhs, let rhs), .integerDivide(let lhs, let rhs),
                 .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .lessThan(let lhs, let rhs),
                 .lessOrEqual(let lhs, let rhs), .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
                 .and(let lhs, let rhs), .or(let lhs, let rhs), .in(let lhs, let rhs), .subset(let lhs, let rhs),
                 .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs),
                 .integerRange(let lhs, let rhs), .tupleDynamicAccess(let lhs, let rhs),
                 .tupleAppend(let lhs, let rhs), .tupleConcatenate(let lhs, let rhs),
                 .setSum(let lhs, let rhs), .functionSet(let lhs, let rhs):
                visit(lhs, scope: scope)
                visit(rhs, scope: scope)
            case .functionApply(.operatorReference(let id), let argument):
                visitCall(.reference(id, arity: 1), arguments: [.value(argument)], scope: scope)
            case .functionApply(let function, let argument):
                visit(function, scope: scope)
                visit(argument, scope: scope)
            case .ifThenElse(let condition, let then, let otherwise):
                visit(condition, scope: scope)
                visit(then, scope: scope)
                visit(otherwise, scope: scope)
            case .setLiteral(let values), .tupleLiteral(let values):
                values.forEach { visit($0, scope: scope) }
            case .setFilter(let set, _, let predicate), .functionLiteral(let set, _, let predicate),
                 .forAll(let set, _, let predicate), .exists(let set, _, let predicate),
                 .choose(let set, _, let predicate):
                visit(set, scope: scope)
                visit(predicate, scope: scope)
            case .setMap(let value, _, let set):
                visit(value, scope: scope)
                visit(set, scope: scope)
            case .recordLiteral(let fields):
                fields.fields.forEach { visit($0.value, scope: scope) }
            case .except(let function, let key, let value):
                visit(function, scope: scope)
                visit(key, scope: scope)
                visit(value, scope: scope)
            case .caseExpr(let first, let remaining, let otherwise):
                visit(first.condition, scope: scope)
                visit(first.value, scope: scope)
                for branch in remaining {
                    visit(branch.condition, scope: scope)
                    visit(branch.value, scope: scope)
                }
                if let otherwise { visit(otherwise, scope: scope) }
            case .foldFunction(let operation, let initial, let sequence):
                visit(operation.body, scope: scope)
                visit(initial, scope: scope)
                visit(sequence, scope: scope)
            case .lambdaApplication(let operation, let arguments):
                visitCall(.lambda(operation), arguments: arguments.map(CompiledFormalCallArgument.value), scope: scope)
            case .operatorApplication(let operation, let arguments):
                visitCall(.reference(operation, arity: arguments.count), arguments: arguments, scope: scope)
            case .recursiveCall(let id, let arguments):
                visitCall(
                    .reference(id, arity: arguments.count),
                    arguments: arguments.map(CompiledFormalCallArgument.value),
                    scope: scope
                )
            case .letValue(let binder, let value, let body):
                var nested = scope
                nested.valueBindings[binder] = .init(value, scope: scope)
                visit(body, scope: nested)
            case .letIn(let operations, let body):
                var nested = scope
                operations.forEach {
                    nested.localOperators[$0.id] = $0
                    register($0.parameters.map(CompiledFormalParameter.value), for: $0.id)
                }
                visit(body, scope: nested)
            }
        }

        visit(self, scope: .init())
        return (variables, requiresCompleteState)
    }
}

struct CompiledFormalLambda: Sendable {
    let parameters: [BinderID]
    let body: CompiledStateExpr
}

enum CompiledFormalOperator: Sendable {
    case lambda(CompiledFormalLambda)
    case reference(OperatorID, arity: Int)

    var arity: Int {
        switch self {
        case .lambda(let lambda): return lambda.parameters.count
        case .reference(_, let arity): return arity
        }
    }
}

indirect enum CompiledFormalCallArgument: Sendable {
    case value(CompiledStateExpr)
    case `operator`(CompiledFormalOperator)
}

struct CompiledLocalOperator: Sendable {
    let id: OperatorID
    let parameters: [BinderID]
    let domain: CompiledStateExpr?
    let body: CompiledStateExpr
    let isRecursive: Bool
}

indirect enum CompiledActionExpr: Sendable {
    case assign(VariableID, CompiledStateExpr)
    case unchanged(VariableID)
    case guard_(CompiledStateExpr)
    case chooseAction(VariableID, CompiledStateExpr)
    case existsAction(BinderID, CompiledStateExpr, CompiledActionExpr)
    case ifElse(CompiledStateExpr, CompiledActionExpr, CompiledActionExpr)
    case define(BinderID, CompiledStateExpr, CompiledActionExpr)
    case and(CompiledActionExpr, CompiledActionExpr)
    case or(CompiledActionExpr, CompiledActionExpr)
}

struct CompiledAction: Sendable {
    let id: ActionID
    let bindings: [CompiledActionBinding]
    let body: CompiledActionExpr
    let symmetricCollection: VariableID?
}

struct CompiledActionBinding: Sendable {
    let binder: BinderID
    let sourceName: String
    let values: [TLAValue]
    let generatedSwiftType: String?
}

struct CompiledInvariant: Sendable {
    let id: PropertyID
    let name: String
    let body: CompiledStateExpr
}

indirect enum CompiledTemporalExpr: Sendable {
    case always(CompiledStateExpr)
    case eventually(CompiledStateExpr)
    case alwaysEventually(CompiledStateExpr)
    case eventuallyAlways(CompiledStateExpr)
    case leadsTo(CompiledStateExpr, CompiledStateExpr)
}

struct CompiledTemporal: Sendable {
    let id: PropertyID
    let name: String
    let expression: CompiledTemporalExpr
}

struct CompiledActionCall: Hashable, Sendable {
    let action: ActionID
    let arguments: [TLAValue]
}

struct CompiledFairnessCondition: Sendable {
    enum Scope: Hashable, Sendable {
        case next
        case action(ActionID)
        case actionCall(CompiledActionCall)
    }

    let scope: Scope
    let isStrong: Bool
}

struct CompiledFormalOperatorDefinition: Sendable {
    let id: OperatorID
    let parameters: [CompiledFormalParameter]
    let body: CompiledStateExpr
}

enum CompiledFormalParameter: Sendable {
    case value(BinderID)
    case `operator`(OperatorID, arity: Int)
}

struct CompiledRecursiveFunction: Sendable {
    let id: OperatorID
    let parameters: [BinderID]
    let body: CompiledStateExpr
}

enum CompiledVariableInitialization: Sendable {
    case value(CompiledValue)
    case expression(CompiledStateExpr)
    case memberOf(CompiledStateExpr)
}

struct CompiledFormalModuleReplacement: Sendable {
    let moduleName: String
    let operatorName: String
    let definitionName: String
    let expression: CompiledStateExpr
}

struct CompiledSymmetrySet: Sendable {
    let values: Set<TLAValue>
}

struct CompiledSymmetricCollection: Sendable {
    let variable: VariableID
    let members: [TLAValue]
    let domainSymbol: String
    let initial: CompiledValue
}

struct CompiledSemantics: Sendable {
    let checkDeadlock: Bool
    let variableInitializations: [(variable: VariableID, initialization: CompiledVariableInitialization)]
    let actions: [CompiledAction]
    let invariants: [CompiledInvariant]
    let temporalProperties: [CompiledTemporal]
    let fairness: [CompiledFairnessCondition]
    let constraint: CompiledStateExpr?
    let assume: CompiledStateExpr?
    let formalOperatorDefinitions: [CompiledFormalOperatorDefinition]
    let recursiveFunctions: [CompiledRecursiveFunction]
    let formalModuleReplacements: [CompiledFormalModuleReplacement]
    let symmetrySets: [CompiledSymmetrySet]
    let symmetricCollections: [CompiledSymmetricCollection]
}
