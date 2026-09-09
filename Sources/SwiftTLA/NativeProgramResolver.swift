extension NativeResolvedProgram {
    package init(compilation: CompiledSpecification, sourceTypes: NativeSourceTypeMetadata = .init()) throws {
        self = try NativeProgramResolver(compilation: compilation, sourceTypes: sourceTypes).resolve()
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
    let compilation: CompiledSpecification
    let inference: NativeTypeInference
    var expressions: [NativeResolvedExpression] = []
    var actions: [NativeResolvedAction] = []
    var functions: [NativeResolvedFunction?] = []
    var functionIDs: [NativeResolvedFunctionKey: NativeFunctionID] = [:]
    var functionCallbacks: [NativeFunctionID: [(OperatorID, NativeOperatorCall, NativeCallbackID)]] = [:]
    var callbacks: [NativeResolvedCallback] = []

    init(compilation: CompiledSpecification, sourceTypes: NativeSourceTypeMetadata) throws {
        self.compilation = compilation
        inference = try .init(compilation: compilation, sourceTypes: sourceTypes)
    }

    func resolve() throws -> NativeResolvedProgram {
        var initializations: [VariableID: NativeExpressionID] = [:]
        for item in compilation.semantics.variableInitializations {
            let expected = try require(inference.variables[item.variable])
            switch item.initialization {
            case .value(let value): initializations[item.variable] = try expression(.value(value), expected: expected)
            case .expression(let value): initializations[item.variable] = try expression(value, expected: expected)
            case .memberOf(let value): initializations[item.variable] = try expression(value, expected: .set(expected))
            }
        }
        var actionRoots: [ActionID: NativeActionNodeID] = [:]
        for item in compilation.semantics.actions { actionRoots[item.id] = try action(item.body) }
        var invariantRoots: [PropertyID: NativeExpressionID] = [:]
        for item in compilation.semantics.invariants { invariantRoots[item.id] = try expression(item.body, expected: .bool) }
        let constraint = try compilation.semantics.constraint.map { try expression($0, expected: .bool) }
        let assume = try compilation.semantics.assume.map { try expression($0, expected: .bool) }
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
        callbackScope: [NativeCallbackUseKey: NativeCallbackID] = [:]
    ) throws -> NativeExpressionID {
        let checked = try inference.resolutionScope(value, expected: expected)
        return try expression(checked, callbackScope: callbackScope)
    }

    func expression(
        _ checked: NativeCheckedExpression,
        callbackScope: [NativeCallbackUseKey: NativeCallbackID]
    ) throws -> NativeExpressionID {
        let value = checked.expression
        var bindings: [BinderID: NativeType] = [:]
        switch value {
        case .setFilter(_, let id, _), .choose(_, let id, _), .setMap(_, let id, _),
             .forAll(_, let id, _), .exists(_, let id, _), .sequenceSelect(_, let id, _),
             .letValue(let id, _, _):
            bindings[id] = try require(checked.scope.bindings[id])
        case .functionLiteral(_, let id, _):
            guard case .dictionary(let key, _) = checked.computationType else { return try require(nil) }
            bindings[id] = key
        case .foldFunction(let operation, _, _):
            let source = try require(checked.children.last).resultType
            switch source {
            case .array(let item), .dictionary(.int, let item): bindings[operation.parameters[0]] = item
            default: return try require(nil)
            }
            bindings[operation.parameters[1]] = checked.computationType
        default: break
        }
        let call: NativeResolvedCall?
        if let resolved = checked.call {
            let operation: OperatorID?
            switch value {
            case .operatorApplication(let id, _), .recursiveCall(let id, _), .functionApply(.operatorReference(let id), _): operation = id
            default: operation = nil
            }
            guard checked.children.count == resolved.parameters.count else { return try require(nil) }
            call = try resolveCall(resolved, operation: operation, scope: checked.scope, callbackScope: callbackScope)
        } else {
            guard checked.children.count == checked.operandTypes.count else { return try require(nil) }
            call = nil
        }
        let children = try checked.children.map { try expression($0, callbackScope: callbackScope) }
        let id = NativeExpressionID(ordinal: expressions.count)
        expressions.append(.init(expression: value, resultType: checked.resultType,
            computationType: checked.computationType, children: children, bindings: bindings, call: call))
        return id
    }

    func resolveCall(
        _ call: NativeOperatorCall, operation: OperatorID?,
        scope: NativeTypeInference, callbackScope: [NativeCallbackUseKey: NativeCallbackID]
    ) throws -> NativeResolvedCall {
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
        let specialization = NativeOperatorSpecialization(
            operation: call.specialization.operation,
            arguments: try call.parameters.map { try require(call.inference.bindings[$0]) },
            resultContext: call.result,
            captures: call.specialization.captures,
            callbacks: call.specialization.callbacks)
        let key = NativeResolvedFunctionKey(specialization: specialization, capturedCallbacks: captures)
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
        guard case .checked(let checkedBody, let checkedGuard) = call.implementation else {
            return try require(nil)
        }
        let body = try expression(checkedBody, callbackScope: nested)
        let domainGuard = try checkedGuard.map { try expression($0, callbackScope: nested) }
        functions[id.ordinal] = .init(parameters: call.parameters,
            parameterTypes: try call.parameters.map { try require(call.inference.bindings[$0]) },
            resultType: call.result,
            callbacks: demands.map { $0.2 }, body: body, domainGuard: domainGuard)
        return id
    }
}
