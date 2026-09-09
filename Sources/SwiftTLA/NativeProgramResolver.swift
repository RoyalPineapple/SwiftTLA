extension NativeResolvedProgram {
    package init(plan: NativeMachinePlan, sourceTypes: NativeSourceTypeMetadata = .init()) throws {
        self = try NativeProgramResolver(plan: plan, sourceTypes: sourceTypes).resolve()
    }
}

private struct NativeCallbackUseKey: Hashable {
    let operation: OperatorID
    let parameters: [NativeType]
    let result: NativeType
    init(_ operation: OperatorID, _ call: NativeOperatorCall) {
        self.operation = operation
        parameters = call.parameters.map { call.inference.bindings[$0] ?? .unknown }
        result = call.result
    }
}

private struct NativeResolvedFunctionKey: Hashable {
    let specialization: NativeOperatorSpecialization
    let capturedCallbacks: [NativeCallbackUseKey: NativeCallbackID]
}

/// Builds immutable occurrence annotations. All type decisions remain owned by
/// NativeTypeInference; code generation receives only this builder's result.
private final class NativeProgramResolver {
    let plan: NativeMachinePlan
    let inference: NativeTypeInference
    var expressions: [NativeResolvedExpression] = []
    var actions: [NativeResolvedAction] = []
    var functions: [NativeResolvedFunction?] = []
    var functionIDs: [NativeResolvedFunctionKey: NativeFunctionID] = [:]
    var functionCallbacks: [NativeFunctionID: [(OperatorID, NativeOperatorCall, NativeCallbackID)]] = [:]
    var callbacks: [NativeResolvedCallback] = []

    init(plan: NativeMachinePlan, sourceTypes: NativeSourceTypeMetadata) throws {
        self.plan = plan
        inference = try .init(plan: plan, sourceTypes: sourceTypes)
    }

    func resolve() throws -> NativeResolvedProgram {
        var initializations: [VariableID: NativeExpressionID] = [:]
        for item in plan.initializations {
            let expected = try require(inference.variables[item.variable])
            switch item.initialization {
            case .value(let value): initializations[item.variable] = try expression(.value(value), expected: expected)
            case .expression(let value): initializations[item.variable] = try expression(value, expected: expected)
            case .memberOf(let value): initializations[item.variable] = try expression(value, expected: .set(expected))
            }
        }
        var actionRoots: [ActionID: NativeActionNodeID] = [:]
        for item in plan.actions { actionRoots[item.id] = try action(item.body) }
        var invariantRoots: [PropertyID: NativeExpressionID] = [:]
        for item in plan.invariants { invariantRoots[item.id] = try expression(item.body, expected: .bool) }
        let constraint = try plan.constraint.map { try expression($0, expected: .bool) }
        let assume = try plan.assume.map { try expression($0, expected: .bool) }
        return .init(variableTypes: inference.variables, bindingTypes: inference.bindings,
            expressions: expressions, actionNodes: actions, functions: try functions.map { try require($0) }, callbacks: callbacks,
            initializations: initializations, actions: actionRoots, invariants: invariantRoots, constraint: constraint, assume: assume)
    }

