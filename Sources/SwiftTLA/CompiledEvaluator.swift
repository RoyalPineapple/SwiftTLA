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

struct CompiledEvaluator: Sendable {
    private static let maximumOperatorCallDepth = 16

    let variableValue: @Sendable (VariableID) throws -> CompiledValue
    let semantics: CompiledSemantics
    let layout: CompiledLayout
    let bindings: CompiledBindings
    let enabledActions: Set<ActionID>
    let localOperators: [OperatorID: CompiledLocalOperator]
    let operatorBindings: [OperatorID: CompiledFormalOperator]
    let remainingOperatorCallDepth: Int

    init(
        state: CompiledState,
        semantics: CompiledSemantics,
        layout: CompiledLayout,
        bindings: CompiledBindings = .init(),
        enabledActions: Set<ActionID> = [],
        localOperators: [OperatorID: CompiledLocalOperator] = [:],
        operatorBindings: [OperatorID: CompiledFormalOperator] = [:],
        remainingOperatorCallDepth: Int = CompiledEvaluator.maximumOperatorCallDepth
    ) {
        self.variableValue = { try state.value(for: $0) }
        self.semantics = semantics
        self.layout = layout
        self.bindings = bindings
        self.enabledActions = enabledActions
        self.localOperators = localOperators
        self.operatorBindings = operatorBindings
        self.remainingOperatorCallDepth = remainingOperatorCallDepth
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
        self.remainingOperatorCallDepth = Self.maximumOperatorCallDepth
    }

    private init(
        variableValue: @escaping @Sendable (VariableID) throws -> CompiledValue,
        semantics: CompiledSemantics,
        layout: CompiledLayout,
        bindings: CompiledBindings,
        enabledActions: Set<ActionID>,
        localOperators: [OperatorID: CompiledLocalOperator],
        operatorBindings: [OperatorID: CompiledFormalOperator],
        remainingOperatorCallDepth: Int
    ) {
        self.variableValue = variableValue
        self.semantics = semantics
        self.layout = layout
        self.bindings = bindings
        self.enabledActions = enabledActions
        self.localOperators = localOperators
        self.operatorBindings = operatorBindings
        self.remainingOperatorCallDepth = remainingOperatorCallDepth
    }

    func evaluate(_ expression: CompiledStateExpr) throws -> CompiledValue {
        try evaluate(expression, bindings: bindings)
    }

