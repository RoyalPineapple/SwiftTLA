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
        var checks: [NativeProjectionPair: Bool] = [:]
        for node in expressions {
            collectProjection(node.computationType, to: node.resultType, checks: &checks)
            if case .assertView = node.expression, let source = node.children.first {
                collectProjection(expressions[source.ordinal].resultType, to: node.computationType, checks: &checks)
            }
        }
        let projections = Set(checks.compactMap { pair, allowed in allowed ? pair : nil })
        return .init(projections: projections, variableTypes: inference.variables, bindingTypes: inference.bindings,
            expressions: expressions, actionNodes: actions, functions: try functions.map { try require($0) }, callbacks: callbacks,
            initializations: initializations, actions: actionRoots, invariants: invariantRoots, constraint: constraint, assume: assume)
    }

    /// Retain only conversions used by an expression or one of its components.
    /// Track failed checks too, so repeated checked views do not repeat them.
    func collectProjection(_ source: NativeType, to target: NativeType, checks: inout [NativeProjectionPair: Bool]) {
        guard source != target else { return }
        let pair = NativeProjectionPair(source: source, target: target)
        guard checks[pair] == nil else { return }
        checks[pair] = inference.canProjectRead(source, to: target)
        switch (source, target) {
        case (.union(let alternatives), _):
            for alternative in alternatives { collectProjection(alternative, to: target, checks: &checks) }
        case (_, .union(let alternatives)):
            for alternative in alternatives { collectProjection(source, to: alternative, checks: &checks) }
        case (.dictionary(let inputKey, let inputValue), .dictionary(let outputKey, let outputValue)):
            collectProjection(inputKey, to: outputKey, checks: &checks)
            collectProjection(inputValue, to: outputValue, checks: &checks)
        case (.set(let input), .set(let output)), (.array(let input), .array(let output)):
            collectProjection(input, to: output, checks: &checks)
        case (.tuple(let inputs), .tuple(let outputs)) where inputs.count == outputs.count:
            for (input, output) in zip(inputs, outputs) { collectProjection(input, to: output, checks: &checks) }
        case (.record(let inputs), .record(let outputs)) where inputs.map(\.name) == outputs.map(\.name):
            for (input, output) in zip(inputs, outputs) { collectProjection(input.type, to: output.type, checks: &checks) }
        default: break
        }
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
        let resolution = try (incoming ?? inference).resolutionScope(value, expected: expected)
        let scope = resolution.scope
        let resultType = resolution.resultType
        var computationType = resolution.computationType
        var children: [NativeExpressionID] = []
        var bindings: [BinderID: NativeType] = [:]
        var call: NativeResolvedCall?
        func child(_ expression: CompiledStateExpr, _ type: NativeType? = nil) throws -> NativeExpressionID {
            try self.expression(expression, expected: type, scope: scope, callbackScope: callbackScope)
        }
        func checkedChildren(_ values: [CompiledStateExpr]) throws -> [NativeExpressionID] {
            guard values.count == resolution.operandTypes.count else { return try require(nil) }
            return try zip(values, resolution.operandTypes).map { try child($0, $1) }
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
        case .assertView(let source, _): children = [try child(source)]
        case .stateVariable(let id): computationType = try require(scope.variables[id])
        case .boundValue(let id): computationType = try require(scope.bindings[id])
        case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b), .divide(let a, let b), .modulo(let a, let b), .integerDivide(let a, let b), .lessThan(let a, let b), .lessOrEqual(let a, let b), .greaterThan(let a, let b), .greaterOrEqual(let a, let b): try pair(a, b, .int)
        case .negate(let a): children = [try child(a, .int)]
        case .and(let a, let b), .or(let a, let b): try pair(a, b, .bool)
        case .not(let a): children = [try child(a, .bool)]
        case .equal(let a, let b), .notEqual(let a, let b), .subset(let a, let b), .in(let a, let b):
            children = try checkedChildren([a, b])
        case .ifThenElse(let condition, let a, let b): children = [try child(condition, .bool), try child(a, computationType), try child(b, computationType)]
        case .setLiteral(let values): children = try values.map { try child($0, element(computationType)) }
        case .union(let a, let b), .intersection(let a, let b), .setDifference(let a, let b): try pair(a, b, computationType)
        case .cardinality(let a): children = [try child(a)]
        case .sequenceSelect(let sequence, let id, let predicate):
            let item = try element(computationType)
            bindings[id] = item
            children = try checkedChildren([sequence, predicate])
        case .setFilter(let domain, let id, let body), .choose(let domain, let id, let body):
            let item: NativeType = if case .setFilter = value { try element(computationType) } else { computationType }
            bindings[id] = item
            children = [try child(domain, .set(item)), try child(body, .bool)]
        case .setMap(let body, let id, let domain):
            let item = try require(scope.bindings[id]); bindings[id] = item
            children = [try child(body, element(computationType)), try child(domain, .set(item))]
        case .forAll(let domain, let id, let body), .exists(let domain, let id, let body):
            let item = try require(scope.bindings[id]); bindings[id] = item
            children = [try child(domain, .set(item)), try child(body, .bool)]
        case .powerSet(let domain): children = [try child(domain, element(computationType))]
        case .unionAll(let domain): children = [try child(domain, .set(computationType))]
        case .integerRange(let a, let b): try pair(a, b, .int)
        case .tupleLiteral(let values):
            if case .tuple(let types) = computationType { children = try zip(values, types).map { try child($0, $1) } }
            else { children = try values.map { try child($0, element(computationType)) } }
        case .tupleAccess(let source, _), .tupleLength(let source), .tupleHead(let source), .tupleTail(let source),
             .recordAccess(let source, _, _), .domain(let source):
            children = try checkedChildren([source])
        case .tupleDynamicAccess(let source, let index), .tupleRemoving(let source, let index):
            children = try checkedChildren([source, index])
        case .tupleAppend(let source, let item), .tupleConcatenate(let source, let item):
            children = try checkedChildren([source, item])
        case .recordLiteral(let record):
            guard case .record(let fields) = computationType else { return try require(nil as NativeExpressionID?) }
            children = try record.fields.map { field in
                guard case .string(let name) = field.key else { return try require(nil as NativeExpressionID?) }
                return try child(field.value, require(fields.first { $0.name == name }?.type))
            }
        case .functionLiteral(let domain, let id, let body):
            guard case .dictionary(let key, let item) = computationType else { return try require(nil as NativeExpressionID?) }
            bindings[id] = key; children = [try child(domain, .set(key)), try child(body, item)]
        case .functionApply(let function, let argument):
            if case .operatorReference(let id) = function {
                let resolved = try require(resolution.call)
                call = try resolveCall(resolved, operation: id, values: [argument], scope: scope, callbackScope: callbackScope, arguments: &children)
            } else {
                children = try checkedChildren([function, argument])
            }
        case .except(let source, let key, let replacement):
            let sourceID = try child(source, computationType)
            let shape = expressions[sourceID.ordinal].resultType
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
            children = [sourceID, try child(key, keyType), try child(replacement, item)]
        case .sequenceFromSet(let domain): children = [try child(domain, .set(element(computationType)))]
        case .setSum(let function, let domain): children = [try child(function), try child(domain)]
        case .functionSet(let domain, let range):
            guard case .set(.dictionary(let key, let item)) = computationType else { return try require(nil as NativeExpressionID?) }
            children = [try child(domain, .set(key)), try child(range, .set(item))]
        case .foldFunction(let operation, let initial, let sequence):
            children = try checkedChildren([operation.body, initial, sequence])
            let source = expressions[children[2].ordinal].resultType
            bindings[operation.parameters[0]] = try element(source)
            bindings[operation.parameters[1]] = computationType
        case .operatorApplication(let id, let arguments):
            let resolved = try require(resolution.call)
            let values = arguments.compactMap { if case .value(let value) = $0 { return value }; return nil }
            call = try resolveCall(resolved, operation: id, values: values, scope: scope, callbackScope: callbackScope, arguments: &children)
        case .recursiveCall(let id, let values):
            let resolved = try require(resolution.call)
            call = try resolveCall(resolved, operation: id, values: values, scope: scope, callbackScope: callbackScope, arguments: &children)
        case .lambdaApplication(_, let values):
            let resolved = try require(resolution.call)
            call = try resolveCall(resolved, operation: nil, values: values, scope: scope, callbackScope: callbackScope, arguments: &children)
        case .letValue(let id, let rhs, let body):
            let item = try require(scope.bindings[id]); bindings[id] = item
            children = [try child(rhs, item), try child(body, computationType)]
        case .letIn(_, let body): children = [try child(body, computationType)]
        case .caseExpr(let first, let rest, let otherwise):
            for branch in [first] + rest { children += [try child(branch.condition, .bool), try child(branch.value, computationType)] }
            if let otherwise { children.append(try child(otherwise, computationType)) }
        case .operatorReference: return try require(nil as NativeExpressionID?)
        }
        guard computationType == resultType || scope.canProjectRead(computationType, to: resultType) else { return try require(nil as NativeExpressionID?) }
        let id = NativeExpressionID(ordinal: expressions.count)
        expressions.append(.init(expression: value, resultType: resultType, computationType: computationType, children: children, bindings: bindings, call: call))
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
