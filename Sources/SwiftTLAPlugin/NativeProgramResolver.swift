import SwiftTLA
extension NativeResolvedProgram {
    init(compilation: CompiledSpecification, sourceTypes: NativeSourceTypeMetadata = .init()) throws {
        self = try NativeProgramResolver(inference: .init(compilation: compilation, sourceTypes: sourceTypes)).resolve()
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

/// Links specialized functions and callbacks without copying checked expressions.
private final class NativeProgramResolver {
    let inference: NativeTypeInference
    var expressions: [NativeCheckedExpression] = []
    var retainedExpressions: Set<NativeCheckedExpression> = []
    var visited: Set<NativeCallSite> = []
    var calls: [NativeCallSite: NativeResolvedCall] = [:]
    var functions: [NativeResolvedFunction?] = []
    var functionIDs: [NativeResolvedFunctionKey: NativeFunctionID] = [:]
    var functionCallbacks: [NativeFunctionID: [(OperatorID, NativeOperatorCall, NativeCallbackID)]] = [:]
    var callbacks: [NativeResolvedCallback] = []

    init(inference: NativeTypeInference) {
        self.inference = inference
    }

    func resolve() throws -> NativeResolvedProgram {
        let initializations = try Dictionary(uniqueKeysWithValues: inference.initializations.map {
            ($0.variable, try root($0.expression))
        })
        let actionRoots = try Dictionary(uniqueKeysWithValues: inference.actions.map {
            ($0.id, try $0.body.map(root))
        })
        let invariantRoots = try Dictionary(uniqueKeysWithValues: inference.invariants.map {
            ($0.id, try root($0.expression))
        })
        let constraint = try inference.constraint.map(root)
        let assume = try inference.assume.map(root)
        var checks: [NativeProjectionPair: Bool] = [:]
        for node in expressions {
            collectProjection(node.computationType, to: node.resultType, checks: &checks)
            if case .assertView = node.expression, let source = node.children.first {
                collectProjection(source.resultType, to: node.computationType, checks: &checks)
            }
        }
        let projections = Set(checks.compactMap { pair, allowed in allowed ? pair : nil })
        return .init(projections: projections, variableTypes: inference.variables, bindingTypes: inference.bindings,
            expressions: expressions, calls: calls, functions: try functions.map { try require($0) }, callbacks: callbacks,
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

    func root(_ checked: NativeCheckedExpression) throws -> NativeCheckedExpression {
        for type in [checked.resultType, checked.computationType] where !type.resolved {
            throw NativeTypeInference.unresolvedDiagnostic(type, at: "resolution")
        }
        return try expression(checked, function: nil, callbackScope: [:])
    }

    func expression(
        _ checked: NativeCheckedExpression, function: NativeFunctionID?,
        callbackScope: [NativeCallbackUseKey: NativeCallbackID]
    ) throws -> NativeCheckedExpression {
        let site = NativeCallSite(expression: checked, function: function)
        guard visited.insert(site).inserted else { return checked }
        let value = checked.expression
        if let resolved = checked.call {
            let operation: OperatorID?
            switch value {
            case .operatorApplication(let id, _), .recursiveCall(let id, _), .functionApply(.operatorReference(let id), _): operation = id
            default: operation = nil
            }
            guard checked.children.count == resolved.parameters.count else { return try require(nil) }
            calls[site] = try resolveCall(resolved, operation: operation, operatorParameters: checked.operatorParameters, callbackScope: callbackScope)
        }
        for child in checked.children {
            _ = try expression(child, function: function, callbackScope: callbackScope)
        }
        if retainedExpressions.insert(checked).inserted { expressions.append(checked) }
        return checked
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
        let body = try expression(checkedBody, function: id, callbackScope: nested)
        let domainGuard = try checkedGuard.map { try expression($0, function: id, callbackScope: nested) }
        functions[id.ordinal] = .init(parameters: call.parameters,
            parameterTypes: call.specialization.arguments,
            resultType: call.result,
            callbacks: demands.map { $0.2 }, body: body, domainGuard: domainGuard)
        return id
    }
}
