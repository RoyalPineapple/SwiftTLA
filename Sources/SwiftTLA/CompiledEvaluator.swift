enum EvalError: Error, CustomStringConvertible, Equatable, Sendable {
    enum IntegerOperation: String, Equatable, Sendable {
        case addition
        case subtraction
        case multiplication
        case division
        case remainder
        case negation
        case summation
    }

    enum ValueShape: String, Equatable, Sendable {
        case integer
        case boolean
        case set
        case sets
        case setOfSets = "set of sets"
        case sequence
        case nonemptySequence = "nonempty sequence"
        case function
        case functionAndSet = "function and set"
        case integerFunctionValues = "integer function values"
        case functionSetDomains = "function-set domains"
        case recordField = "record field"
    }

    enum Callable: String, Equatable, Sendable {
        case foldFunction = "FoldFunction"
        case formalOperator = "formal operator"
        case recursiveOperator = "recursive operator"
    }

    enum FormalArgumentKind: Equatable, Sendable {
        case value
        case `operator`(arity: Int)
    }

    case expected(ValueShape, actual: [CompiledValue])
    case noSatisfyingChoice
    case noMatchingCase
    case functionArgumentOutsideDomain(CompiledValue)
    case tupleIndexOutsideDomain(CompiledValue)
    case recordFieldUnavailable(CompiledValue)
    case invalidArity(Callable, expected: Int, actual: Int)
    case invalidFormalArgument(expected: FormalArgumentKind, actual: FormalArgumentKind)
    case recursiveArgumentOutsideDomain
    case invalidContinuation(availableValues: Int)
    case collectionState
    case powerSetTooLarge(actualCount: Int, maximumCount: Int)
    case divisionByZero
    case integerOverflow(IntegerOperation, operands: [Int])
    case indexOutOfBounds(Int, Int)
    case recursionDepthExceeded(Int)

    var description: String {
        switch self {
        case .expected(let expected, let actual):
            return "Expected \(expected.rawValue); received \(actual.map(\.kindDescription).joined(separator: ", "))"
        case .noSatisfyingChoice: return "No value satisfies CHOOSE"
        case .noMatchingCase: return "No CASE branch matched"
        case .functionArgumentOutsideDomain(let argument):
            return "Function argument \(argument.kindDescription) is outside its domain"
        case .tupleIndexOutsideDomain(let argument):
            return "Tuple index \(argument.kindDescription) is outside its domain"
        case .recordFieldUnavailable(let argument):
            return "Record field \(argument.kindDescription) is unavailable"
        case .invalidArity(let callable, let expected, let actual):
            return "\(callable.rawValue) requires \(expected) arguments; received \(actual)"
        case .invalidFormalArgument(let expected, let actual):
            return "Formal argument kind differs: expected \(expected); received \(actual)"
        case .recursiveArgumentOutsideDomain:
            return "Recursive operator argument is outside its declared domain"
        case .invalidContinuation(let availableValues):
            return "Evaluator continuation has \(availableValues) values"
        case .collectionState: return "Collection evaluation reached an invalid state"
        case .powerSetTooLarge(let actualCount, let maximumCount):
            return "Power-set input has \(actualCount) members; the maximum is \(maximumCount)"
        case .divisionByZero: return "Division by zero"
        case .integerOverflow(let operation, let operands):
            return "Integer \(operation.rawValue) overflowed for \(operands.map(String.init).joined(separator: ", "))"
        case .indexOutOfBounds(let index, let count): return "Index \(index) out of bounds (1..\(count))"
        case .recursionDepthExceeded(let limit): return "Evaluation exceeded recursive depth \(limit)"
        }
    }
}

