enum EvalError: Error, CustomStringConvertible, Equatable {
    case typeMismatch(String)
    case divisionByZero
    case indexOutOfBounds(Int, Int)
    case recursionDepthExceeded(Int)

    var description: String {
        switch self {
        case .typeMismatch(let message): return "Type mismatch: \(message)"
        case .divisionByZero: return "Division by zero"
        case .indexOutOfBounds(let index, let count): return "Index \(index) out of bounds (1..\(count))"
        case .recursionDepthExceeded(let limit): return "Evaluation exceeded recursive depth \(limit)"
        }
    }
}

private enum EvaluatorBinding {
    case value(CompiledValue)
    case expression(EvaluatorThunk)
}

private final class EvaluatorThunk {
    let expression: CompiledStateExpr
    let scope: EvaluatorScope
    var value: CompiledValue?

    init(expression: CompiledStateExpr, scope: EvaluatorScope) {
        self.expression = expression
        self.scope = scope
    }

}

private struct EvaluatorBindings {
    let inherited: CompiledBindings
    var values: [BinderID: EvaluatorBinding] = [:]

    func binding(_ value: CompiledValue, to binder: BinderID) -> EvaluatorBindings {
        var bindings = self
        bindings.values[binder] = .value(value)
        return bindings
    }

    func binding(
        _ expression: CompiledStateExpr,
        from scope: EvaluatorScope,
        to binder: BinderID
    ) -> EvaluatorBindings {
        var bindings = self
        if case .boundValue(let source) = expression,
           let binding = scope.bindings.values[source] {
            bindings.values[binder] = binding
            return bindings
        }
        bindings.values[binder] = .expression(.init(expression: expression, scope: scope))
        return bindings
    }
}

private struct EvaluatorScope {
    var bindings: EvaluatorBindings
    var localOperators: [OperatorID: CompiledLocalOperator]
    var operatorBindings: [OperatorID: CompiledFormalOperator]
}

private enum EvaluatorCollection {
    case filter
    case map
    case function
    case forall
    case exists
    case choose
}

private enum EvaluatorCollectionValues {
    case values([CompiledValue])
    case function([CompiledValue: CompiledValue])
}

private enum EvaluatorTask {
    case expression(CompiledStateExpr, EvaluatorScope)
    case finish(CompiledStateExpr)
    case booleanResult
    case conditional(then: CompiledStateExpr, otherwise: CompiledStateExpr, scope: EvaluatorScope)
    case booleanRight(CompiledStateExpr, scope: EvaluatorScope, shortCircuit: Bool)
    case collectionStart(EvaluatorCollection, binder: BinderID, body: CompiledStateExpr, scope: EvaluatorScope)
    case collectionStep(EvaluatorCollection, members: [CompiledValue], index: Int, binder: BinderID, body: CompiledStateExpr, scope: EvaluatorScope, accumulated: EvaluatorCollectionValues)
    case collectionResult(EvaluatorCollection, members: [CompiledValue], index: Int, binder: BinderID, body: CompiledStateExpr, scope: EvaluatorScope, accumulated: EvaluatorCollectionValues)
    case caseBranch([CompiledCaseBranch], index: Int, otherwise: CompiledStateExpr?, scope: EvaluatorScope)
    case caseCondition([CompiledCaseBranch], index: Int, otherwise: CompiledStateExpr?, scope: EvaluatorScope)
    case exceptFunction(key: CompiledStateExpr, scope: EvaluatorScope)
    case exceptKey(function: CompiledValue)
    case foldSequence(CompiledFormalLambda, initial: CompiledStateExpr, scope: EvaluatorScope)
    case foldInitial(CompiledFormalLambda, members: [CompiledValue], scope: EvaluatorScope)
    case foldStep(CompiledFormalLambda, members: [CompiledValue], index: Int, result: CompiledValue, scope: EvaluatorScope)
    case foldResult(CompiledFormalLambda, members: [CompiledValue], index: Int, scope: EvaluatorScope)
    case formalCall(CompiledFormalOperator, arguments: [CompiledFormalCallArgument], scope: EvaluatorScope)
    case recursiveCall(OperatorID, arguments: [CompiledStateExpr], scope: EvaluatorScope)
    case recursiveReturn
    case localDomain(CompiledStateExpr, scope: EvaluatorScope)
    case store(EvaluatorThunk)
}

