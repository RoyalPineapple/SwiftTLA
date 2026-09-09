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
        parameters = call.specialization.arguments
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
    var checkedRoots: ArraySlice<NativeCheckedExpression>
    var expressions: [NativeResolvedExpression] = []
    var functions: [NativeResolvedFunction?] = []
    var functionIDs: [NativeResolvedFunctionKey: NativeFunctionID] = [:]
    var functionCallbacks: [NativeFunctionID: [(OperatorID, NativeOperatorCall, NativeCallbackID)]] = [:]
    var callbacks: [NativeResolvedCallback] = []

    init(compilation: CompiledSpecification, sourceTypes: NativeSourceTypeMetadata) throws {
        self.compilation = compilation
        inference = try .init(compilation: compilation, sourceTypes: sourceTypes)
        checkedRoots = inference.checkedRoots[...]
    }

    func resolve() throws -> NativeResolvedProgram {
        var initializations: [VariableID: NativeExpressionID] = [:]
        for item in compilation.semantics.variableInitializations {
            initializations[item.variable] = try nextExpression()
        }
        var actionRoots: [ActionID: CompiledActionExpr<NativeExpressionID>] = [:]
        for item in compilation.semantics.actions { actionRoots[item.id] = try item.body.map { _ in try nextExpression() } }
        var invariantRoots: [PropertyID: NativeExpressionID] = [:]
        for item in compilation.semantics.invariants { invariantRoots[item.id] = try nextExpression() }
        let constraint = try compilation.semantics.constraint.map { _ in try nextExpression() }
        let assume = try compilation.semantics.assume.map { _ in try nextExpression() }
        guard checkedRoots.isEmpty else {
            throw NativeTypeInference.diagnostic("resolution", "unconsumed checked roots")
        }
        var checks: [NativeProjectionPair: Bool] = [:]
        for node in expressions {
            collectProjection(node.computationType, to: node.resultType, checks: &checks)
            if case .assertView = node.expression, let source = node.children.first {
                collectProjection(expressions[source.ordinal].resultType, to: node.computationType, checks: &checks)
            }
        }
        let projections = Set(checks.compactMap { pair, allowed in allowed ? pair : nil })
        return .init(projections: projections, variableTypes: inference.variables, bindingTypes: inference.bindings,
            expressions: expressions, functions: try functions.map { try require($0) }, callbacks: callbacks,
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

    /// Consume roots in the shared program's initialization/action/predicate order.
    func nextExpression() throws -> NativeExpressionID {
        let checked = try require(checkedRoots.popFirst())
        for type in [checked.resultType, checked.computationType] where !type.resolved {
            throw NativeTypeInference.unresolvedDiagnostic(type, at: "resolution")
        }
        return try expression(checked, callbackScope: [:])
    }

    func expression(
        _ checked: NativeCheckedExpression,
        callbackScope: [NativeCallbackUseKey: NativeCallbackID]
    ) throws -> NativeExpressionID {
        let value = checked.expression
        let call: NativeResolvedCall?
        if let resolved = checked.call {
            let operation: OperatorID?
            switch value {
            case .operatorApplication(let id, _), .recursiveCall(let id, _), .functionApply(.operatorReference(let id), _): operation = id
            default: operation = nil
            }
            guard checked.children.count == resolved.parameters.count else { return try require(nil) }
            call = try resolveCall(resolved, operation: operation, operatorParameters: checked.operatorParameters, callbackScope: callbackScope)
        } else {
            call = nil
        }
        let children = try checked.children.map { try expression($0, callbackScope: callbackScope) }
        let id = NativeExpressionID(ordinal: expressions.count)
        expressions.append(.init(expression: value, resultType: checked.resultType,
            computationType: checked.computationType, children: children, call: call))
        return id
    }

    func resolveCall(
        _ call: NativeOperatorCall, operation: OperatorID?,
        operatorParameters: Set<OperatorID>, callbackScope: [NativeCallbackUseKey: NativeCallbackID]
    ) throws -> NativeResolvedCall {
        if let operation, operatorParameters.contains(operation) {
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
            if case .reference(let origin, _) = actual, operatorParameters.contains(origin) {
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
                callbacks.append(.init(parameters: use.specialization.arguments, result: use.result))
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
            parameterTypes: call.specialization.arguments,
            resultType: call.result,
            callbacks: demands.map { $0.2 }, body: body, domainGuard: domainGuard)
        return id
    }
}