private extension CompiledValue {
    var kindDescription: String {
        switch self {
        case .integer: "integer"
        case .boolean: "boolean"
        case .string: "string"
        case .controlLocation: "control location"
        case .set: "set"
        case .tuple: "tuple"
        case .record: "record"
        case .function: "function"
        case .constant: "constant"
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
    var operatorBindings: [OperatorID: EvaluatorOperatorBinding]
}

private final class EvaluatorOperatorBinding {
    let operation: CompiledFormalOperator
    let scope: EvaluatorScope

    init(_ operation: CompiledFormalOperator, scope: EvaluatorScope) {
        self.operation = operation
        self.scope = scope
    }
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
    case foldStep(CompiledFormalLambda, members: [CompiledValue], index: Int, accumulator: CompiledValue, scope: EvaluatorScope)
    case foldResult(CompiledFormalLambda, members: [CompiledValue], index: Int, scope: EvaluatorScope)
    case formalCall(
        EvaluatorOperatorBinding,
        arguments: [CompiledFormalCallArgument],
        argumentScope: EvaluatorScope
    )
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
    private static let maximumRecursiveDepth = 4_096

    init(
        state: CompiledState,
        semantics: CompiledSemantics,
        layout: CompiledLayout,
        bindings: CompiledBindings = .init(),
        enabledActions: Set<ActionID> = [],
        localOperators: [OperatorID: CompiledLocalOperator] = [:]
    ) {
        self.variableValue = { try state.value(for: $0) }
        self.semantics = semantics
        self.layout = layout
        self.bindings = bindings
        self.enabledActions = enabledActions
        self.localOperators = localOperators
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
    }

    func evaluate(_ expression: CompiledStateExpr) throws -> CompiledValue {
        let scope = EvaluatorScope(
            bindings: .init(inherited: bindings),
            localOperators: localOperators,
            operatorBindings: [:]
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
                throw EvalError.expected(.integer, actual: [value])
            }
            return integer
        }

        func boolean(_ value: CompiledValue) throws -> Bool {
            guard case .boolean(let boolean) = value else {
                throw EvalError.expected(.boolean, actual: [value])
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
                throw EvalError.noSatisfyingChoice
            default:
                throw EvalError.collectionState
            }
        }

        while let task = tasks.popLast() {
            switch task {
            case .finish(let expression):
                switch expression {
                case .add:
                    let rhs = try integer(popValue(from: &values))
                    let lhs = try integer(popValue(from: &values))
                    values.append(.integer(try checkedInteger(
                        lhs.addingReportingOverflow(rhs),
                        operation: .addition,
                        operands: [lhs, rhs]
                    )))
                case .subtract:
                    let rhs = try integer(popValue(from: &values))
                    let lhs = try integer(popValue(from: &values))
                    values.append(.integer(try checkedInteger(
                        lhs.subtractingReportingOverflow(rhs),
                        operation: .subtraction,
                        operands: [lhs, rhs]
                    )))
                case .multiply:
                    let rhs = try integer(popValue(from: &values))
                    let lhs = try integer(popValue(from: &values))
                    values.append(.integer(try checkedInteger(
                        lhs.multipliedReportingOverflow(by: rhs),
                        operation: .multiplication,
                        operands: [lhs, rhs]
                    )))
                case .divide, .integerDivide:
                    let dividend = try integer(popValue(from: &values))
                    let divisor = try integer(popValue(from: &values))
                    if divisor == 0 { throw EvalError.divisionByZero }
                    if dividend == .min && divisor == -1 {
                        throw EvalError.integerOverflow(.division, operands: [dividend, divisor])
                    }
                    values.append(.integer(dividend / divisor))
                case .modulo:
                    let dividend = try integer(popValue(from: &values))
                    let divisor = try integer(popValue(from: &values))
                    if divisor == 0 { throw EvalError.divisionByZero }
                    if dividend == .min && divisor == -1 {
                        throw EvalError.integerOverflow(.remainder, operands: [dividend, divisor])
                    }
                    values.append(.integer(dividend % divisor))
                case .negate:
                    let operand = try integer(popValue(from: &values))
                    values.append(.integer(try checkedInteger(
                        0.subtractingReportingOverflow(operand),
                        operation: .negation,
                        operands: [operand]
                    )))
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
                        throw EvalError.expected(.set, actual: [setValue])
                    }
                    values.append(.boolean(set.contains(member)))
                case .subset:
                    let rhs = try popValue(from: &values)
                    let lhs = try popValue(from: &values)
                    guard case .set(let lhs) = lhs, case .set(let rhs) = rhs else {
                        throw EvalError.expected(.sets, actual: [lhs, rhs])
                    }
                    values.append(.boolean(lhs.isSubset(of: rhs)))
                case .union:
                    let rhs = try popValue(from: &values)
                    let lhs = try popValue(from: &values)
                    guard case .set(let lhs) = lhs, case .set(let rhs) = rhs else {
                        throw EvalError.expected(.sets, actual: [lhs, rhs])
                    }
                    values.append(.set(lhs.union(rhs)))
                case .intersection:
                    let rhs = try popValue(from: &values)
                    let lhs = try popValue(from: &values)
                    guard case .set(let lhs) = lhs, case .set(let rhs) = rhs else {
                        throw EvalError.expected(.sets, actual: [lhs, rhs])
                    }
                    values.append(.set(lhs.intersection(rhs)))
                case .setDifference:
                    let rhs = try popValue(from: &values)
                    let lhs = try popValue(from: &values)
                    guard case .set(let lhs) = lhs, case .set(let rhs) = rhs else {
                        throw EvalError.expected(.sets, actual: [lhs, rhs])
                    }
                    values.append(.set(lhs.subtracting(rhs)))
                case .cardinality:
                    let value = try popValue(from: &values)
                    guard case .set(let set) = value else {
                        throw EvalError.expected(.set, actual: [value])
                    }
                    values.append(.integer(set.count))
                case .powerSet:
                    let value = try popValue(from: &values)
                    guard case .set(let set) = value else {
                        throw EvalError.expected(.set, actual: [value])
                    }
                    values.append(try powerSet(of: set))
                case .unionAll:
                    let value = try popValue(from: &values)
                    guard case .set(let members) = value else {
                        throw EvalError.expected(.set, actual: [value])
                    }
                    values.append(.set(try members.reduce(into: Set<CompiledValue>()) { unionMembers, member in
                        guard case .set(let nested) = member else {
                            throw EvalError.expected(.setOfSets, actual: [member])
                        }
                        unionMembers.formUnion(nested)
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
                    let sequence = try sequenceElements(from: popValue(from: &values))
                    guard let first = sequence.first else {
                        throw EvalError.expected(.nonemptySequence, actual: [.tuple(sequence)])
                    }
                    values.append(first)
                case .tupleTail:
                    let tuple = try sequenceElements(from: popValue(from: &values))
                    guard tuple.isEmpty == false else {
                        throw EvalError.expected(.nonemptySequence, actual: [.tuple(tuple)])
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
                    let recordValue = try popValue(from: &values)
                    guard case .record(let record) = recordValue,
                          let value = record.value(for: key)
                    else {
                        throw EvalError.expected(.recordField, actual: [recordValue])
                    }
                    values.append(value)
                case .domain:
                    let value = try popValue(from: &values)
                    switch value {
                    case .function(let function): values.append(.set(Set(function.keys)))
                    case .record(let record): values.append(.set(Set(record.fields.map(\.key))))
                    case .tuple(let tuple): values.append(.set(Set(tuple.indices.map { .integer($0 + 1) })))
                    default: throw EvalError.expected(.function, actual: [value])
                    }
                case .functionApply:
                    let function = try popValue(from: &values)
                    let key = try popValue(from: &values)
                    switch function {
                    case .function(let function):
                        guard let value = function[key] else {
                            throw EvalError.functionArgumentOutsideDomain(key)
                        }
                        values.append(value)
                    case .tuple(let tuple):
                        guard case .integer(let index) = key, index >= 1, index <= tuple.count else {
                            throw EvalError.tupleIndexOutsideDomain(key)
                        }
                        values.append(tuple[index - 1])
                    case .record(let record):
                        guard case .string = key, let value = record.value(for: key) else {
                            throw EvalError.recordFieldUnavailable(key)
                        }
                        values.append(value)
                    default:
                        throw EvalError.expected(.function, actual: [function])
                    }
                case .sequenceFromSet:
                    let value = try popValue(from: &values)
                    guard case .set(let set) = value else {
                        throw EvalError.expected(.set, actual: [value])
                    }
                    values.append(.tuple(CompiledValue.sorted(set)))
                case .setSum:
                    let membersValue = try popValue(from: &values)
                    let functionValue = try popValue(from: &values)
                    guard case .set(let members) = membersValue,
                          case .function(let function) = functionValue
                    else {
                        throw EvalError.expected(.functionAndSet, actual: [functionValue, membersValue])
                    }
                    let integers = try CompiledValue.sorted(members).map { member in
                        guard let mapped = function[member], case .integer(let value) = mapped else {
                            throw EvalError.expected(
                                .integerFunctionValues,
                                actual: function[member].map { [$0] } ?? []
                            )
                        }
                        return value
                    }
                    values.append(.integer(try integerSum(integers)))
                case .functionSet:
                    let range = try popValue(from: &values)
                    let domain = try popValue(from: &values)
                    values.append(try functionSet(domain: domain, range: range))
                default:
                    throw EvalError.invalidContinuation(availableValues: values.count)
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
                let value = try popValue(from: &values)
                guard case .set(let set) = value else {
                    throw EvalError.expected(.set, actual: [value])
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
                    throw EvalError.collectionState
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
                        throw EvalError.noMatchingCase
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
                    throw EvalError.expected(.function, actual: [function])
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
                        throw EvalError.expected(.recordField, actual: [key])
                    }
                    values.append(.record(record.replacing(replacement, for: key)))
                default:
                    throw EvalError.expected(.function, actual: [function])
                }

            case .foldSequence(let operation, let initial, let scope):
                let members = try sequenceElements(from: popValue(from: &values))
                tasks.append(.foldInitial(operation, members: Array(members.reversed()), scope: scope))
                tasks.append(.expression(initial, scope))

            case .foldInitial(let operation, let members, let scope):
                let initial = try popValue(from: &values)
                tasks.append(.foldStep(operation, members: members, index: 0, accumulator: initial, scope: scope))

            case .foldStep(let operation, let members, let index, let accumulator, let scope):
                guard operation.parameters.count == 2 else {
                    throw EvalError.invalidArity(
                        .foldFunction,
                        expected: 2,
                        actual: operation.parameters.count
                    )
                }
                guard index < members.count else {
                    values.append(accumulator)
                    continue
                }
                var bodyScope = scope
                bodyScope.bindings = bodyScope.bindings
                    .binding(members[index], to: operation.parameters[0])
                    .binding(accumulator, to: operation.parameters[1])
                tasks.append(.foldResult(operation, members: members, index: index, scope: scope))
                tasks.append(.expression(operation.body, bodyScope))

            case .foldResult(let operation, let members, let index, let scope):
                let accumulator = try popValue(from: &values)
                tasks.append(.foldStep(operation, members: members, index: index + 1, accumulator: accumulator, scope: scope))

            case .formalCall(let boundOperation, let arguments, let argumentScope):
                switch boundOperation.operation {
                case .lambda(let lambda):
                    guard lambda.parameters.count == arguments.count else {
                        throw EvalError.invalidArity(
                            .formalOperator,
                            expected: lambda.parameters.count,
                            actual: arguments.count
                        )
                    }
                    var callScope = boundOperation.scope
                    for (parameter, argument) in zip(lambda.parameters, arguments) {
                        guard case .value(let expression) = argument else {
                            guard case .operator(let operation) = argument else {
                                throw EvalError.invalidFormalArgument(expected: .value, actual: .value)
                            }
                            throw EvalError.invalidFormalArgument(
                                expected: .value,
                                actual: .operator(arity: operation.arity)
                            )
                        }
                        callScope.bindings = callScope.bindings.binding(
                            expression,
                            from: argumentScope,
                            to: parameter
                        )
                    }
                    tasks.append(.expression(lambda.body, callScope))

                case .reference(let id, let arity):
                    if let supplied = boundOperation.scope.operatorBindings[id] {
                        guard supplied.operation.arity == arity else {
                            throw EvalError.invalidArity(
                                .formalOperator,
                                expected: arity,
                                actual: supplied.operation.arity
                            )
                        }
                        tasks.append(.formalCall(
                            supplied,
                            arguments: arguments,
                            argumentScope: argumentScope
                        ))
                        continue
                    }
                    guard let definition = formalDefinitions[id] else {
                        throw CompiledEvaluationError.unresolvedOperator
                    }
                    guard definition.parameters.count == arity,
                          definition.parameters.count == arguments.count
                    else {
                        throw EvalError.invalidArity(
                            .formalOperator,
                            expected: definition.parameters.count,
                            actual: arguments.count
                        )
                    }
                    var callScope = boundOperation.scope
                    for (parameter, argument) in zip(definition.parameters, arguments) {
                        switch (parameter, argument) {
                        case (.value(let binder), .value(let expression)):
                            callScope.bindings = callScope.bindings.binding(
                                expression,
                                from: argumentScope,
                                to: binder
                            )
                        case (.operator(let operatorID, let expectedArity), .operator(let supplied)):
                            guard supplied.arity == expectedArity else {
                                throw EvalError.invalidArity(
                                    .formalOperator,
                                    expected: expectedArity,
                                    actual: supplied.arity
                                )
                            }
                            callScope.operatorBindings[operatorID] = .init(supplied, scope: argumentScope)
                        default:
                            let expected: EvalError.FormalArgumentKind
                            let actual: EvalError.FormalArgumentKind
                            switch parameter {
                            case .value: expected = .value
                            case .operator(_, let arity): expected = .operator(arity: arity)
                            }
                            switch argument {
                            case .value: actual = .value
                            case .operator(let operation): actual = .operator(arity: operation.arity)
                            }
                            throw EvalError.invalidFormalArgument(expected: expected, actual: actual)
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
                        throw EvalError.invalidArity(
                            .recursiveOperator,
                            expected: operation.parameters.count,
                            actual: arguments.count
                        )
                    }
                    var callScope = scope
                    for (parameter, argument) in zip(operation.parameters, arguments) {
                        callScope.bindings = callScope.bindings.binding(argument, from: scope, to: parameter)
                    }
                    if let domain = operation.domain {
                        guard let parameter = operation.parameters.first else {
                            throw EvalError.invalidArity(
                                .recursiveOperator,
                                expected: 1,
                                actual: operation.parameters.count
                            )
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
                    throw EvalError.invalidArity(
                        .recursiveOperator,
                        expected: function.parameters.count,
                        actual: arguments.count
                    )
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
                    throw EvalError.recursiveArgumentOutsideDomain
                }
                tasks.append(.expression(body, scope))

            case .store(let thunk):
                let value = try popValue(from: &values)
                thunk.value = value
                values.append(value)

            case .expression(let expression, let scope):
                switch expression {
                case .value(let value):
                    values.append(value)
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
                        tasks.append(.formalCall(
                            .init(.reference(id, arity: 0), scope: scope),
                            arguments: [],
                            argumentScope: scope
                        ))
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
                        .init(.lambda(operation), scope: scope),
                        arguments: arguments.map(CompiledFormalCallArgument.value),
                        argumentScope: scope
                    ))
                case .operatorApplication(let operation, let arguments):
                    tasks.append(.formalCall(
                        .init(.reference(operation, arity: arguments.count), scope: scope),
                        arguments: arguments,
                        argumentScope: scope
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
            throw EvalError.invalidContinuation(availableValues: values.count)
        }
        return value
    }
}

private extension CompiledEvaluator {
    func checkedInteger(
        _ result: (partialValue: Int, overflow: Bool),
        operation: EvalError.IntegerOperation,
        operands: [Int]
    ) throws -> Int {
        if result.overflow {
            throw EvalError.integerOverflow(operation, operands: operands)
        }
        return result.partialValue
    }

    func integerSum(_ values: [Int]) throws -> Int {
        let operands = values.sorted()
        var negative = operands.filter { $0 < 0 }
        var nonnegative = operands.filter { $0 >= 0 }

        while negative.isEmpty == false && nonnegative.isEmpty == false {
            let lhs = negative.removeLast()
            let rhs = nonnegative.removeLast()
            let combined = try checkedInteger(
                lhs.addingReportingOverflow(rhs),
                operation: .summation,
                operands: operands
            )
            if combined < 0 {
                negative.append(combined)
            } else {
                nonnegative.append(combined)
            }
        }

        return try (negative + nonnegative).reduce(0) { total, value in
            try checkedInteger(
                total.addingReportingOverflow(value),
                operation: .summation,
                operands: operands
            )
        }
    }

    func popValue(from values: inout [CompiledValue]) throws -> CompiledValue {
        guard let value = values.popLast() else {
            throw EvalError.invalidContinuation(availableValues: 0)
        }
        return value
    }

    func popValues(_ count: Int, from values: inout [CompiledValue]) throws -> [CompiledValue] {
        guard values.count >= count else {
            throw EvalError.invalidContinuation(availableValues: values.count)
        }
        let start = values.count - count
        let popped = Array(values[start...])
        values.removeSubrange(start...)
        return popped
    }

    func sequenceElements(from value: CompiledValue) throws -> [CompiledValue] {
        switch value {
        case .tuple(let values):
            return values
        case .function(let values):
            return try (0..<values.count).map { offset in
                guard let element = values[.integer(offset + 1)] else {
                    throw EvalError.expected(.sequence, actual: [.function(values)])
                }
                return element
            }
        default:
            throw EvalError.expected(.sequence, actual: [value])
        }
    }

    func powerSet(of values: Set<CompiledValue>) throws -> CompiledValue {
        guard values.count < Int.bitWidth else {
            throw EvalError.powerSetTooLarge(
                actualCount: values.count,
                maximumCount: Int.bitWidth - 1
            )
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
            throw EvalError.expected(.functionSetDomains, actual: [domain, range])
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
    guard let value = try CompiledRuntime(compilation: compilation)
        .evaluate([invariant.body], in: state)
        .first else {
        throw CompiledEvaluationError.unresolvedOperator
    }
    return try value.rendered(using: compilation.layout)
}