    func require<Value>(_ value: Value?) throws -> Value {
        guard let value else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
                path: "native.resolution", expected: "complete native annotation", actual: "missing resolved evidence",
                nextSafeAction: "Resolve every expression and callback before generating Swift.")
        }
        return value
    }

    func action(_ value: CompiledActionExpr) throws -> NativeActionNodeID {
        var children: [NativeActionNodeID] = []
        var values: [NativeExpressionID] = []
        var bindings: [BinderID: NativeType] = [:]
        switch value {
        case .assign(let id, let rhs): values = [try expression(rhs, expected: require(inference.variables[id]))]
        case .unchanged: break
        case .guard_(let condition): values = [try expression(condition, expected: .bool)]
        case .existsAction(let id, let domain, let body):
            let type = try require(inference.bindings[id]); bindings[id] = type
            values = [try expression(domain, expected: .set(type))]; children = [try action(body)]
        case .define(let id, let rhs, let body):
            let type = try require(inference.bindings[id]); bindings[id] = type
            values = [try expression(rhs, expected: type)]; children = [try action(body)]
        case .ifElse(let condition, let yes, let no):
            values = [try expression(condition, expected: .bool)]; children = [try action(yes), try action(no)]
        case .and(let lhs, let rhs), .or(let lhs, let rhs): children = [try action(lhs), try action(rhs)]
        }
        let id = NativeActionNodeID(ordinal: actions.count)
        actions.append(.init(expression: value, expressions: values, children: children, bindings: bindings))
        return id
    }

    func expression(
        _ value: CompiledStateExpr, expected: NativeType? = nil,
        scope incoming: NativeTypeInference? = nil,
        callbackScope: [NativeCallbackUseKey: NativeCallbackID] = [:]
    ) throws -> NativeExpressionID {
        let (scope, output, result) = try (incoming ?? inference).resolutionScope(value, expected: expected)
        var computation = result
        var children: [NativeExpressionID] = []
        var bindings: [BinderID: NativeType] = [:]
        var call: NativeResolvedCall?
        func child(_ expression: CompiledStateExpr, _ type: NativeType? = nil) throws -> NativeExpressionID {
            try self.expression(expression, expected: type, scope: scope, callbackScope: callbackScope)
        }
        func type(_ expression: CompiledStateExpr) throws -> NativeType { try scope.type(of: expression) }
        func element(_ source: NativeType) throws -> NativeType {
            switch source {
            case .array(let item), .set(let item), .dictionary(.int, let item): return item
            default: return try require(nil as NativeType?)
            }
        }
        func pair(_ lhs: CompiledStateExpr, _ rhs: CompiledStateExpr, _ type: NativeType) throws {
            children = [try child(lhs, type), try child(rhs, type)]
        }
        switch value {
        case .value, .controlLocation, .enabledAction: break
        case .stateVariable(let id): computation = try require(scope.variables[id])
        case .boundValue(let id): computation = try require(scope.bindings[id])
        case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b), .divide(let a, let b), .modulo(let a, let b), .integerDivide(let a, let b), .lessThan(let a, let b), .lessOrEqual(let a, let b), .greaterThan(let a, let b), .greaterOrEqual(let a, let b): try pair(a, b, .int)
        case .negate(let a): children = [try child(a, .int)]
        case .and(let a, let b), .or(let a, let b): try pair(a, b, .bool)
        case .not(let a): children = [try child(a, .bool)]
        case .equal(let a, let b), .notEqual(let a, let b): try pair(a, b, scope.operandType(a, b))
        case .ifThenElse(let condition, let a, let b): children = [try child(condition, .bool), try child(a, result), try child(b, result)]
        case .setLiteral(let values): children = try values.map { try child($0, element(result)) }
        case .in(let value, let domain):
            let item = try scope.membershipElementType(value: value, domain: domain)
            children = [try child(value, item), try child(domain, .set(item))]
        case .subset(let a, let b): try pair(a, b, scope.operandType(a, b))
        case .union(let a, let b), .intersection(let a, let b), .setDifference(let a, let b): try pair(a, b, result)
        case .cardinality(let a): children = [try child(a)]
        case .sequenceSelect(let sequence, let id, let predicate):
            let item = try element(result)
            let source = try scope.sequenceSourceType(sequence, element: item)
            bindings[id] = item
            children = [try child(sequence, source), try child(predicate, .bool)]
        case .setFilter(let domain, let id, let body), .choose(let domain, let id, let body):
            let item: NativeType = if case .setFilter = value { try element(result) } else { result }
            bindings[id] = item
            children = [try child(domain, .set(item)), try child(body, .bool)]
        case .setMap(let body, let id, let domain):
            let item = try require(scope.bindings[id]); bindings[id] = item
            children = [try child(body, element(result)), try child(domain, .set(item))]
        case .forAll(let domain, let id, let body), .exists(let domain, let id, let body):
            let item = try require(scope.bindings[id]); bindings[id] = item
            children = [try child(domain, .set(item)), try child(body, .bool)]
        case .powerSet(let domain): children = [try child(domain, element(result))]
        case .unionAll(let domain): children = [try child(domain, .set(result))]
        case .integerRange(let a, let b): try pair(a, b, .int)
        case .tupleLiteral(let values):
            if case .tuple(let types) = result { children = try zip(values, types).map { try child($0, $1) } }
            else { children = try values.map { try child($0, element(result)) } }
        case .tupleAccess(let source, let index):
            let shape = try scope.projectionSourceType(source, index: index, expected: result)
            computation = if case .tuple(let fields) = shape { fields[index - 1] } else { try element(shape) }
            children = [try child(source, shape)]
        case .tupleDynamicAccess(let source, let index):
            let shape = try scope.sequenceSourceType(source, element: result)
            children = [try child(source, shape), try child(index, .int)]
        case .tupleLength(let source):
            let shape = try type(source)
            children = [try child(source, { if case .tuple = shape { return shape }; return try scope.sequenceSourceType(source) }())]
        case .tupleHead(let source): children = [try child(source, scope.sequenceSourceType(source, element: result))]
        case .tupleTail(let source): children = [try child(source, scope.sequenceSourceType(source, element: element(result)))]
        case .tupleRemoving(let source, let index):
            children = [try child(source, scope.sequenceSourceType(source, element: element(result))), try child(index, .int)]
        case .tupleAppend(let source, let item): children = [try child(source, scope.sequenceSourceType(source, element: element(result))), try child(item, element(result))]
        case .tupleConcatenate(let a, let b): children = [try child(a, scope.sequenceSourceType(a, element: element(result))), try child(b, scope.sequenceSourceType(b, element: element(result)))]
        case .recordLiteral(let record):
            guard case .record(let fields) = result else { return try require(nil as NativeExpressionID?) }
            children = try record.fields.map { field in
                guard case .string(let name) = field.key else { return try require(nil as NativeExpressionID?) }
                return try child(field.value, require(fields.first { $0.name == name }?.type))
            }
        case .recordAccess(let source, _, let key):
            let shape = try scope.recordProjectionSourceType(source, key: key, expected: result)
            guard case .record(let fields) = shape, case .string(let name) = key else { return try require(nil as NativeExpressionID?) }
            computation = try require(fields.first { $0.name == name }?.type)
            children = [try child(source, shape)]
        case .domain(let source): children = [try child(source, scope.domainSourceType(source, expected: result))]
        case .functionLiteral(let domain, let id, let body):
            guard case .dictionary(let key, let item) = result else { return try require(nil as NativeExpressionID?) }
            bindings[id] = key; children = [try child(domain, .set(key)), try child(body, item)]
        case .functionApply(let function, let argument):
            if case .operatorReference(let id) = function {
                let resolved = try scope.operatorCall(id, arguments: [.value(argument)], expected: result)
                call = try resolveCall(resolved, operation: id, values: [argument], scope: scope, callbackScope: callbackScope, arguments: &children)
            } else {
                let shape = try scope.functionApplicationSourceType(function, argument: argument, expected: result)
                let key: NativeType = switch shape { case .dictionary(let key, _): key; case .record: .string; default: .int }
                children = [try child(function, shape), try child(argument, key)]
            }
        case .except(let source, let key, let replacement):
            let shape = try type(source)
            let keyType: NativeType
            let item: NativeType
            switch shape {
            case .dictionary(let key, let value): keyType = key; item = value
            case .array(let value): keyType = .int; item = value
            case .record(let fields):
                keyType = .string
                if case .value(.string(let name)) = key { item = try fields.first { $0.name == name }?.type ?? type(replacement) }
                else { item = try require(fields.first?.type) }
            default: return try require(nil as NativeExpressionID?)
            }
            children = [try child(source, shape), try child(key, keyType), try child(replacement, item)]
        case .sequenceFromSet(let domain): children = [try child(domain, .set(element(result)))]
        case .setSum(let function, let domain): children = [try child(function), try child(domain)]
        case .functionSet(let domain, let range):
            guard case .set(.dictionary(let key, let item)) = result else { return try require(nil as NativeExpressionID?) }
            children = [try child(domain, .set(key)), try child(range, .set(item))]
        case .foldFunction(let operation, let initial, let sequence):
            let shape = try scope.sequenceSourceType(sequence)
            bindings[operation.parameters[0]] = try element(shape); bindings[operation.parameters[1]] = result
            children = [try child(operation.body, result), try child(initial, result), try child(sequence, shape)]
        case .operatorApplication(let id, let arguments):
            let resolved = try scope.operatorCall(id, arguments: arguments, expected: result)
            let values = arguments.compactMap { if case .value(let value) = $0 { return value }; return nil }
            call = try resolveCall(resolved, operation: id, values: values, scope: scope, callbackScope: callbackScope, arguments: &children)
        case .recursiveCall(let id, let values):
            let resolved = try scope.operatorCall(id, arguments: values.map { .value($0) }, expected: result)
            call = try resolveCall(resolved, operation: id, values: values, scope: scope, callbackScope: callbackScope, arguments: &children)
        case .lambdaApplication(let lambda, let values):
            let resolved = try scope.lambdaCall(lambda, arguments: values, expected: result)
            call = try resolveCall(resolved, operation: nil, values: values, scope: scope, callbackScope: callbackScope, arguments: &children)
        case .letValue(let id, let rhs, let body):
            let item = try require(scope.bindings[id]); bindings[id] = item
            children = [try child(rhs, item), try child(body, result)]
        case .letIn(_, let body): children = [try child(body, result)]
        case .caseExpr(let first, let rest, let otherwise):
            for branch in [first] + rest { children += [try child(branch.condition, .bool), try child(branch.value, result)] }
            if let otherwise { children.append(try child(otherwise, result)) }
        case .operatorReference: return try require(nil as NativeExpressionID?)
        }
        guard computation == output || scope.canProjectRead(computation, to: output) else { return try require(nil as NativeExpressionID?) }
        let id = NativeExpressionID(ordinal: expressions.count)
        expressions.append(.init(expression: value, resultType: output, computationType: computation, children: children, bindings: bindings, call: call))
        return id
    }

    func resolveCall(
        _ call: NativeOperatorCall, operation: OperatorID?, values: [CompiledStateExpr],
        scope: NativeTypeInference, callbackScope: [NativeCallbackUseKey: NativeCallbackID],
        arguments: inout [NativeExpressionID]
    ) throws -> NativeResolvedCall {
        arguments = try zip(values, call.parameters).map { value, parameter in
            try expression(value, expected: require(call.inference.bindings[parameter]), scope: scope, callbackScope: callbackScope)
        }
        if let operation, scope.isOperatorParameter(operation) {
            guard call.callbackArguments.isEmpty else {
                throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
                    path: "native.callback", expected: "a callback with value parameters",
                    actual: "operator-valued callback parameter", nextSafeAction: "Pass operator arguments to a named formal operator specialization.")
            }
            return .init(target: .callback(try require(callbackScope[.init(operation, call)])), callbacks: [])
        }
        let id = try function(call, callbackScope: callbackScope)
        var actuals: [NativeResolvedCallbackArgument] = []
        for (operation, use, parameter) in functionCallbacks[id] ?? [] {
            let actual = try require(call.callbackArguments[operation])
            let target: NativeResolvedCallTarget
            if case .reference(let origin, _) = actual, scope.isOperatorParameter(origin) {
                target = .callback(try require(callbackScope[.init(origin, use)]))
            } else {
                target = .function(try function(use, callbackScope: callbackScope))
            }
            actuals.append(.init(parameter: parameter, target: target))
        }
        return .init(target: .function(id), callbacks: actuals)
    }

    func function(_ call: NativeOperatorCall, callbackScope: [NativeCallbackUseKey: NativeCallbackID]) throws -> NativeFunctionID {
        var captures: [NativeCallbackUseKey: NativeCallbackID] = [:]
        for (operation, uses) in call.callbackUses where call.callbackArguments[operation] == nil {
            for use in uses {
                let key = NativeCallbackUseKey(operation, use)
                captures[key] = try require(callbackScope[key])
            }
        }
        let key = NativeResolvedFunctionKey(specialization: call.specialization, capturedCallbacks: captures)
        if let id = functionIDs[key] { return id }
        let id = NativeFunctionID(ordinal: functions.count)
        functionIDs[key] = id
        functions.append(nil)
        var nested = callbackScope
        var demands: [(OperatorID, NativeOperatorCall, NativeCallbackID)] = []
        for operation in call.callbackUses.keys.sorted(by: { $0.ordinal < $1.ordinal }) {
            guard call.callbackArguments[operation] != nil else { continue }
            for use in call.callbackUses[operation] ?? [] {
                let callback = NativeCallbackID(ordinal: callbacks.count)
                let types = try use.parameters.map { try require(use.inference.bindings[$0]) }
                callbacks.append(.init(parameters: types, result: use.result))
                nested[.init(operation, use)] = callback
                demands.append((operation, use, callback))
            }
        }
        functionCallbacks[id] = demands
        let body = try expression(call.body, expected: call.result, scope: call.inference, callbackScope: nested)
        let domainGuard: NativeExpressionID?
        if let domain = call.domain, let parameter = call.parameters.first {
            domainGuard = try expression(.in(.boundValue(parameter), domain), expected: .bool, scope: call.inference, callbackScope: nested)
        } else { domainGuard = nil }
        functions[id.ordinal] = .init(parameters: call.parameters,
            parameterTypes: try call.parameters.map { try require(call.inference.bindings[$0]) },
            resultType: call.result,
            callbacks: demands.map { $0.2 }, body: body, domainGuard: domainGuard)
        return id
    }
}