    private func evaluate(
        _ expression: CompiledStateExpr,
        bindings: CompiledBindings
    ) throws -> CompiledValue {
        func value(_ expression: CompiledStateExpr) throws -> CompiledValue {
            try evaluate(expression, bindings: bindings)
        }
        func integer(_ expression: CompiledStateExpr) throws -> Int {
            guard case .integer(let value) = try value(expression) else {
                throw EvalError.typeMismatch("Expected an integer")
            }
            return value
        }
        func boolean(_ expression: CompiledStateExpr) throws -> Bool {
            guard case .boolean(let value) = try value(expression) else {
                throw EvalError.typeMismatch("Expected a boolean")
            }
            return value
        }

        switch expression {
        case .value(let value):
            return .init(formal: value)
        case .stateVariable(let variable):
            return try variableValue(variable)
        case .boundValue(let binder):
            return try bindings.value(for: binder)
        case .controlLocation(let label):
            return .controlLocation(label)
        case .operatorReference(let id):
            if localOperators[id] != nil || semantics.recursiveFunctions.contains(where: { $0.id == id }) {
                return try evaluateRecursiveCall(id, arguments: [], bindings: bindings)
            }
            return try evaluateOperatorApplication(
                .reference(id, arity: 0),
                arguments: [],
                bindings: bindings
            )
        case .add(let lhs, let rhs):
            return .integer(try integer(lhs) + integer(rhs))
        case .subtract(let lhs, let rhs):
            return .integer(try integer(lhs) - integer(rhs))
        case .multiply(let lhs, let rhs):
            return .integer(try integer(lhs) * integer(rhs))
        case .divide(let lhs, let rhs), .integerDivide(let lhs, let rhs):
            let divisor = try integer(rhs)
            guard divisor != 0 else { throw EvalError.divisionByZero }
            return .integer(try integer(lhs) / divisor)
        case .modulo(let lhs, let rhs):
            let divisor = try integer(rhs)
            guard divisor != 0 else { throw EvalError.divisionByZero }
            return .integer(try integer(lhs) % divisor)
        case .negate(let value):
            return .integer(-(try integer(value)))
        case .equal(let lhs, let rhs):
            return .boolean(try value(lhs) == value(rhs))
        case .notEqual(let lhs, let rhs):
            return .boolean(try value(lhs) != value(rhs))
        case .lessThan(let lhs, let rhs):
            return .boolean(try integer(lhs) < integer(rhs))
        case .lessOrEqual(let lhs, let rhs):
            return .boolean(try integer(lhs) <= integer(rhs))
        case .greaterThan(let lhs, let rhs):
            return .boolean(try integer(lhs) > integer(rhs))
        case .greaterOrEqual(let lhs, let rhs):
            return .boolean(try integer(lhs) >= integer(rhs))
        case .and(let lhs, let rhs):
            guard try boolean(lhs) else { return .boolean(false) }
            return .boolean(try boolean(rhs))
        case .or(let lhs, let rhs):
            guard !(try boolean(lhs)) else { return .boolean(true) }
            return .boolean(try boolean(rhs))
        case .not(let value):
            return .boolean(!(try boolean(value)))
        case .ifThenElse(let condition, let then, let otherwise):
            return try value(boolean(condition) ? then : otherwise)
        case .setLiteral(let expressions):
            return .set(try Set(expressions.map(value)))
        case .in(let member, let set):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            return .boolean(values.contains(try value(member)))
        case .subset(let lhs, let rhs):
            guard case .set(let left) = try value(lhs), case .set(let right) = try value(rhs) else {
                throw EvalError.typeMismatch("Expected sets")
            }
            return .boolean(left.isSubset(of: right))
        case .union(let lhs, let rhs):
            guard case .set(let left) = try value(lhs), case .set(let right) = try value(rhs) else {
                throw EvalError.typeMismatch("Expected sets")
            }
            return .set(left.union(right))
        case .intersection(let lhs, let rhs):
            guard case .set(let left) = try value(lhs), case .set(let right) = try value(rhs) else {
                throw EvalError.typeMismatch("Expected sets")
            }
            return .set(left.intersection(right))
        case .setDifference(let lhs, let rhs):
            guard case .set(let left) = try value(lhs), case .set(let right) = try value(rhs) else {
                throw EvalError.typeMismatch("Expected sets")
            }
            return .set(left.subtracting(right))
        case .cardinality(let set):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            return .integer(values.count)
        case .setFilter(let set, let binder, let predicate):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            return .set(try values.reduce(into: Set<CompiledValue>()) { result, element in
                if case .boolean(true) = try evaluate(predicate, bindings: bindings.binding(element, to: binder)) {
                    result.insert(element)
                }
            })
        case .setMap(let body, let binder, let set):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            return .set(try Set(values.map { element in
                try evaluate(body, bindings: bindings.binding(element, to: binder))
            }))
        case .powerSet(let set):
            return try evaluatePowerSet(set, bindings: bindings)
        case .unionAll(let set):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            return .set(try values.reduce(into: Set<CompiledValue>()) { result, member in
                guard case .set(let nested) = member else {
                    throw EvalError.typeMismatch("Expected a set of sets")
                }
                result.formUnion(nested)
            })
        case .integerRange(let lower, let upper):
            let lowerValue = try integer(lower)
            let upperValue = try integer(upper)
            guard lowerValue <= upperValue else { return .set([]) }
            return .set(Set((lowerValue...upperValue).map(CompiledValue.integer)))
        case .tupleLiteral(let expressions):
            return .tuple(try expressions.map(value))
        case .tupleAccess(let tuple, let index):
            let values = try sequenceElements(from: value(tuple))
            guard index >= 1, index <= values.count else {
                throw EvalError.indexOutOfBounds(index, values.count)
            }
            return values[index - 1]
        case .tupleDynamicAccess(let tuple, let index):
            let values = try sequenceElements(from: value(tuple))
            let position = try integer(index)
            guard position >= 1, position <= values.count else {
                throw EvalError.indexOutOfBounds(position, values.count)
            }
            return values[position - 1]
        case .tupleLength(let tuple):
            let values = try sequenceElements(from: value(tuple))
            return .integer(values.count)
        case .tupleAppend(let tuple, let element):
            var values = try sequenceElements(from: value(tuple))
            values.append(try value(element))
            return .tuple(values)
        case .tupleHead(let tuple):
            guard let first = try sequenceElements(from: value(tuple)).first else {
                throw EvalError.typeMismatch("Expected a nonempty tuple")
            }
            return first
        case .tupleTail(let tuple):
            let values = try sequenceElements(from: value(tuple))
            guard values.isEmpty == false else {
                throw EvalError.typeMismatch("Expected a nonempty tuple")
            }
            return .tuple(Array(values.dropFirst()))
        case .tupleConcatenate(let lhs, let rhs):
            let left = try sequenceElements(from: value(lhs))
            let right = try sequenceElements(from: value(rhs))
            return .tuple(left + right)
        case .recordLiteral(let fields):
            return .record(CompiledRecord(try fields.fields.map {
                .init(key: $0.key, value: try value($0.value))
            }))
        case .recordAccess(let record, _, let key):
            guard case .record(let values) = try value(record), let result = values.value(for: key) else {
                throw EvalError.typeMismatch("Expected record field")
            }
            return result
        case .domain(let function):
            switch try value(function) {
            case .function(let values):
                return .set(Set(values.keys))
            case .record(let values):
                return .set(Set(values.fields.map(\.key)))
            case .tuple(let values):
                return .set(Set(values.indices.map { .integer($0 + 1) }))
            default:
                throw EvalError.typeMismatch("Expected a function")
            }
        case .functionLiteral(let domain, let binder, let body):
            return try evaluateFunctionLiteral(domain: domain, binder: binder, body: body, bindings: bindings)
        case .functionApply(let function, let argument):
            if case .operatorReference(let id) = function {
                return try evaluateRecursiveCall(id, arguments: [argument], bindings: bindings)
            }
            let key = try value(argument)
            switch try value(function) {
            case .function(let values):
                guard let result = values[key] else {
                    throw EvalError.typeMismatch("Function argument is outside its domain")
                }
                return result
            case .tuple(let values):
                guard case .integer(let index) = key, index >= 1, index <= values.count else {
                    throw EvalError.typeMismatch("Tuple index is outside its domain")
                }
                return values[index - 1]
            case .record(let values):
                guard case .string = key,
                      let result = values.value(for: key)
                else {
                    throw EvalError.typeMismatch("Record field is unavailable")
                }
                return result
            default:
                throw EvalError.typeMismatch("Expected a function")
            }
        case .except(let function, let key, let replacement):
            let replacementValue = try value(replacement)
            switch try value(function) {
            case .function(var values):
                values[try value(key)] = replacementValue
                return .function(values)
            case .record(let values):
                let recordKey = try value(key)
                guard case .string = recordKey
                else {
                    throw EvalError.typeMismatch("Expected a record field")
                }
                return .record(values.replacing(replacementValue, for: recordKey))
            default:
                throw EvalError.typeMismatch("Expected a function")
            }
        case .forAll(let set, let binder, let predicate):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            for element in values where try evaluate(predicate, bindings: bindings.binding(element, to: binder)) != .boolean(true) {
                return .boolean(false)
            }
            return .boolean(true)
        case .exists(let set, let binder, let predicate):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            for element in values where try evaluate(predicate, bindings: bindings.binding(element, to: binder)) == .boolean(true) {
                return .boolean(true)
            }
            return .boolean(false)
        case .choose(let set, let binder, let predicate):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            for element in CompiledValue.sorted(values) where try evaluate(predicate, bindings: bindings.binding(element, to: binder)) == .boolean(true) {
                return element
            }
            throw EvalError.typeMismatch("No value satisfies CHOOSE")
        case .enabledAction(let action):
            return .boolean(enabledActions.contains(action))
        case .sequenceFromSet(let set):
            guard case .set(let values) = try value(set) else {
                throw EvalError.typeMismatch("Expected a set")
            }
            return .tuple(CompiledValue.sorted(values))
        case .setSum(let function, let set):
            guard case .function(let values) = try value(function), case .set(let members) = try value(set) else {
                throw EvalError.typeMismatch("Expected a function and a set")
            }
            return .integer(try members.reduce(0) { total, member in
                guard let result = values[member], case .integer(let value) = result else {
                    throw EvalError.typeMismatch("Expected integer function values")
                }
                return total + value
            })
        case .functionSet(let domain, let range):
            return try evaluateFunctionSet(domain: domain, range: range, bindings: bindings)
        case .foldFunction(let operation, let initial, let sequence):
            return try evaluateFoldFunction(
                operation: operation,
                initial: initial,
                sequence: sequence,
                bindings: bindings
            )
        case .caseExpr(let branches, let otherwise):
            var index = 0
            while index < branches.count {
                guard index + 1 < branches.count else {
                    throw EvalError.typeMismatch("CASE requires condition and result pairs")
                }
                if try boolean(branches[index]) {
                    return try value(branches[index + 1])
                }
                index += 2
            }
            guard let otherwise else {
                throw EvalError.typeMismatch("No CASE branch matched")
            }
            return try value(otherwise)
        case .operatorApplication(let operation, let arguments):
            return try evaluateOperatorApplication(operation, arguments: arguments, bindings: bindings)
        case .letValue(let binder, let valueExpression, let body):
            return try evaluate(
                body,
                bindings: bindings.binding(
                    { try evaluate(valueExpression, bindings: bindings) },
                    to: binder
                )
            )
        case .letIn(let operators, let body):
            var nested = localOperators
            for operation in operators {
                nested[operation.id] = operation
            }
            return try CompiledEvaluator(
                variableValue: variableValue,
                semantics: semantics,
                layout: layout,
                bindings: bindings,
                enabledActions: enabledActions,
                localOperators: nested,
                operatorBindings: operatorBindings,
                remainingOperatorCallDepth: remainingOperatorCallDepth
            ).evaluate(body)
        case .recursiveCall(let id, let arguments):
            return try evaluateRecursiveCall(id, arguments: arguments, bindings: bindings)
        }
    }
}