struct CompiledEvaluator: Sendable {
    let variableValue: @Sendable (VariableID) throws -> CompiledValue
    let semantics: CompiledSemantics
    let layout: CompiledLayout
    let bindings: CompiledBindings
    let enabledActions: Set<ActionID>
    let localOperators: [OperatorID: CompiledLocalOperator]
    let operatorBindings: [OperatorID: CompiledFormalOperator]
    private static let maximumRecursiveDepth = 4_096

    init(
        state: CompiledState,
        semantics: CompiledSemantics,
        layout: CompiledLayout,
        bindings: CompiledBindings = .init(),
        enabledActions: Set<ActionID> = [],
        localOperators: [OperatorID: CompiledLocalOperator] = [:],
        operatorBindings: [OperatorID: CompiledFormalOperator] = [:]
    ) {
        self.variableValue = { try state.value(for: $0) }
        self.semantics = semantics
        self.layout = layout
        self.bindings = bindings
        self.enabledActions = enabledActions
        self.localOperators = localOperators
        self.operatorBindings = operatorBindings
    }

    init(
        variableValues: [VariableID: CompiledValue],
        semantics: CompiledSemantics,
        layout: CompiledLayout
    ) {
        self.variableValue = { variable in
            guard let value = variableValues[variable] else {
                throw CompiledEvaluationError.uninitializedVariable(variable)
            }
            return value
        }
        self.semantics = semantics
        self.layout = layout
        self.bindings = .init()
        self.enabledActions = []
        self.localOperators = [:]
        self.operatorBindings = [:]
    }

