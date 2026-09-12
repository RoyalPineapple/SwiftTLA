extension CompiledProgram {
    package init(inputs: CompiledTypeInputs) throws {
        var checker = try CompiledTypeChecker(inputs: inputs)
        self = try ProgramResolver(checked: checker.checkProgram(), types: inputs.types).resolve()
    }
}

private struct CallbackUseKey: Hashable {
    let operation: OperatorID
    let parameters: [CompiledValueType]
    let result: CompiledValueType
    init(_ operation: OperatorID, _ call: CheckedOperatorCall) {
        self.operation = operation
        parameters = call.parameters.map(\.type)
        result = call.result
    }
}

private struct ResolvedFunctionKey: Hashable {
    let specialization: CheckedOperatorSpecialization
    let capturedCallbacks: [CallbackUseKey: ResolvedCallbackID]
}

private struct CheckedCallSite: Hashable {
    let expression: CompiledExpression
    let function: ResolvedFunctionID?
}

/// Consumes checking annotations and retains only resolved calls for generation.
private final class ProgramResolver {
    let checked: CompiledProgram
    let types: CompiledTypeContext
    var projectionChecks: [ResolvedProjectionPair: Bool] = [:]
    var resolvedExpressions: [CheckedCallSite: CompiledExpression] = [:]
    var functions: [ResolvedFunction?] = []
    var functionIDs: [ResolvedFunctionKey: ResolvedFunctionID] = [:]
    var functionCallbacks: [ResolvedFunctionID: [(OperatorID, CheckedOperatorCall, ResolvedCallbackID)]] = [:]
    var callbacks: [ResolvedCallback] = []

    init(checked: CompiledProgram, types: CompiledTypeContext) {
        self.checked = checked
        self.types = types
    }

    func resolve() throws -> CompiledProgram {
        let behavior = try checked.behavior.map(root)
        let projections = Set(projectionChecks.compactMap { pair, allowed in allowed ? pair : nil })
        let resolvedFunctions = try functions.map { try require($0) }
        for (index, function) in resolvedFunctions.enumerated() {
            for (offset, parameter) in function.parameters.enumerated() where !parameter.type.resolved {
                throw CompiledValueType.unresolvedDiagnostic(parameter.type, at: "function[\(index)].parameter[\(offset)]")
            }
            guard function.resultType.resolved else {
                throw CompiledValueType.unresolvedDiagnostic(function.resultType, at: "function[\(index)].result")
            }
        }
        return .init(identity: checked.identity, layout: checked.layout,
            behavior: behavior, enums: checked.enums,
            projections: projections, variableTypes: checked.variableTypes, bindingTypes: checked.bindingTypes,
            functions: resolvedFunctions, callbacks: callbacks)
    }

