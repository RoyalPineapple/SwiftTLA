enum EvalError: Error, CustomStringConvertible {
    case typeMismatch(String)
    case divisionByZero
    case indexOutOfBounds(Int, Int)

    var description: String {
        switch self {
        case .typeMismatch(let message): return "Type mismatch: \(message)"
        case .divisionByZero: return "Division by zero"
        case .indexOutOfBounds(let index, let count): return "Index \(index) out of bounds (1..\(count))"
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

private indirect enum EvaluatorTask {
    case expression(CompiledStateExpr, EvaluatorScope)
    case finish(Int, ([CompiledValue]) throws -> CompiledValue)
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

        func schedule(
            _ expressions: [(CompiledStateExpr, EvaluatorScope)],
            build: @escaping ([CompiledValue]) throws -> CompiledValue
        ) {
            tasks.append(.finish(expressions.count, build))
            for (expression, scope) in expressions.reversed() {
                tasks.append(.expression(expression, scope))
            }
        }

        func schedule(
            _ expressions: [CompiledStateExpr],
            scope: EvaluatorScope,
            build: @escaping ([CompiledValue]) throws -> CompiledValue
        ) {
            schedule(expressions.map { ($0, scope) }, build: build)
        }

        func schedule(
            _ expression: CompiledStateExpr,
            scope: EvaluatorScope,
            build: @escaping (CompiledValue) throws -> CompiledValue
        ) {
            schedule([expression], scope: scope) { values in
                guard values.count == 1, let value = values.first else {
                    throw EvalError.typeMismatch("Invalid evaluator continuation")
                }
                return try build(value)
            }
        }

        func schedule(
            _ first: CompiledStateExpr,
            _ second: CompiledStateExpr,
            scope: EvaluatorScope,
            build: @escaping (CompiledValue, CompiledValue) throws -> CompiledValue
        ) {
            schedule([first, second], scope: scope) { values in
                guard values.count == 2 else {
                    throw EvalError.typeMismatch("Invalid evaluator continuation")
                }
                return try build(values[0], values[1])
            }
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
            case .finish(let count, let build):
                guard values.count >= count else {
                    throw EvalError.typeMismatch("Invalid evaluator continuation")
                }
                let start = values.count - count
                let arguments = Array(values[start...])
                values.removeSubrange(start...)
                values.append(try build(arguments))

            case .conditional(let then, let otherwise, let scope):
                let condition = try boolean(try popValue(from: &values))
                tasks.append(.expression(condition ? then : otherwise, scope))

            case .booleanRight(let expression, let scope, let shortCircuit):
                let lhs = try boolean(try popValue(from: &values))
                if lhs == shortCircuit {
                    values.append(.boolean(shortCircuit))
                } else {
                    tasks.append(.finish(1) { values in
                        guard values.count == 1, let value = values.first else {
                            throw EvalError.typeMismatch("Invalid evaluator continuation")
                        }
                        return .boolean(try boolean(value))
                    })
                    tasks.append(.expression(expression, scope))
                }

            case .collectionStart(let mode, let binder, let body, let scope):
                guard case .set(let set) = try popValue(from: &values) else {
                    throw EvalError.typeMismatch("Expected a set")
                }
                let members: [CompiledValue]
                switch mode {
                case .choose: members = CompiledValue.sorted(set)
                default: members = Array(set)
                }
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
                    schedule(lhs, rhs, scope: scope) {
                        .integer(try integer($0) + integer($1))
                    }
                case .subtract(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .integer(try integer($0) - integer($1))
                    }
                case .multiply(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .integer(try integer($0) * integer($1))
                    }
                case .divide(let lhs, let rhs), .integerDivide(let lhs, let rhs):
                    schedule(rhs, lhs, scope: scope) { divisorValue, dividendValue in
                        let divisor = try integer(divisorValue)
                        guard divisor != 0 else { throw EvalError.divisionByZero }
                        return .integer(try integer(dividendValue) / divisor)
                    }
                case .modulo(let lhs, let rhs):
                    schedule(rhs, lhs, scope: scope) { divisorValue, dividendValue in
                        let divisor = try integer(divisorValue)
                        guard divisor != 0 else { throw EvalError.divisionByZero }
                        return .integer(try integer(dividendValue) % divisor)
                    }
                case .negate(let expression):
                    schedule(expression, scope: scope) {
                        .integer(-(try integer($0)))
                    }
                case .equal(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .boolean($0 == $1)
                    }
                case .notEqual(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .boolean($0 != $1)
                    }
                case .lessThan(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .boolean(try integer($0) < integer($1))
                    }
                case .lessOrEqual(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .boolean(try integer($0) <= integer($1))
                    }
                case .greaterThan(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .boolean(try integer($0) > integer($1))
                    }
                case .greaterOrEqual(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .boolean(try integer($0) >= integer($1))
                    }
                case .and(let lhs, let rhs):
                    tasks.append(.booleanRight(rhs, scope: scope, shortCircuit: false))
                    tasks.append(.expression(lhs, scope))
                case .or(let lhs, let rhs):
                    tasks.append(.booleanRight(rhs, scope: scope, shortCircuit: true))
                    tasks.append(.expression(lhs, scope))
                case .not(let expression):
                    schedule(expression, scope: scope) {
                        .boolean(!(try boolean($0)))
                    }
                case .ifThenElse(let condition, let then, let otherwise):
                    tasks.append(.conditional(then: then, otherwise: otherwise, scope: scope))
                    tasks.append(.expression(condition, scope))
                case .setLiteral(let expressions):
                    schedule(expressions, scope: scope) { .set(Set($0)) }
                case .in(let member, let set):
                    schedule(set, member, scope: scope) { setValue, member in
                        guard case .set(let set) = setValue else {
                            throw EvalError.typeMismatch("Expected a set")
                        }
                        return .boolean(set.contains(member))
                    }
                case .subset(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        guard case .set(let lhs) = $0,
                              case .set(let rhs) = $1
                        else {
                            throw EvalError.typeMismatch("Expected sets")
                        }
                        return .boolean(lhs.isSubset(of: rhs))
                    }
                case .union(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        guard case .set(let lhs) = $0,
                              case .set(let rhs) = $1
                        else {
                            throw EvalError.typeMismatch("Expected sets")
                        }
                        return .set(lhs.union(rhs))
                    }
                case .intersection(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        guard case .set(let lhs) = $0,
                              case .set(let rhs) = $1
                        else {
                            throw EvalError.typeMismatch("Expected sets")
                        }
                        return .set(lhs.intersection(rhs))
                    }
                case .setDifference(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        guard case .set(let lhs) = $0,
                              case .set(let rhs) = $1
                        else {
                            throw EvalError.typeMismatch("Expected sets")
                        }
                        return .set(lhs.subtracting(rhs))
                    }
                case .cardinality(let set):
                    schedule(set, scope: scope) {
                        guard case .set(let set) = $0 else {
                            throw EvalError.typeMismatch("Expected a set")
                        }
                        return .integer(set.count)
                    }
                case .setFilter(let set, let binder, let predicate):
                    tasks.append(.collectionStart(.filter, binder: binder, body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .setMap(let body, let binder, let set):
                    tasks.append(.collectionStart(.map, binder: binder, body: body, scope: scope))
                    tasks.append(.expression(set, scope))
                case .powerSet(let set):
                    schedule(set, scope: scope) {
                        guard case .set(let set) = $0 else {
                            throw EvalError.typeMismatch("Expected a set")
                        }
                        return try powerSet(of: set)
                    }
                case .unionAll(let set):
                    schedule(set, scope: scope) {
                        guard case .set(let members) = $0 else {
                            throw EvalError.typeMismatch("Expected a set")
                        }
                        return .set(try members.reduce(into: Set<CompiledValue>()) { result, member in
                            guard case .set(let nested) = member else {
                                throw EvalError.typeMismatch("Expected a set of sets")
                            }
                            result.formUnion(nested)
                        })
                    }
                case .integerRange(let lower, let upper):
                    schedule(lower, upper, scope: scope) {
                        let lower = try integer($0)
                        let upper = try integer($1)
                        guard lower <= upper else { return .set([]) }
                        return .set(Set((lower...upper).map(CompiledValue.integer)))
                    }
                case .tupleLiteral(let expressions):
                    schedule(expressions, scope: scope) { .tuple($0) }
                case .tupleAccess(let tuple, let index):
                    schedule(tuple, scope: scope) {
                        let tuple = try sequenceElements(from: $0)
                        guard index >= 1, index <= tuple.count else {
                            throw EvalError.indexOutOfBounds(index, tuple.count)
                        }
                        return tuple[index - 1]
                    }
                case .tupleDynamicAccess(let tuple, let index):
                    schedule(tuple, index, scope: scope) {
                        let tuple = try sequenceElements(from: $0)
                        let index = try integer($1)
                        guard index >= 1, index <= tuple.count else {
                            throw EvalError.indexOutOfBounds(index, tuple.count)
                        }
                        return tuple[index - 1]
                    }
                case .tupleLength(let tuple):
                    schedule(tuple, scope: scope) {
                        .integer(try sequenceElements(from: $0).count)
                    }
                case .tupleAppend(let tuple, let element):
                    schedule(tuple, element, scope: scope) {
                        var tuple = try sequenceElements(from: $0)
                        tuple.append($1)
                        return .tuple(tuple)
                    }
                case .tupleHead(let tuple):
                    schedule(tuple, scope: scope) {
                        guard let first = try sequenceElements(from: $0).first else {
                            throw EvalError.typeMismatch("Expected a nonempty tuple")
                        }
                        return first
                    }
                case .tupleTail(let tuple):
                    schedule(tuple, scope: scope) {
                        let tuple = try sequenceElements(from: $0)
                        guard tuple.isEmpty == false else {
                            throw EvalError.typeMismatch("Expected a nonempty tuple")
                        }
                        return .tuple(Array(tuple.dropFirst()))
                    }
                case .tupleConcatenate(let lhs, let rhs):
                    schedule(lhs, rhs, scope: scope) {
                        .tuple(
                            try sequenceElements(from: $0)
                                + sequenceElements(from: $1)
                        )
                    }
                case .recordLiteral(let fields):
                    schedule(fields.fields.map { ($0.value, scope) }) { fieldValues in
                        .record(CompiledRecord(zip(fields.fields, fieldValues).map {
                            .init(key: $0.0.key, value: $0.1)
                        }))
                    }
                case .recordAccess(let record, _, let key):
                    schedule(record, scope: scope) {
                        guard case .record(let record) = $0,
                              let value = record.value(for: key)
                        else {
                            throw EvalError.typeMismatch("Expected record field")
                        }
                        return value
                    }
                case .domain(let expression):
                    schedule(expression, scope: scope) {
                        switch $0 {
                        case .function(let values): return .set(Set(values.keys))
                        case .record(let values): return .set(Set(values.fields.map(\.key)))
                        case .tuple(let values): return .set(Set(values.indices.map { .integer($0 + 1) }))
                        default: throw EvalError.typeMismatch("Expected a function")
                        }
                    }
                case .functionLiteral(let domain, let binder, let body):
                    tasks.append(.collectionStart(.function, binder: binder, body: body, scope: scope))
                    tasks.append(.expression(domain, scope))
                case .functionApply(let function, let argument):
                    if case .operatorReference(let id) = function {
                        tasks.append(.recursiveCall(id, arguments: [argument], scope: scope))
                    } else {
                        schedule(argument, function, scope: scope) { key, function in
                            switch function {
                            case .function(let values):
                                guard let value = values[key] else {
                                    throw EvalError.typeMismatch("Function argument is outside its domain")
                                }
                                return value
                            case .tuple(let values):
                                guard case .integer(let index) = key,
                                      index >= 1,
                                      index <= values.count
                                else {
                                    throw EvalError.typeMismatch("Tuple index is outside its domain")
                                }
                                return values[index - 1]
                            case .record(let values):
                                guard case .string = key,
                                      let value = values.value(for: key)
                                else {
                                    throw EvalError.typeMismatch("Record field is unavailable")
                                }
                                return value
                            default:
                                throw EvalError.typeMismatch("Expected a function")
                            }
                        }
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
                    schedule(set, scope: scope) {
                        guard case .set(let set) = $0 else {
                            throw EvalError.typeMismatch("Expected a set")
                        }
                        return .tuple(CompiledValue.sorted(set))
                    }
                case .setSum(let function, let set):
                    schedule(function, set, scope: scope) {
                        guard case .function(let function) = $0,
                              case .set(let members) = $1
                        else {
                            throw EvalError.typeMismatch("Expected a function and a set")
                        }
                        return .integer(try members.reduce(0) { total, member in
                            guard let result = function[member],
                                  case .integer(let value) = result
                            else {
                                throw EvalError.typeMismatch("Expected integer function values")
                            }
                            return total + value
                        })
                    }
                case .functionSet(let domain, let range):
                    schedule(domain, range, scope: scope) {
                        try functionSet(domain: $0, range: $1)
                    }
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
