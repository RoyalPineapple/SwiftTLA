package enum EvalError: Error, CustomStringConvertible, Equatable, Sendable {
    package enum ValueShape: String, Equatable, Sendable {
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

    package enum Callable: String, Equatable, Sendable {
        case foldFunction = "FoldFunction"
        case formalOperator = "formal operator"
        case recursiveOperator = "recursive operator"
    }

    package enum FormalArgumentKind: Equatable, Sendable {
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
    case collectionCardinalityOverflow(NativeMachineEvaluationError.CollectionOperation, operands: [Int])
    case divisionByZero
    case negativeModuloDivisor(Int)
    case integerOverflow(NativeMachineEvaluationError.IntegerOperation, operands: [Int])
    case indexOutOfBounds(Int, Int)
    case recursionDepthExceeded(Int)

    package var description: String {
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
        case .collectionCardinalityOverflow(let operation, let operands):
            return "Collection \(operation.rawValue) cardinality exceeds Int for \(operands.map(String.init).joined(separator: ", "))"
        case .divisionByZero: return "Division by zero"
        case .negativeModuloDivisor(let divisor): return "Modulo requires a positive divisor; received \(divisor)"
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
    enum State {
        case pending(CompiledExpression, EvaluatorScope)
        case evaluated(CompiledValue)
        case discarded
    }

    var state: State

    init(expression: CompiledExpression, scope: EvaluatorScope) {
        state = .pending(expression, scope)
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
        _ expression: CompiledExpression,
        from scope: EvaluatorScope,
        to binder: BinderID,
        retainingIn pendingArguments: inout [ObjectIdentifier: EvaluatorThunk]
    ) -> EvaluatorBindings {
        var bindings = self
        if case .boundValue(let source) = expression.operation,
           let binding = scope.bindings.values[source] {
            bindings.values[binder] = binding
            return bindings
        }
        let thunk = EvaluatorThunk(expression: expression, scope: scope)
        pendingArguments[ObjectIdentifier(thunk)] = thunk
        bindings.values[binder] = .expression(thunk)
        return bindings
    }
}

private struct EvaluatorScope {
    var bindings: EvaluatorBindings
    var operatorBindings: [OperatorID: EvaluatorOperatorBinding]
    var callbacks: [ResolvedCallbackID: EvaluatorFunctionBinding] = [:]
}

private struct EvaluatorFunctionBinding {
    let function: ResolvedFunctionID
    let scope: EvaluatorScope
}

private struct EvaluatorOperatorBinding {
    let operation: CompiledFormalOperator
    let scope: EvaluatorScope
}

/// Collection iteration owns values and progress, independently of expression syntax.
private struct CollectionEvaluation {
    private enum Accumulation {
        case values([CompiledValue])
        case function([CompiledValue: CompiledValue])
    }

    let binder: BinderID
    private let operation: CompiledOperation
    private let members: [CompiledValue]
    private var index = 0
    private var accumulated: Accumulation

    init(operation: CompiledOperation, domain: CompiledValue) throws {
        if case .sequenceSelect = operation {
            members = try sequenceElements(from: domain)
        } else {
            guard case .set(let values) = domain else { throw EvalError.expected(.set, actual: [domain]) }
            members = CompiledValue.sorted(values)
        }
        switch operation {
        case .setFilter(let binder), .setMap(let binder), .functionLiteral(let binder),
             .forAll(let binder), .exists(let binder), .choose(let binder),
             .sequenceSelect(let binder): self.binder = binder
        default: throw EvalError.collectionState
        }
        self.operation = operation
        if case .functionLiteral = operation { accumulated = .function([:]) }
        else { accumulated = .values([]) }
    }

    var member: CompiledValue? { index < members.count ? members[index] : nil }

    func result() throws -> CompiledValue {
        switch (operation, accumulated) {
        case (.setFilter, .values(let values)), (.setMap, .values(let values)): return .set(Set(values))
        case (.sequenceSelect, .values(let values)): return .tuple(values)
        case (.functionLiteral, .function(let values)): return .function(values)
        case (.forAll, _): return .boolean(true)
        case (.exists, _): return .boolean(false)
        case (.choose, _): throw EvalError.noSatisfyingChoice
        default: throw EvalError.collectionState
        }
    }

    /// A value ends a short-circuiting operation; nil requests the next member.
    mutating func accept(_ value: CompiledValue) throws -> CompiledValue? {
        switch (operation, accumulated) {
        case (.setFilter, .values(var selected)), (.sequenceSelect, .values(var selected)):
            if try boolean(value) { selected.append(members[index]) }
            accumulated = .values(selected)
        case (.setMap, .values(var mapped)):
            mapped.append(value)
            accumulated = .values(mapped)
        case (.functionLiteral, .function(var function)):
            function[members[index]] = value
            accumulated = .function(function)
        case (.forAll, _):
            if try !boolean(value) { return .boolean(false) }
        case (.exists, _):
            if try boolean(value) { return .boolean(true) }
        case (.choose, _):
            if try boolean(value) { return members[index] }
        default: throw EvalError.collectionState
        }
        index += 1
        return nil
    }
}

private struct FoldEvaluation {
    let memberParameter: BinderID
    let accumulatorParameter: BinderID
    var members: ArraySlice<CompiledValue>
    var accumulator: CompiledValue

    init(parameters: [BinderID], members: [CompiledValue], initial: CompiledValue) throws {
        guard parameters.count == 2 else {
            throw EvalError.invalidArity(.foldFunction, expected: 2, actual: parameters.count)
        }
        memberParameter = parameters[0]
        accumulatorParameter = parameters[1]
        self.members = members[...]
        accumulator = initial
    }
}

private enum EvaluatorTask {
    case expression(CompiledExpression, EvaluatorScope)
    case finish(CompiledOperation, operandCount: Int)
    case booleanResult
    case conditional(then: CompiledExpression, otherwise: CompiledExpression, scope: EvaluatorScope)
    case booleanRight(CompiledExpression, scope: EvaluatorScope, shortCircuit: Bool)
    case collectionStart(CompiledOperation, body: CompiledExpression, scope: EvaluatorScope)
    case collectionStep(CollectionEvaluation, body: CompiledExpression, scope: EvaluatorScope)
    case collectionResult(CollectionEvaluation, body: CompiledExpression, scope: EvaluatorScope)
    case caseBranch([CompiledCaseBranch], index: Int, otherwise: CompiledExpression?, scope: EvaluatorScope)
    case caseCondition([CompiledCaseBranch], index: Int, otherwise: CompiledExpression?, scope: EvaluatorScope)
    case exceptFunction(key: CompiledExpression, scope: EvaluatorScope)
    case foldSequence(parameters: [BinderID], body: CompiledExpression, initial: CompiledExpression, scope: EvaluatorScope)
    case foldInitial(parameters: [BinderID], body: CompiledExpression, members: [CompiledValue], scope: EvaluatorScope)
    case foldStep(FoldEvaluation, body: CompiledExpression, scope: EvaluatorScope)
    case foldResult(FoldEvaluation, body: CompiledExpression, scope: EvaluatorScope)
    case formalCall(
        EvaluatorOperatorBinding,
        arguments: [CompiledFormalCallArgument],
        argumentScope: EvaluatorScope
    )
    case callReturn
    case localDomain(CompiledExpression, scope: EvaluatorScope)
    case store(EvaluatorThunk)
}

struct CompiledEvaluator: Sendable {
    let variableValue: @Sendable (VariableID) throws -> CompiledValue
    let operators: CompiledOperators
    let functions: [ResolvedFunction]
    let bindings: CompiledBindings
    let enabledActions: Set<ActionID>

    init(
        state: CompiledState,
        operators: CompiledOperators,
        functions: [ResolvedFunction] = [],
        bindings: CompiledBindings = .init(),
        enabledActions: Set<ActionID> = []
    ) {
        self.variableValue = { try state.value(for: $0) }
        self.operators = operators
        self.functions = functions
        self.bindings = bindings
        self.enabledActions = enabledActions
    }

    init(
        variableValues: [VariableID: CompiledValue],
        operators: CompiledOperators,
        functions: [ResolvedFunction] = []
    ) {
        self.variableValue = { variable in
            guard let value = variableValues[variable] else {
                throw CompiledEvaluationError.uninitializedVariable(variable)
            }
            return value
        }
        self.operators = operators
        self.functions = functions
        self.bindings = .init()
        self.enabledActions = []
    }

    func evaluate(_ expression: CompiledExpression) throws -> CompiledValue {
        if case .value(let value) = expression.operation { return value }
        var pendingArguments: [ObjectIdentifier: EvaluatorThunk] = [:]
        defer {
            // Keep every pending argument alive while breaking captured-scope
            // chains, including when evaluation exits before demanding them.
            for argument in pendingArguments.values { argument.state = .discarded }
        }
        let scope = EvaluatorScope(
            bindings: .init(inherited: bindings),
            operatorBindings: [:]
        )
        var tasks = [EvaluatorTask.expression(expression, scope)]
        var values: [CompiledValue] = []
        var recursiveDepth = 0

        while let task = tasks.popLast() {
            switch task {
            case .finish(let operation, let operandCount):
                try operation.apply(to: &values, operandCount: operandCount)

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

            case .collectionStart(let operation, let body, let scope):
                let collection = try CollectionEvaluation(operation: operation, domain: popValue(from: &values))
                tasks.append(.collectionStep(collection, body: body, scope: scope))

            case .collectionStep(let collection, let body, let scope):
                guard let member = collection.member else {
                    values.append(try collection.result())
                    continue
                }
                var bodyScope = scope
                bodyScope.bindings = bodyScope.bindings.binding(member, to: collection.binder)
                tasks.append(.collectionResult(collection, body: body, scope: scope))
                tasks.append(.expression(body, bodyScope))

            case .collectionResult(var collection, let body, let scope):
                if let result = try collection.accept(popValue(from: &values)) {
                    values.append(result)
                } else {
                    tasks.append(.collectionStep(collection, body: body, scope: scope))
                }

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
                case .function, .record, .tuple:
                    values.append(function)
                    tasks.append(.finish(.except, operandCount: 3))
                    tasks.append(.expression(key, scope))
                default:
                    throw EvalError.expected(.function, actual: [function])
                }

            case .foldSequence(let parameters, let body, let initial, let scope):
                let members = try sequenceElements(from: popValue(from: &values))
                tasks.append(.foldInitial(parameters: parameters, body: body, members: members, scope: scope))
                tasks.append(.expression(initial, scope))

            case .foldInitial(let parameters, let body, let members, let scope):
                let fold = try FoldEvaluation(parameters: parameters, members: members, initial: popValue(from: &values))
                tasks.append(.foldStep(fold, body: body, scope: scope))

            case .foldStep(var fold, let body, let scope):
                guard let member = fold.members.popLast() else {
                    values.append(fold.accumulator)
                    continue
                }
                var bodyScope = scope
                bodyScope.bindings = bodyScope.bindings
                    .binding(member, to: fold.memberParameter)
                    .binding(fold.accumulator, to: fold.accumulatorParameter)
                tasks.append(.foldResult(fold, body: body, scope: scope))
                tasks.append(.expression(body, bodyScope))

            case .foldResult(var fold, let body, let scope):
                fold.accumulator = try popValue(from: &values)
                tasks.append(.foldStep(fold, body: body, scope: scope))

            case .formalCall(let boundOperation, let arguments, let argumentScope):
                let operation = boundOperation.operation
                if case .reference(let id, let arity) = operation,
                   let supplied = boundOperation.scope.operatorBindings[id] {
                    guard supplied.operation.arity == arity else {
                        throw EvalError.invalidArity(.formalOperator, expected: arity, actual: supplied.operation.arity)
                    }
                    tasks.append(.formalCall(supplied, arguments: arguments, argumentScope: argumentScope))
                    continue
                }
                guard let definition = operators[operation.declarationID] else {
                    throw CompiledEvaluationError.unresolvedOperator
                }
                let parameters = definition.parameters
                let body = definition.body
                let domain = definition.domain
                guard parameters.count == operation.arity else {
                    throw EvalError.invalidArity(.formalOperator, expected: parameters.count, actual: operation.arity)
                }
                guard parameters.count == arguments.count else {
                    throw EvalError.invalidArity(.formalOperator, expected: parameters.count, actual: arguments.count)
                }
                try beginCall(tasks: &tasks, depth: &recursiveDepth)
                var callScope = boundOperation.scope
                for (parameter, argument) in zip(parameters, arguments) {
                    switch (parameter, argument) {
                    case (.value(let binder, _), .value(let expression)):
                        callScope.bindings = callScope.bindings.binding(
                            expression,
                            from: argumentScope,
                            to: binder,
                            retainingIn: &pendingArguments
                        )
                    case (.operator(let operatorID, let expectedArity), .operator(let supplied)):
                        guard supplied.arity == expectedArity else {
                            throw EvalError.invalidArity(
                                .formalOperator,
                                expected: expectedArity,
                                actual: supplied.arity
                            )
                        }
                        callScope.operatorBindings[operatorID] = .init(operation: supplied, scope: argumentScope)
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
                if let domain {
                    guard case .value(let parameter, _) = parameters.first else {
                        throw EvalError.invalidArity(
                            .recursiveOperator,
                            expected: 1,
                            actual: parameters.count
                        )
                    }
                    tasks.append(.localDomain(body, scope: callScope))
                    tasks.append(.finish(.in, operandCount: 2))
                    tasks.append(.expression(.boundValue(parameter), callScope))
                    tasks.append(.expression(domain, callScope))
                } else {
                    tasks.append(.expression(body, callScope))
                }

            case .callReturn:
                recursiveDepth -= 1

            case .localDomain(let body, let scope):
                if try popValue(from: &values) == .boolean(false) {
                    throw EvalError.recursiveArgumentOutsideDomain
                }
                tasks.append(.expression(body, scope))

            case .store(let thunk):
                let value = try popValue(from: &values)
                // The cached result replaces its inputs so completed arguments
                // do not retain chains of earlier lexical scopes.
                thunk.state = .evaluated(value)
                pendingArguments.removeValue(forKey: ObjectIdentifier(thunk))
                values.append(value)

            case .expression(let expression, let scope):
                func schedule(_ operation: CompiledOperation, _ operands: [CompiledExpression]) {
                    tasks.append(.finish(operation, operandCount: operands.count))
                    let evaluationOrder = operation.evaluatesRightOperandFirst ? Array(operands.reversed()) : operands
                    for operand in evaluationOrder.reversed() { tasks.append(.expression(operand, scope)) }
                }
                func call(_ id: OperatorID, arguments: [CompiledExpression]) {
                    tasks.append(.formalCall(
                        .init(operation: .reference(id, arity: arguments.count), scope: scope),
                        arguments: arguments.map(CompiledFormalCallArgument.value),
                        argumentScope: scope
                    ))
                }
                switch expression.operation {
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
                            switch thunk.state {
                            case .evaluated(let value):
                                values.append(value)
                            case .discarded:
                                throw EvalError.invalidContinuation(availableValues: values.count)
                            case .pending(let expression, let argumentScope):
                                tasks.append(.store(thunk))
                                tasks.append(.expression(expression, argumentScope))
                            }
                        }
                    } else {
                        values.append(try scope.bindings.inherited.value(for: binder))
                    }
                case .controlLocation(let label):
                    values.append(.controlLocation(label))
                case .operatorReference(let id):
                    call(id, arguments: [])
                case .and:
                    let lhs = expression.children[0]
                    let rhs = expression.children[1]

                    tasks.append(.booleanRight(rhs, scope: scope, shortCircuit: false))
                    tasks.append(.expression(lhs, scope))
                case .or:
                    let lhs = expression.children[0]
                    let rhs = expression.children[1]

                    tasks.append(.booleanRight(rhs, scope: scope, shortCircuit: true))
                    tasks.append(.expression(lhs, scope))
                case .ifThenElse:
                    let condition = expression.children[0]
                    let then = expression.children[1]
                    let otherwise = expression.children[2]

                    tasks.append(.conditional(then: then, otherwise: otherwise, scope: scope))
                    tasks.append(.expression(condition, scope))
                case .setFilter(let binder):
                    let set = expression.children[0]
                    let predicate = expression.children[1]

                    tasks.append(.collectionStart(.setFilter(binder), body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .setMap(let binder):
                    let body = expression.children[0]
                    let set = expression.children[1]

                    tasks.append(.collectionStart(.setMap(binder), body: body, scope: scope))
                    tasks.append(.expression(set, scope))
                case .functionLiteral(let binder):
                    let domain = expression.children[0]
                    let body = expression.children[1]

                    tasks.append(.collectionStart(.functionLiteral(binder), body: body, scope: scope))
                    tasks.append(.expression(domain, scope))
                case .functionApply:
                    let function = expression.children[0]
                    let argument = expression.children[1]

                    if case .operatorReference(let id) = function.operation {
                        call(id, arguments: [argument])
                    } else {
                        schedule(.functionApply, [function, argument])
                    }
                case .except:
                    let function = expression.children[0]
                    let key = expression.children[1]
                    let replacement = expression.children[2]

                    tasks.append(.exceptFunction(key: key, scope: scope))
                    tasks.append(.expression(function, scope))
                    tasks.append(.expression(replacement, scope))
                case .caseExpr(let hasOtherwise):
                    let branches = stride(from: 0, to: expression.children.count - (hasOtherwise ? 1 : 0), by: 2).map { CompiledCaseBranch(condition: expression.children[$0], value: expression.children[$0 + 1]) }
                    let first = branches[0]
                    let remaining = Array(branches.dropFirst())
                    let otherwise = hasOtherwise ? expression.children.last : nil

                    tasks.append(.caseBranch([first] + remaining, index: 0, otherwise: otherwise, scope: scope))
                case .forAll(let binder):
                    let set = expression.children[0]
                    let predicate = expression.children[1]

                    tasks.append(.collectionStart(.forAll(binder), body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .exists(let binder):
                    let set = expression.children[0]
                    let predicate = expression.children[1]

                    tasks.append(.collectionStart(.exists(binder), body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .choose(let binder):
                    let set = expression.children[0]
                    let predicate = expression.children[1]

                    tasks.append(.collectionStart(.choose(binder), body: predicate, scope: scope))
                    tasks.append(.expression(set, scope))
                case .enabledAction(let action):
                    values.append(.boolean(enabledActions.contains(action)))
                case .foldFunction(let parameters):
                    let body = expression.children[0]
                    let initial = expression.children[1]
                    let sequence = expression.children[2]

                    tasks.append(.foldSequence(parameters: parameters, body: body, initial: initial, scope: scope))
                    tasks.append(.expression(sequence, scope))
                case .sequenceSelect(let binder):
                    let sequence = expression.children[0]
                    let predicate = expression.children[1]

                    tasks.append(.collectionStart(.sequenceSelect(binder), body: predicate, scope: scope))
                    tasks.append(.expression(sequence, scope))
                case .convert:
                    tasks.append(.expression(expression.children[0], scope))
                case .call(let call):
                    let target: EvaluatorFunctionBinding
                    switch call.target {
                    case .function(let id): target = .init(function: id, scope: scope)
                    case .callback(let id):
                        guard let callback = scope.callbacks[id] else {
                            throw CompiledEvaluationError.unresolvedOperator
                        }
                        target = callback
                    }
                    guard functions.indices.contains(target.function.ordinal) else {
                        throw CompiledEvaluationError.unresolvedOperator
                    }
                    let function = functions[target.function.ordinal]
                    guard function.parameters.count == expression.children.count else {
                        throw EvalError.invalidArity(.formalOperator,
                            expected: function.parameters.count, actual: expression.children.count)
                    }
                    try beginCall(tasks: &tasks, depth: &recursiveDepth)
                    var callScope = target.scope
                    for (parameter, argument) in zip(function.parameters, expression.children) {
                        callScope.bindings = callScope.bindings.binding(argument, from: scope,
                            to: parameter.binder, retainingIn: &pendingArguments)
                    }
                    for (parameter, actual) in call.callbacks {
                        switch actual {
                        case .function(let id):
                            callScope.callbacks[parameter] = .init(function: id, scope: scope)
                        case .callback(let id):
                            guard let callback = scope.callbacks[id] else {
                                throw CompiledEvaluationError.unresolvedOperator
                            }
                            callScope.callbacks[parameter] = callback
                        }
                    }
                    if let domain = function.domainGuard {
                        tasks.append(.localDomain(function.body, scope: callScope))
                        tasks.append(.expression(domain, callScope))
                    } else {
                        tasks.append(.expression(function.body, callScope))
                    }
                case .checkedCall:
                    throw CompiledEvaluationError.unresolvedOperator
                case .operatorApplication(let operation, let arguments):
                    tasks.append(.formalCall(
                        .init(operation: operation, scope: scope),
                        arguments: arguments,
                        argumentScope: scope
                    ))
                case .letValue(let binder):
                    let boundExpression = expression.children[0]
                    let body = expression.children[1]

                    var bodyScope = scope
                    bodyScope.bindings = bodyScope.bindings.binding(boundExpression, from: scope, to: binder, retainingIn: &pendingArguments)
                    tasks.append(.expression(body, bodyScope))
                case .letIn(_):
                    let body = expression.children[0]

                    tasks.append(.expression(body, scope))
                case .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .assertView, .negate, .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .not, .setLiteral, .in, .subset, .union, .intersection, .setDifference, .cardinality, .powerSet, .unionAll, .integerRange, .tupleLiteral, .tupleAccess, .tupleDynamicAccess, .tupleLength, .tupleAppend, .tupleHead, .tupleTail, .tupleConcatenate, .tupleRemoving, .recordLiteral, .recordAccess, .domain, .sequenceFromSet, .setSum, .functionSet:
                    schedule(expression.operation, expression.children)

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
    func beginCall(tasks: inout [EvaluatorTask], depth: inout Int) throws {
        guard depth < _NativeMachineOperations.maximumRecursiveDepth else {
            throw EvalError.recursionDepthExceeded(_NativeMachineOperations.maximumRecursiveDepth)
        }
        depth += 1
        tasks.append(.callReturn)
    }
}

/// Apply an eager operation to evaluated operands without syntax or scope state.
extension CompiledOperation {
    func apply(to values: inout [CompiledValue], operandCount: Int) throws {
        switch self {
        case .assertView(let shape):
            guard operandCount == 1, let value = values.last else {
                throw EvalError.invalidContinuation(availableValues: values.count)
            }
            guard shape.accepts(value) else { throw EvalError.noMatchingCase }
        case .convert:
            guard operandCount == 1, !values.isEmpty else {
                throw EvalError.invalidContinuation(availableValues: values.count)
            }
            // An implicit conversion changes Swift representation, not the formal value.
        case .add:
            let rhs = try integer(popValue(from: &values))
            let lhs = try integer(popValue(from: &values))
            values.append(.integer(try nativeOperation { try _NativeMachineOperations.add(lhs, rhs) }))
        case .subtract:
            let rhs = try integer(popValue(from: &values))
            let lhs = try integer(popValue(from: &values))
            values.append(.integer(try nativeOperation { try _NativeMachineOperations.subtract(lhs, rhs) }))
        case .multiply:
            let rhs = try integer(popValue(from: &values))
            let lhs = try integer(popValue(from: &values))
            values.append(.integer(try nativeOperation { try _NativeMachineOperations.multiply(lhs, rhs) }))
        case .divide, .integerDivide:
            let dividend = try integer(popValue(from: &values))
            let divisor = try integer(popValue(from: &values))
            values.append(.integer(try nativeOperation { try _NativeMachineOperations.divide(dividend, divisor) }))
        case .modulo:
            let dividend = try integer(popValue(from: &values))
            let divisor = try integer(popValue(from: &values))
            values.append(.integer(try nativeOperation { try _NativeMachineOperations.modulo(dividend, divisor) }))
        case .negate:
            let operand = try integer(popValue(from: &values))
            values.append(.integer(try nativeOperation { try _NativeMachineOperations.negate(operand) }))
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
        case .setLiteral:
            values.append(.set(Set(try popValues(operandCount, from: &values))))
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
            let subsets = try nativeOperation { try _NativeMachineOperations.powerSet(set) }
            values.append(.set(Set(subsets.map(CompiledValue.set))))
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
            let integers = try nativeOperation { try _NativeMachineOperations.integerRange(lower, upper) }
            values.append(.set(Set(integers.map(CompiledValue.integer))))
        case .tupleLiteral:
            values.append(.tuple(try popValues(operandCount, from: &values)))
        case .tupleAccess(let index):
            let tuple = try sequenceElements(from: popValue(from: &values))
            values.append(try nativeOperation { try _NativeMachineOperations.sequenceElement(tuple, at: index) })
        case .tupleDynamicAccess:
            let index = try integer(popValue(from: &values))
            let tuple = try sequenceElements(from: popValue(from: &values))
            values.append(try nativeOperation { try _NativeMachineOperations.sequenceElement(tuple, at: index) })
        case .tupleLength:
            values.append(.integer(try sequenceElements(from: popValue(from: &values)).count))
        case .tupleAppend:
            let element = try popValue(from: &values)
            var tuple = try sequenceElements(from: popValue(from: &values))
            tuple.append(element)
            values.append(.tuple(tuple))
        case .tupleHead:
            let sequence = try sequenceElements(from: popValue(from: &values))
            values.append(try nativeOperation { try _NativeMachineOperations.sequenceHead(sequence) })
        case .tupleTail:
            let tuple = try sequenceElements(from: popValue(from: &values))
            values.append(.tuple(try nativeOperation { try _NativeMachineOperations.sequenceTail(tuple) }))
        case .tupleConcatenate:
            let rhs = try sequenceElements(from: popValue(from: &values))
            let lhs = try sequenceElements(from: popValue(from: &values))
            values.append(.tuple(lhs + rhs))
        case .tupleRemoving:
            let index = try integer(popValue(from: &values))
            let tuple = try sequenceElements(from: popValue(from: &values))
            values.append(.tuple(try nativeOperation {
                try _NativeMachineOperations.sequenceRemoving(tuple, at: index)
            }))
        case .recordLiteral(let fields):
            let fieldValues = try popValues(fields.count, from: &values)
            values.append(.record(CompiledRecord(zip(fields, fieldValues).map {
                .init(key: .string($0.0), value: $0.1)
            })))
        case .recordAccess(let field):
            let recordValue = try popValue(from: &values)
            guard case .record(let record) = recordValue,
                  let value = record.value(for: .string(field))
            else {
                throw EvalError.expected(.recordField, actual: [recordValue])
            }
            values.append(value)
        case .domain:
            let value = try popValue(from: &values)
            switch value {
            case .function(let function): values.append(.set(_NativeMachineOperations.functionDomain(function)))
            case .record(let record): values.append(.set(Set(record.fields.map(\.key))))
            case .tuple(let tuple): values.append(.set(Set(_NativeMachineOperations.sequenceDomain(tuple).map(CompiledValue.integer))))
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
                guard case .integer(let index) = key else {
                    throw EvalError.tupleIndexOutsideDomain(key)
                }
                values.append(try nativeOperation {
                    try _NativeMachineOperations.sequenceFunctionValue(tuple, at: index)
                })
            case .record(let record):
                guard case .string = key, let value = record.value(for: key) else {
                    throw EvalError.recordFieldUnavailable(key)
                }
                values.append(value)
            default:
                throw EvalError.expected(.function, actual: [function])
            }
        case .except:
            let key = try popValue(from: &values)
            let function = try popValue(from: &values)
            let replacement = try popValue(from: &values)
            switch function {
            case .function(let function):
                values.append(.function(_NativeMachineOperations.functionUpdated(function, at: key, to: replacement)))
            case .tuple(let tuple):
                guard case .integer(let index) = key else {
                    throw EvalError.expected(.integer, actual: [key])
                }
                values.append(.tuple(_NativeMachineOperations.sequenceUpdated(tuple, at: index, to: replacement)))
            case .record(let record):
                guard case .string = key else {
                    throw EvalError.expected(.recordField, actual: [key])
                }
                values.append(.record(record.replacing(replacement, for: key)))
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
            values.append(.integer(try nativeOperation { try _NativeMachineOperations.sum(integers) }))
        case .functionSet:
            let range = try popValue(from: &values)
            let domain = try popValue(from: &values)
            guard case .set(let domainValues) = domain, case .set(let rangeValues) = range else {
                throw EvalError.expected(.functionSetDomains, actual: [domain, range])
            }
            let functions = try nativeOperation { try _NativeMachineOperations.functionSet(domainValues, rangeValues) }
            values.append(.set(Set(functions.map(CompiledValue.function))))
        default:
            throw EvalError.invalidContinuation(availableValues: values.count)
        }
    }
}

private func integer(_ value: CompiledValue) throws -> Int {
    guard case .integer(let integer) = value else {
        throw EvalError.expected(.integer, actual: [value])
    }
    return integer
}

private func boolean(_ value: CompiledValue) throws -> Bool {
    guard case .boolean(let boolean) = value else {
        throw EvalError.expected(.boolean, actual: [value])
    }
    return boolean
}

private func nativeOperation<Value>(_ operation: () throws -> Value) throws -> Value {
    do {
        return try operation()
    } catch NativeMachineEvaluationError.integerOverflow(let operation, let operands) {
        throw EvalError.integerOverflow(operation, operands: operands)
    } catch NativeMachineEvaluationError.divisionByZero {
        throw EvalError.divisionByZero
    } catch NativeMachineEvaluationError.negativeModuloDivisor(let divisor) {
        throw EvalError.negativeModuloDivisor(divisor)
    } catch NativeMachineEvaluationError.collectionCardinalityOverflow(let operation, let operands) {
        throw EvalError.collectionCardinalityOverflow(operation, operands: operands)
    } catch NativeMachineEvaluationError.powerSetTooLarge(let actualCount, let maximumCount) {
        throw EvalError.powerSetTooLarge(actualCount: actualCount, maximumCount: maximumCount)
    } catch NativeMachineEvaluationError.indexOutOfBounds(let index, let count) {
        throw EvalError.indexOutOfBounds(index, count)
    } catch NativeMachineEvaluationError.tupleIndexOutsideDomain(let index) {
        throw EvalError.tupleIndexOutsideDomain(.integer(index))
    } catch NativeMachineEvaluationError.emptySequence {
        throw EvalError.expected(.nonemptySequence, actual: [.tuple([])])
    }
}

private func popValue(from values: inout [CompiledValue]) throws -> CompiledValue {
    guard let value = values.popLast() else {
        throw EvalError.invalidContinuation(availableValues: 0)
    }
    return value
}

private func popValues(_ count: Int, from values: inout [CompiledValue]) throws -> [CompiledValue] {
    guard values.count >= count else {
        throw EvalError.invalidContinuation(availableValues: values.count)
    }
    let start = values.count - count
    let popped = Array(values[start...])
    values.removeSubrange(start...)
    return popped
}

private func sequenceElements(from value: CompiledValue) throws -> [CompiledValue] {
    switch value {
    case .tuple(let values):
        return values
    case .function(let values):
        let indexed = try values.reduce(into: [Int: CompiledValue]()) { result, entry in
            guard case .integer(let index) = entry.key else {
                throw EvalError.expected(.sequence, actual: [value])
            }
            result[index] = entry.value
        }
        do { return try _NativeMachineOperations.sequenceElements(indexed) }
        catch NativeMachineEvaluationError.invalidSequenceDomain {
            throw EvalError.expected(.sequence, actual: [value])
        }
    default:
        throw EvalError.expected(.sequence, actual: [value])
    }
}

package func evaluateClosed(_ expression: StateExpr) throws -> TLAValue {
    let compilation = try TLASpec(
        name: "ClosedExpression",
        variables: [],
        actions: [],
        invariants: [.init(name: "value", body: expression)]
    ).compile()
    let state = try CompiledState(values: [CompiledValue](), layout: compilation.layout, identity: compilation.identity)
    guard let invariant = compilation.semantics.behavior.invariants.first else {
        throw CompiledEvaluationError.unresolvedOperator
    }
    guard let value = try CompiledRuntime(compilation: compilation)
        .evaluate([invariant.predicate], in: state)
        .first else {
        throw CompiledEvaluationError.unresolvedOperator
    }
    return try value.rendered(using: compilation.layout)
}