    func require<Value>(_ value: Value?) throws -> Value {
        guard let value else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
                path: "native.resolution", expected: "complete native annotation", actual: "missing resolved evidence",
                nextSafeAction: "Resolve every expression and callback before generating Swift.")
        }
        return value
    }

    func root(_ checked: CompiledExpression) throws -> CompiledExpression {
        try expression(checked, function: nil, callbackScope: [:])
    }

    func expression(
        _ checked: CompiledExpression, function: ResolvedFunctionID?,
        callbackScope: [CallbackUseKey: ResolvedCallbackID]
    ) throws -> CompiledExpression {
        var pending: [(expression: CompiledExpression, call: ResolvedCall?, expanded: Bool)] = [
            (checked, nil, false)
        ]
        while let task = pending.popLast() {
            let node = task.expression
            let site = CheckedCallSite(expression: node, function: function)
            if resolvedExpressions[site] != nil { continue }
            if task.expanded {
                let children = try node.children.map {
                    try require(resolvedExpressions[.init(expression: $0, function: function)])
                }
                if case .letIn = node.operation {
                    guard children.count == 1, let body = children.first,
                          body.resultType == node.resultType else {
                        throw CompiledValueType.diagnostic("resolution.scope", "local declarations must preserve their body's result type")
                    }
                    resolvedExpressions[site] = body
                    continue
                }
                let operation = task.call.map(CompiledOperation.call) ?? node.operation
                if case .assertView = operation, let source = children.first {
                    _ = types.canProjectRead(source.resultType, to: node.resultType, checks: &projectionChecks)
                }
                if case .convert = operation, let source = children.first {
                    guard types.canProjectRead(source.resultType, to: node.resultType, checks: &projectionChecks) else {
                        throw CompiledValueType.diagnostic("conversion", "the checked expression requires an unsupported conversion")
                    }
                }
                resolvedExpressions[site] = .init(operation: operation, resultType: node.resultType, children: children)
                continue
            }
            for type in [node.resultType, node.computationType] where !type.resolved {
                throw CompiledValueType.unresolvedDiagnostic(type, at: "expression.\(node.operation.diagnosticName)")
            }
            let call: ResolvedCall?
            if case .checkedCall(let annotation, let origin, let operatorParameters) = node.operation {
                guard node.children.count == annotation.parameters.count else { return try require(nil) }
                call = try resolveCall(annotation, operation: origin,
                    operatorParameters: operatorParameters, callbackScope: callbackScope)
            } else { call = nil }
            pending.append((node, call, true))
            pending.append(contentsOf: node.children.reversed().map { ($0, nil, false) })
        }
        return try require(resolvedExpressions[.init(expression: checked, function: function)])
    }

    func resolveCall(
        _ call: CheckedOperatorCall, operation: OperatorID?,
        operatorParameters: Set<OperatorID>, callbackScope: [CallbackUseKey: ResolvedCallbackID]
    ) throws -> ResolvedCall {
        if let operation, operatorParameters.contains(operation) {
            guard call.callbackArguments.isEmpty else {
                throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
                    path: "native.callback", expected: "a callback with value parameters",
                    actual: "operator-valued callback parameter", nextSafeAction: "Pass operator arguments to a named formal operator specialization.")
            }
            return .init(target: .callback(try require(callbackScope[.init(operation, call)])), callbacks: [])
        }
        let id = try function(call, callbackScope: callbackScope)
        var actuals: [ResolvedCallbackArgument] = []
        for (operation, use, parameter) in functionCallbacks[id] ?? [] {
            let actual = try require(call.callbackArguments[operation])
            let target: ResolvedCallTarget
            if case .reference(let origin, _) = actual, operatorParameters.contains(origin) {
                target = .callback(try require(callbackScope[.init(origin, use)]))
            } else {
                target = .function(try function(use, callbackScope: callbackScope))
            }
            actuals.append(.init(parameter: parameter, target: target))
        }
        return .init(target: .function(id), callbacks: actuals)
    }

    func function(_ call: CheckedOperatorCall, callbackScope: [CallbackUseKey: ResolvedCallbackID]) throws -> ResolvedFunctionID {
        var captures: [CallbackUseKey: ResolvedCallbackID] = [:]
        for (operation, uses) in call.callbackUses where call.callbackArguments[operation] == nil {
            for use in uses {
                let key = CallbackUseKey(operation, use)
                captures[key] = try require(callbackScope[key])
            }
        }
        let key = ResolvedFunctionKey(specialization: call.specialization, capturedCallbacks: captures)
        if let id = functionIDs[key] { return id }
        let id = ResolvedFunctionID(ordinal: functions.count)
        functionIDs[key] = id
        functions.append(nil)
        var nested = callbackScope
        var demands: [(OperatorID, CheckedOperatorCall, ResolvedCallbackID)] = []
        for operation in call.callbackUses.keys.sorted(by: { $0.ordinal < $1.ordinal }) {
            guard call.callbackArguments[operation] != nil else { continue }
            for use in call.callbackUses[operation] ?? [] {
                let callback = ResolvedCallbackID(ordinal: callbacks.count)
                callbacks.append(.init(parameters: use.parameters.map(\.type), result: use.result))
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
            resultType: call.result,
            callbacks: demands.map { $0.2 }, body: body, domainGuard: domainGuard)
        return id
    }
}