    func evaluate(_ expression: CompiledStateExpr) throws -> CompiledValue {
        let scope = EvaluatorScope(
            bindings: .init(inherited: bindings),
            localOperators: localOperators,
            operatorBindings: operatorBindings
        )
        var tasks = [EvaluatorTask.expression(expression, scope)]
        var values: [CompiledValue] = []
        let formalDefinitions = Dictionary(
            uniqueKeysWithValues: semantics.formalOperatorDefinitions.map { ($0.id, $0) }
        )
        let recursiveFunctions = Dictionary(
            uniqueKeysWithValues: semantics.recursiveFunctions.map { ($0.id, $0) }
        )
        var recursiveDepth = 0

        func integer(_ value: CompiledValue) throws -> Int {
            guard case .integer(let integer) = value else {
                throw EvalError.typeMismatch("Expected an integer")
            }
            return integer
        }

        func boolean(_ value: CompiledValue) throws -> Bool {
            guard case .boolean(let boolean) = value else {
                throw EvalError.typeMismatch("Expected a boolean")
            }
            return boolean
        }

        func collectionResult(
            _ mode: EvaluatorCollection,
            accumulated: EvaluatorCollectionValues
        ) throws -> CompiledValue {
            switch (mode, accumulated) {
            case (.filter, .values(let values)), (.map, .values(let values)):
                return .set(Set(values))
            case (.function, .function(let values)):
                return .function(values)
            case (.forall, _):
                return .boolean(true)
            case (.exists, _):
                return .boolean(false)
            case (.choose, _):
                throw EvalError.typeMismatch("No value satisfies CHOOSE")
            default:
                throw EvalError.typeMismatch("Invalid collection evaluation")
            }
        }

        while let task = tasks.popLast() {
            switch task {
            case .finish(let expression):
                switch expression {
                case .add:
                    let rhs = try integer(popValue(from: &values))
                    let lhs = try integer(popValue(from: &values))
                    values.append(.integer(lhs + rhs))
                case .subtract:
                    let rhs = try integer(popValue(from: &values))
                    let lhs = try integer(popValue(from: &values))
                    values.append(.integer(lhs - rhs))
                case .multiply:
                    let rhs = try integer(popValue(from: &values))
                    let lhs = try integer(popValue(from: &values))
                    values.append(.integer(lhs * rhs))
                case .divide, .integerDivide:
                    let dividend = try integer(popValue(from: &values))
                    let divisor = try integer(popValue(from: &values))
                    guard divisor != 0 else { throw EvalError.divisionByZero }
                    values.append(.integer(dividend / divisor))
                case .modulo:
                    let dividend = try integer(popValue(from: &values))
                    let divisor = try integer(popValue(from: &values))
                    guard divisor != 0 else { throw EvalError.divisionByZero }
                    values.append(.integer(dividend % divisor))
                case .negate:
                    values.append(.integer(-(try integer(popValue(from: &values)))))
                case .equal:
                    let rhs = try popValue(from: &values)
                    values.append(.boolean(try popValue(from: &values) == rhs))
                case .notEqual:
                    let rhs = try popValue(from: &values)
                    values.append(.boolean(try popValue(from: &values) != rhs))
                case .lessThan:
                    let rhs = try integer(popValue(from: &values))
                    values.append(.boolean(try integer(popValue(from: &values)) < rhs))
                case .lessOrEqual:
                    let rhs = try integer(popValue(from: &values))
                    values.append(.boolean(try integer(popValue(from: &values)) <= rhs))
                case .greaterThan:
                    let rhs = try integer(popValue(from: &values))
                    values.append(.boolean(try integer(popValue(from: &values)) > rhs))
                case .greaterOrEqual:
                    let rhs = try integer(popValue(from: &values))
                    values.append(.boolean(try integer(popValue(from: &values)) >= rhs))
                case .not:
                    values.append(.boolean(!(try boolean(popValue(from: &values)))))
                case .setLiteral(let expressions):
                    values.append(.set(Set(try popValues(expressions.count, from: &values))))
                case .in:
                    let member = try popValue(from: &values)
                    let setValue = try popValue(from: &values)
                    guard case .set(let set) = setValue else {
                        throw EvalError.typeMismatch("Expected a set")
                    }
                    values.append(.boolean(set.contains(member)))
                case .subset:
                    let rhs = try popValue(from: &values)
                    let lhs = try popValue(from: &values)
                    guard case .set(let lhs) = lhs, case .set(let rhs) = rhs else {
                        throw EvalError.typeMismatch("Expected sets")
                    }
                    values.append(.boolean(lhs.isSubset(of: rhs)))
                case .union:
                    let rhs = try popValue(from: &values)
                    let lhs = try popValue(from: &values)
                    guard case .set(let lhs) = lhs, case .set(let rhs) = rhs else {
                        throw EvalError.typeMismatch("Expected sets")
                    }
                    values.append(.set(lhs.union(rhs)))
                case .intersection:
                    let rhs = try popValue(from: &values)
                    let lhs = try popValue(from: &values)
                    guard case .set(let lhs) = lhs, case .set(let rhs) = rhs else {
                        throw EvalError.typeMismatch("Expected sets")
                    }
                    values.append(.set(lhs.intersection(rhs)))
                case .setDifference:
                    let rhs = try popValue(from: &values)
                    let lhs = try popValue(from: &values)
                    guard case .set(let lhs) = lhs, case .set(let rhs) = rhs else {
                        throw EvalError.typeMismatch("Expected sets")
                    }
                    values.append(.set(lhs.subtracting(rhs)))
                case .cardinality:
                    guard case .set(let set) = try popValue(from: &values) else {
                        throw EvalError.typeMismatch("Expected a set")
                    }
                    values.append(.integer(set.count))
                case .powerSet:
                    guard case .set(let set) = try popValue(from: &values) else {
                        throw EvalError.typeMismatch("Expected a set")
                    }
                    values.append(try powerSet(of: set))
                case .unionAll:
                    guard case .set(let members) = try popValue(from: &values) else {
                        throw EvalError.typeMismatch("Expected a set")
                    }
                    values.append(.set(try members.reduce(into: Set<CompiledValue>()) { result, member in
                        guard case .set(let nested) = member else {
                            throw EvalError.typeMismatch("Expected a set of sets")
                        }
                        result.formUnion(nested)
                    }))
                case .integerRange:
                    let upper = try integer(popValue(from: &values))
                    let lower = try integer(popValue(from: &values))
                    values.append(lower <= upper ? .set(Set((lower...upper).map(CompiledValue.integer))) : .set([]))
                case .tupleLiteral(let expressions):
                    values.append(.tuple(try popValues(expressions.count, from: &values)))
                case .tupleAccess(_, let index):
                    let tuple = try sequenceElements(from: popValue(from: &values))
                    guard index >= 1, index <= tuple.count else {
                        throw EvalError.indexOutOfBounds(index, tuple.count)
                    }
                    values.append(tuple[index - 1])
                case .tupleDynamicAccess:
                    let index = try integer(popValue(from: &values))
                    let tuple = try sequenceElements(from: popValue(from: &values))
                    guard index >= 1, index <= tuple.count else {
                        throw EvalError.indexOutOfBounds(index, tuple.count)
                    }
                    values.append(tuple[index - 1])
                case .tupleLength:
                    values.append(.integer(try sequenceElements(from: popValue(from: &values)).count))
                case .tupleAppend:
                    let element = try popValue(from: &values)
                    var tuple = try sequenceElements(from: popValue(from: &values))
                    tuple.append(element)
                    values.append(.tuple(tuple))
                case .tupleHead:
                    guard let first = try sequenceElements(from: popValue(from: &values)).first else {
                        throw EvalError.typeMismatch("Expected a nonempty tuple")
                    }
                    values.append(first)
                case .tupleTail:
                    let tuple = try sequenceElements(from: popValue(from: &values))
                    guard tuple.isEmpty == false else {
                        throw EvalError.typeMismatch("Expected a nonempty tuple")
                    }
                    values.append(.tuple(Array(tuple.dropFirst())))
                case .tupleConcatenate:
                    let rhs = try sequenceElements(from: popValue(from: &values))
                    let lhs = try sequenceElements(from: popValue(from: &values))
                    values.append(.tuple(lhs + rhs))
                case .recordLiteral(let fields):
                    let fieldValues = try popValues(fields.fields.count, from: &values)
                    values.append(.record(CompiledRecord(zip(fields.fields, fieldValues).map {
                        .init(key: $0.0.key, value: $0.1)
                    })))
                case .recordAccess(_, _, let key):
                    guard case .record(let record) = try popValue(from: &values),
                          let value = record.value(for: key)
                    else {
                        throw EvalError.typeMismatch("Expected record field")
                    }
                    values.append(value)
                case .domain:
                    switch try popValue(from: &values) {
                    case .function(let function): values.append(.set(Set(function.keys)))
                    case .record(let record): values.append(.set(Set(record.fields.map(\.key))))
                    case .tuple(let tuple): values.append(.set(Set(tuple.indices.map { .integer($0 + 1) })))
                    default: throw EvalError.typeMismatch("Expected a function")
                    }
                case .functionApply:
                    let function = try popValue(from: &values)
                    let key = try popValue(from: &values)
                    switch function {
                    case .function(let function):
                        guard let value = function[key] else {
                            throw EvalError.typeMismatch("Function argument is outside its domain")
                        }
                        values.append(value)
                    case .tuple(let tuple):
                        guard case .integer(let index) = key, index >= 1, index <= tuple.count else {
                            throw EvalError.typeMismatch("Tuple index is outside its domain")
                        }
                        values.append(tuple[index - 1])
                    case .record(let record):
                        guard case .string = key, let value = record.value(for: key) else {
                            throw EvalError.typeMismatch("Record field is unavailable")
                        }
                        values.append(value)
                    default:
                        throw EvalError.typeMismatch("Expected a function")
                    }
                case .sequenceFromSet:
                    guard case .set(let set) = try popValue(from: &values) else {
                        throw EvalError.typeMismatch("Expected a set")
                    }
                    values.append(.tuple(CompiledValue.sorted(set)))
                case .setSum:
                    guard case .set(let members) = try popValue(from: &values),
                          case .function(let function) = try popValue(from: &values)
                    else {
                        throw EvalError.typeMismatch("Expected a function and a set")
                    }
                    values.append(.integer(try members.reduce(0) { total, member in
                        guard let result = function[member], case .integer(let value) = result else {
                            throw EvalError.typeMismatch("Expected integer function values")
                        }
                        return total + value
                    }))
                case .functionSet:
                    let range = try popValue(from: &values)
                    let domain = try popValue(from: &values)
                    values.append(try functionSet(domain: domain, range: range))
                default:
                    throw EvalError.typeMismatch("Invalid evaluator continuation")
                }

            case .booleanResult:
                values.append(.boolean(try boolean(popValue(from: &values))))

            case .conditional(let then, let otherwise, let scope):
                let condition = try boolean(try popValue(from: &values))
                tasks.append(.expression(condition ? then : otherwise, scope))

            case .booleanRight(let expression, let scope, let shortCircuit):
                let lhs = try boolean(try popValue(from: &values))
                if lhs == shortCircuit {
                    values.append(.boolean(shortCircuit))
                } else {
                    tasks.append(.booleanResult)
                    tasks.append(.expression(expression, scope))
                }

            case .collectionStart(let mode, let binder, let body, let scope):
                guard case .set(let set) = try popValue(from: &values) else {
                    throw EvalError.typeMismatch("Expected a set")
                }
                let members = CompiledValue.sorted(set)
                let accumulated: EvaluatorCollectionValues
                switch mode {
                case .function: accumulated = .function([:])
                default: accumulated = .values([])
                }
                tasks.append(.collectionStep(
                    mode,
                    members: members,
                    index: 0,
                    binder: binder,
                    body: body,
                    scope: scope,
                    accumulated: accumulated
                ))

            case .collectionStep(let mode, let members, let index, let binder, let body, let scope, let accumulated):
                guard index < members.count else {
                    values.append(try collectionResult(mode, accumulated: accumulated))
                    continue
                }
                let member = members[index]
                var bodyScope = scope
                bodyScope.bindings = bodyScope.bindings.binding(member, to: binder)
                tasks.append(.collectionResult(
                    mode,
                    members: members,
                    index: index,
                    binder: binder,
                    body: body,
                    scope: scope,
                    accumulated: accumulated
                ))
                tasks.append(.expression(body, bodyScope))

            case .collectionResult(let mode, let members, let index, let binder, let body, let scope, let accumulated):
                let bodyValue = try popValue(from: &values)
                var next = accumulated
                switch (mode, accumulated) {
                case (.filter, .values(var selected)):
                    if bodyValue == .boolean(true) {
                        selected.append(members[index])
                    }
                    next = .values(selected)
                case (.map, .values(var mapped)):
                    mapped.append(bodyValue)
                    next = .values(mapped)
                case (.function, .function(var function)):
                    function[members[index]] = bodyValue
                    next = .function(function)
                case (.forall, _):
                    if bodyValue != .boolean(true) {
                        values.append(.boolean(false))
                        continue
                    }
                case (.exists, _):
                    if bodyValue == .boolean(true) {
                        values.append(.boolean(true))
                        continue
                    }
                case (.choose, _):
                    if bodyValue == .boolean(true) {
                        values.append(members[index])
                        continue
                    }
                default:
                    throw EvalError.typeMismatch("Invalid collection evaluation")
                }
                tasks.append(.collectionStep(
                    mode,
                    members: members,
                    index: index + 1,
                    binder: binder,
                    body: body,
                    scope: scope,
                    accumulated: next
                ))

            case .caseBranch(let branches, let index, let otherwise, let scope):
                guard index < branches.count else {
                    guard let otherwise else {
                        throw EvalError.typeMismatch("No CASE branch matched")
                    }
                    tasks.append(.expression(otherwise, scope))
                    continue
                }
                tasks.append(.caseCondition(branches, index: index, otherwise: otherwise, scope: scope))
                tasks.append(.expression(branches[index].condition, scope))

            case .caseCondition(let branches, let index, let otherwise, let scope):
                if try boolean(try popValue(from: &values)) {
                    tasks.append(.expression(branches[index].value, scope))
                } else {
                    tasks.append(.caseBranch(branches, index: index + 1, otherwise: otherwise, scope: scope))
                }

            case .exceptFunction(let key, let scope):
                let function = try popValue(from: &values)
                switch function {
                case .function, .record:
                    tasks.append(.exceptKey(function: function))
                    tasks.append(.expression(key, scope))
                default:
                    throw EvalError.typeMismatch("Expected a function")
                }

            case .exceptKey(let function):
                let key = try popValue(from: &values)
                let replacement = try popValue(from: &values)
                switch function {
                case .function(var function):
                    function[key] = replacement
                    values.append(.function(function))
                case .record(let record):
                    guard case .string = key else {
                        throw EvalError.typeMismatch("Expected a record field")
                    }
                    values.append(.record(record.replacing(replacement, for: key)))
                default:
                    throw EvalError.typeMismatch("Expected a function")
                }

            case .foldSequence(let operation, let initial, let scope):
                let members = try sequenceElements(from: popValue(from: &values))
                tasks.append(.foldInitial(operation, members: Array(members.reversed()), scope: scope))
                tasks.append(.expression(initial, scope))

            case .foldInitial(let operation, let members, let scope):
                let initial = try popValue(from: &values)
                tasks.append(.foldStep(operation, members: members, index: 0, result: initial, scope: scope))

            case .foldStep(let operation, let members, let index, let result, let scope):
                guard operation.parameters.count == 2 else {
                    throw EvalError.typeMismatch("FoldFunction requires two parameters")
                }
                guard index < members.count else {
                    values.append(result)
                    continue
                }
                var bodyScope = scope
                bodyScope.bindings = bodyScope.bindings
                    .binding(members[index], to: operation.parameters[0])
                    .binding(result, to: operation.parameters[1])
                tasks.append(.foldResult(operation, members: members, index: index, scope: scope))
                tasks.append(.expression(operation.body, bodyScope))

            case .foldResult(let operation, let members, let index, let scope):
                let result = try popValue(from: &values)
                tasks.append(.foldStep(operation, members: members, index: index + 1, result: result, scope: scope))

            case .formalCall(let operation, let arguments, let scope):
                switch operation {
                case .lambda(let lambda):
                    guard lambda.parameters.count == arguments.count else {
                        throw EvalError.typeMismatch("Formal operator argument count differs")
                    }
                    var callScope = scope
                    for (parameter, argument) in zip(lambda.parameters, arguments) {
                        guard case .value(let expression) = argument else {
                            throw EvalError.typeMismatch("Expected a formal value argument")
                        }
                        callScope.bindings = callScope.bindings.binding(expression, from: scope, to: parameter)
                    }
                    tasks.append(.expression(lambda.body, callScope))

                case .reference(let id, let arity):
                    if let supplied = scope.operatorBindings[id] {
                        guard supplied.arity == arity else {
                            throw EvalError.typeMismatch("Formal operator argument count differs")
                        }
                        tasks.append(.formalCall(supplied, arguments: arguments, scope: scope))
                        continue
                    }
                    guard let definition = formalDefinitions[id] else {
                        throw CompiledEvaluationError.unresolvedOperator
                    }
                    guard definition.parameters.count == arity,
                          definition.parameters.count == arguments.count
                    else {
                        throw EvalError.typeMismatch("Formal operator argument count differs")
                    }
                    var callScope = scope
                    for (parameter, argument) in zip(definition.parameters, arguments) {
                        switch (parameter, argument) {
                        case (.value(let binder), .value(let expression)):
                            callScope.bindings = callScope.bindings.binding(expression, from: scope, to: binder)
                        case (.operator(let operatorID, let expectedArity), .operator(let supplied)):
                            guard supplied.arity == expectedArity else {
                                throw EvalError.typeMismatch("Formal operator argument count differs")
                            }
                            callScope.operatorBindings[operatorID] = supplied
                        default:
                            throw EvalError.typeMismatch("Expected a formal value argument")
                        }
                    }
                    tasks.append(.expression(definition.body, callScope))
                }

            case .recursiveCall(let id, let arguments, let scope):
                guard recursiveDepth < Self.maximumRecursiveDepth else {
                    throw EvalError.recursionDepthExceeded(Self.maximumRecursiveDepth)
                }
                recursiveDepth += 1
                tasks.append(.recursiveReturn)
                if let operation = scope.localOperators[id] {
                    guard operation.parameters.count == arguments.count else {
                        throw EvalError.typeMismatch("Recursive operator argument count differs")
                    }
                    var callScope = scope
                    for (parameter, argument) in zip(operation.parameters, arguments) {
                        callScope.bindings = callScope.bindings.binding(argument, from: scope, to: parameter)
                    }
                    if let domain = operation.domain {
                        guard let parameter = operation.parameters.first else {
                            throw EvalError.typeMismatch("Recursive operator domain requires one parameter")
                        }
                        tasks.append(.localDomain(operation.body, scope: callScope))
                        tasks.append(.expression(.in(.boundValue(parameter), domain), callScope))
                    } else {
                        tasks.append(.expression(operation.body, callScope))
                    }
                    continue
                }
                guard let function = recursiveFunctions[id] else {
                    throw CompiledEvaluationError.unresolvedOperator
                }
                guard function.parameters.count == arguments.count else {
                    throw EvalError.typeMismatch("Recursive operator argument count differs")
                }
                var callScope = scope
                for (parameter, argument) in zip(function.parameters, arguments) {
                    callScope.bindings = callScope.bindings.binding(argument, from: scope, to: parameter)
                }
                tasks.append(.expression(function.body, callScope))

            case .recursiveReturn:
                recursiveDepth -= 1

            case .localDomain(let body, let scope):
                if try popValue(from: &values) == .boolean(false) {
                    throw EvalError.typeMismatch("Recursive operator argument is outside its domain")
                }
                tasks.append(.expression(body, scope))

            case .store(let thunk):
                let value = try popValue(from: &values)
                thunk.value = value
                values.append(value)

            case .expression(let expression, let scope):
                switch expression {
                case .value(let value):
                    values.append(.init(formal: value))
                case .stateVariable(let variable):
                    values.append(try variableValue(variable))
                case .boundValue(let binder):
                    if let binding = scope.bindings.values[binder] {
                        switch binding {
                        case .value(let value):
                            values.append(value)
                        case .expression(let thunk):
                            if let value = thunk.value {
                                values.append(value)
                            } else {
                                tasks.append(.store(thunk))
                                tasks.append(.expression(thunk.expression, thunk.scope))
                            }
                        }
                    } else {
                        values.append(try scope.bindings.inherited.value(for: binder))
                    }
                case .controlLocation(let label):
                    values.append(.controlLocation(label))
                case .operatorReference(let id):
                    if scope.localOperators[id] != nil
                        || recursiveFunctions[id] != nil
                    {
                        tasks.append(.recursiveCall(id, arguments: [], scope: scope))
                    } else {
                        tasks.append(.formalCall(.reference(id, arity: 0), arguments: [], scope: scope))
                    }
                case .add(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .subtract(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .multiply(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .divide(let lhs, let rhs), .integerDivide(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(lhs, scope))
                    tasks.append(.expression(rhs, scope))
                case .modulo(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(lhs, scope))
                    tasks.append(.expression(rhs, scope))
                case .negate(let operand):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(operand, scope))
                case .equal(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .notEqual(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .lessThan(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .lessOrEqual(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .greaterThan(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .greaterOrEqual(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .and(let lhs, let rhs):
                    tasks.append(.booleanRight(rhs, scope: scope, shortCircuit: false))
                    tasks.append(.expression(lhs, scope))
                case .or(let lhs, let rhs):
                    tasks.append(.booleanRight(rhs, scope: scope, shortCircuit: true))
                    tasks.append(.expression(lhs, scope))
                case .not(let operand):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(operand, scope))
                case .ifThenElse(let condition, let then, let otherwise):
                    tasks.append(.conditional(then: then, otherwise: otherwise, scope: scope))
                    tasks.append(.expression(condition, scope))
                case .setLiteral(let expressions):
                    tasks.append(.finish(expression))
                    for element in expressions.reversed() {
                        tasks.append(.expression(element, scope))
                    }
                case .in(let member, let set):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(member, scope))
                    tasks.append(.expression(set, scope))
                case .subset(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .union(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .intersection(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .setDifference(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .cardinality(let set):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(set, scope))
                case .setFilter(let set, let binder, let predicate):
                    tasks.append(.collectionStart(.filter, binder: binder, body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .setMap(let body, let binder, let set):
                    tasks.append(.collectionStart(.map, binder: binder, body: body, scope: scope))
                    tasks.append(.expression(set, scope))
                case .powerSet(let set):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(set, scope))
                case .unionAll(let set):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(set, scope))
                case .integerRange(let lower, let upper):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(upper, scope))
                    tasks.append(.expression(lower, scope))
                case .tupleLiteral(let expressions):
                    tasks.append(.finish(expression))
                    for element in expressions.reversed() {
                        tasks.append(.expression(element, scope))
                    }
                case .tupleAccess(let tuple, _):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(tuple, scope))
                case .tupleDynamicAccess(let tuple, let index):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(index, scope))
                    tasks.append(.expression(tuple, scope))
                case .tupleLength(let tuple):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(tuple, scope))
                case .tupleAppend(let tuple, let element):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(element, scope))
                    tasks.append(.expression(tuple, scope))
                case .tupleHead(let tuple):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(tuple, scope))
                case .tupleTail(let tuple):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(tuple, scope))
                case .tupleConcatenate(let lhs, let rhs):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(rhs, scope))
                    tasks.append(.expression(lhs, scope))
                case .recordLiteral(let fields):
                    tasks.append(.finish(expression))
                    for field in fields.fields.reversed() {
                        tasks.append(.expression(field.value, scope))
                    }
                case .recordAccess(let record, _, _):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(record, scope))
                case .domain(let operand):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(operand, scope))
                case .functionLiteral(let domain, let binder, let body):
                    tasks.append(.collectionStart(.function, binder: binder, body: body, scope: scope))
                    tasks.append(.expression(domain, scope))
                case .functionApply(let function, let argument):
                    if case .operatorReference(let id) = function {
                        tasks.append(.recursiveCall(id, arguments: [argument], scope: scope))
                    } else {
                        tasks.append(.finish(expression))
                        tasks.append(.expression(function, scope))
                        tasks.append(.expression(argument, scope))
                    }
                case .except(let function, let key, let replacement):
                    tasks.append(.exceptFunction(key: key, scope: scope))
                    tasks.append(.expression(function, scope))
                    tasks.append(.expression(replacement, scope))
                case .caseExpr(let first, let remaining, let otherwise):
                    tasks.append(.caseBranch([first] + remaining, index: 0, otherwise: otherwise, scope: scope))
                case .forAll(let set, let binder, let predicate):
                    tasks.append(.collectionStart(.forall, binder: binder, body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .exists(let set, let binder, let predicate):
                    tasks.append(.collectionStart(.exists, binder: binder, body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .choose(let set, let binder, let predicate):
                    tasks.append(.collectionStart(.choose, binder: binder, body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .enabledAction(let action):
                    values.append(.boolean(enabledActions.contains(action)))
                case .sequenceFromSet(let set):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(set, scope))
                case .setSum(let function, let set):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(set, scope))
                    tasks.append(.expression(function, scope))
                case .functionSet(let domain, let range):
                    tasks.append(.finish(expression))
                    tasks.append(.expression(range, scope))
                    tasks.append(.expression(domain, scope))
                case .foldFunction(let operation, let initial, let sequence):
                    tasks.append(.foldSequence(operation, initial: initial, scope: scope))
                    tasks.append(.expression(sequence, scope))
                case .lambdaApplication(let operation, let arguments):
                    tasks.append(.formalCall(
                        .lambda(operation),
                        arguments: arguments.map(CompiledFormalCallArgument.value),
                        scope: scope
                    ))
                case .operatorApplication(let operation, let arguments):
                    tasks.append(.formalCall(
                        .reference(operation, arity: arguments.count),
                        arguments: arguments,
                        scope: scope
                    ))
                case .letValue(let binder, let expression, let body):
                    var bodyScope = scope
                    bodyScope.bindings = bodyScope.bindings.binding(expression, from: scope, to: binder)
                    tasks.append(.expression(body, bodyScope))
                case .letIn(let operators, let body):
                    var bodyScope = scope
                    for operation in operators {
                        bodyScope.localOperators[operation.id] = operation
                    }
                    tasks.append(.expression(body, bodyScope))
                case .recursiveCall(let id, let arguments):
                    tasks.append(.recursiveCall(id, arguments: arguments, scope: scope))
                }
            }
        }

        guard values.count == 1, let value = values.first else {
            throw EvalError.typeMismatch("Invalid evaluator result")
        }
        return value
    }
}

private extension CompiledEvaluator {
    func popValue(from values: inout [CompiledValue]) throws -> CompiledValue {
        guard let value = values.popLast() else {
            throw EvalError.typeMismatch("Invalid evaluator continuation")
        }
        return value
    }

    func popValues(_ count: Int, from values: inout [CompiledValue]) throws -> [CompiledValue] {
        guard values.count >= count else {
            throw EvalError.typeMismatch("Invalid evaluator continuation")
        }
        let start = values.count - count
        let result = Array(values[start...])
        values.removeSubrange(start...)
        return result
    }

    func sequenceElements(from value: CompiledValue) throws -> [CompiledValue] {
        switch value {
        case .tuple(let values):
            return values
        case .function(let values):
            return try (0..<values.count).map { offset in
                guard let element = values[.integer(offset + 1)] else {
                    throw EvalError.typeMismatch("Expected a sequence function")
                }
                return element
            }
        default:
            throw EvalError.typeMismatch("Expected a sequence")
        }
    }

    func powerSet(of values: Set<CompiledValue>) throws -> CompiledValue {
        guard values.count < Int.bitWidth else {
            throw EvalError.typeMismatch("Set is too large to enumerate its power set")
        }
        let members = Array(values)
        return .set(Set((0..<(1 << members.count)).map { mask in
            .set(Set(members.enumerated().compactMap { index, member in
                mask & (1 << index) == 0 ? nil : member
            }))
        }))
    }

    func functionSet(domain: CompiledValue, range: CompiledValue) throws -> CompiledValue {
        guard case .set(let domainValues) = domain,
              case .set(let rangeValues) = range
        else {
            throw EvalError.typeMismatch("Expected function-set domains")
        }
        let orderedDomain = CompiledValue.sorted(domainValues)
        let orderedRange = CompiledValue.sorted(rangeValues)
        var functions: [[CompiledValue: CompiledValue]] = [[:]]
        for key in orderedDomain {
            functions = functions.flatMap { partial in
                orderedRange.map { value in
                    var next = partial
                    next[key] = value
                    return next
                }
            }
        }
        return .set(Set(functions.map(CompiledValue.function)))
    }
}

package func evaluateClosed(_ expression: StateExpr) throws -> TLAValue {
    let compilation = try TLASpec(
        name: "ClosedExpression",
        variables: [],
        actions: [],
        invariants: [.init(name: "value", body: expression)]
    ).compile()
    let state = try CompiledState(values: [CompiledValue](), compilation: compilation)
    guard let invariant = compilation.semantics.invariants.first else {
        throw CompiledEvaluationError.unresolvedOperator
    }
    return try CompiledEvaluator(state: state, semantics: compilation.semantics, layout: compilation.layout)
        .evaluate(invariant.body)
        .rendered(using: compilation.layout)
}