private extension CompiledEvaluator {
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

    func evaluatePowerSet(
        _ expression: CompiledStateExpr,
        bindings: CompiledBindings
    ) throws -> CompiledValue {
        guard case .set(let values) = try evaluate(expression, bindings: bindings) else {
            throw EvalError.typeMismatch("Expected a set")
        }
        let members = Array(values)
        return .set(Set((0..<(1 << members.count)).map { mask in
            .set(Set(members.enumerated().compactMap { index, member in
                mask & (1 << index) == 0 ? nil : member
            }))
        }))
    }

    func evaluateFunctionLiteral(
        domain: CompiledStateExpr,
        binder: BinderID,
        body: CompiledStateExpr,
        bindings: CompiledBindings
    ) throws -> CompiledValue {
        guard case .set(let values) = try evaluate(domain, bindings: bindings) else {
            throw EvalError.typeMismatch("Expected a function domain")
        }
        return .function(try values.reduce(into: [CompiledValue: CompiledValue]()) { result, element in
            result[element] = try evaluate(body, bindings: bindings.binding(element, to: binder))
        })
    }

    func evaluateFunctionSet(
        domain: CompiledStateExpr,
        range: CompiledStateExpr,
        bindings: CompiledBindings
    ) throws -> CompiledValue {
        guard case .set(let domainValues) = try evaluate(domain, bindings: bindings),
              case .set(let rangeValues) = try evaluate(range, bindings: bindings) else {
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

    func evaluateFoldFunction(
        operation: CompiledFormalLambda,
        initial: CompiledStateExpr,
        sequence: CompiledStateExpr,
        bindings: CompiledBindings
    ) throws -> CompiledValue {
        guard operation.parameters.count == 2 else {
            throw EvalError.typeMismatch("FoldFunction requires two parameters")
        }
        let values = try sequenceElements(from: evaluate(sequence, bindings: bindings))
        let initialValue = try evaluate(initial, bindings: bindings)
        return try values.reversed().reduce(initialValue) { result, element in
            try evaluate(
                operation.body,
                bindings: bindings
                    .binding(element, to: operation.parameters[0])
                    .binding(result, to: operation.parameters[1])
            )
        }
    }

    func evaluateOperatorApplication(
        _ operation: CompiledFormalOperator,
        arguments: [CompiledFormalCallArgument],
        bindings: CompiledBindings
    ) throws -> CompiledValue {
        guard remainingOperatorCallDepth > 0 else {
            throw EvalError.typeMismatch("Formal operator depth exceeded")
        }
        switch operation {
        case .lambda(let lambda):
            guard lambda.parameters.count == arguments.count else {
                throw EvalError.typeMismatch("Formal operator argument count differs")
            }
            var callBindings = bindings
            for (parameter, argument) in zip(lambda.parameters, arguments) {
                guard case .value(let argumentExpression) = argument else {
                    throw EvalError.typeMismatch("Expected a formal value argument")
                }
                callBindings = callBindings.binding(
                    { try evaluate(argumentExpression, bindings: bindings) },
                    to: parameter
                )
            }
            return try evaluateCallBody(lambda.body, bindings: callBindings)
        case .reference(let id, let arity):
            if let supplied = operatorBindings[id] {
                guard supplied.arity == arity else {
                    throw EvalError.typeMismatch("Formal operator argument count differs")
                }
                return try evaluateOperatorApplication(supplied, arguments: arguments, bindings: bindings)
            }
            guard let definition = semantics.formalOperatorDefinitions.first(where: { $0.id == id }) else {
                throw CompiledEvaluationError.unresolvedOperator
            }
            guard definition.parameters.count == arity, definition.parameters.count == arguments.count else {
                throw EvalError.typeMismatch("Formal operator argument count differs")
            }
            var callBindings = bindings
            var callOperatorBindings = operatorBindings
            for (parameter, argument) in zip(definition.parameters, arguments) {
                switch (parameter, argument) {
                case (.value(let binder), .value(let argumentExpression)):
                    callBindings = callBindings.binding(
                        { try evaluate(argumentExpression, bindings: bindings) },
                        to: binder
                    )
                case (.operator(let id, let arity), .operator(let operation)):
                    guard operation.arity == arity else {
                        throw EvalError.typeMismatch("Formal operator argument count differs")
                    }
                    callOperatorBindings[id] = operation
                default:
                    throw EvalError.typeMismatch("Expected a formal value argument")
                }
            }
            return try evaluateCallBody(
                definition.body,
                bindings: callBindings,
                operatorBindings: callOperatorBindings
            )
        }
    }

    func evaluateRecursiveCall(
        _ id: OperatorID,
        arguments: [CompiledStateExpr],
        bindings: CompiledBindings
    ) throws -> CompiledValue {
        guard remainingOperatorCallDepth > 0 else {
            throw EvalError.typeMismatch("Recursive operator depth exceeded")
        }
        if let operation = localOperators[id] {
            guard operation.parameters.count == arguments.count else {
                throw EvalError.typeMismatch("Recursive operator argument count differs")
            }
            var callBindings = bindings
            for (parameter, argument) in zip(operation.parameters, arguments) {
                callBindings = callBindings.binding(
                    { try evaluate(argument, bindings: bindings) },
                    to: parameter
                )
            }
            if let domain = operation.domain,
               case .boolean(false) = try evaluateCallBody(
                   .in(.boundValue(operation.parameters[0]), domain),
                   bindings: callBindings
               ) {
                throw EvalError.typeMismatch("Recursive operator argument is outside its domain")
            }
            return try evaluateCallBody(operation.body, bindings: callBindings)
        }
        if let function = semantics.recursiveFunctions.first(where: { $0.id == id }) {
            guard function.parameters.count == arguments.count else {
                throw EvalError.typeMismatch("Recursive operator argument count differs")
            }
            var callBindings = bindings
            for (parameter, argument) in zip(function.parameters, arguments) {
                callBindings = callBindings.binding(
                    { try evaluate(argument, bindings: bindings) },
                    to: parameter
                )
            }
            return try evaluateCallBody(function.body, bindings: callBindings)
        }
        throw CompiledEvaluationError.unresolvedOperator
    }

    func evaluateCallBody(
        _ expression: CompiledStateExpr,
        bindings: CompiledBindings,
        operatorBindings: [OperatorID: CompiledFormalOperator]? = nil
    ) throws -> CompiledValue {
        try CompiledEvaluator(
            variableValue: variableValue,
            semantics: semantics,
            layout: layout,
            bindings: bindings,
            enabledActions: enabledActions,
            localOperators: localOperators,
            operatorBindings: operatorBindings ?? self.operatorBindings,
            remainingOperatorCallDepth: remainingOperatorCallDepth - 1
        ).evaluate(expression)
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
