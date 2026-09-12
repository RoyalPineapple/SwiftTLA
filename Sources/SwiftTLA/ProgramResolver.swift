extension CompiledProgram {
    package init(inputs: CompiledTypeInputs) throws {
        var checker = try CompiledTypeChecker(inputs: inputs)
        self = try ProgramResolver(checked: checker.checkProgram(), types: inputs.types,
            nextBinder: (inputs.bindings.binders.keys.map(\.ordinal).max() ?? -1) + 1).resolve()
    }
}

/// A capture path distinguishes a callback's closed-over value from a same-named
/// parameter in the function forwarding that callback.
private struct CaptureKey: Hashable {
    var callbacks: [OperatorID]
    let binder: BinderID
}

private struct CaptureParameter {
    let key: CaptureKey
    let binder: BinderID
    let type: CompiledValueType
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
    var functionIDs: [CheckedOperatorSpecialization: ResolvedFunctionID] = [:]
    var functionCaptures: [[CaptureParameter]] = []
    var nextBinder: Int

    init(checked: CompiledProgram, types: CompiledTypeContext, nextBinder: Int) {
        self.nextBinder = nextBinder
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
            functions: resolvedFunctions)
    }

    func require<Value>(_ value: Value?) throws -> Value {
        guard let value else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
                path: "native.resolution", expected: "complete native annotation", actual: "missing resolved types and bindings",
                nextSafeAction: "Resolve every expression and callback before generating Swift.")
        }
        return value
    }

    func root(_ checked: CompiledExpression) throws -> CompiledExpression {
        try expression(checked, function: nil, captures: [:])
    }

    func expression(
        _ checked: CompiledExpression, function: ResolvedFunctionID?,
        captures: [CaptureKey: BinderID]
    ) throws -> CompiledExpression {
        var pending: [(expression: CompiledExpression, call: ResolvedFunctionID?, expanded: Bool)] = [
            (checked, nil, false)
        ]
        while let task = pending.popLast() {
            let node = task.expression
            let site = CheckedCallSite(expression: node, function: function)
            if resolvedExpressions[site] != nil { continue }
            if task.expanded {
                var children = try node.children.map {
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
                var operation = task.call.map(CompiledOperation.call) ?? node.operation
                if let target = task.call,
                   case .checkedCall(let call, let origin, let operatorParameters) = node.operation {
                    children += try captureArguments(for: target, call: call, origin: origin,
                        operatorParameters: operatorParameters, captures: captures)
                }
                if case .boundValue(let binder) = operation,
                   let parameter = captures[.init(callbacks: [], binder: binder)] {
                    operation = .boundValue(parameter)
                }
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
            let call: ResolvedFunctionID?
            if case .checkedCall(let annotation, let origin, let operatorParameters) = node.operation {
                guard node.children.count == annotation.parameters.count else { return try require(nil) }
                if let origin, operatorParameters.contains(origin), !annotation.callbackArguments.isEmpty {
                    throw CompiledValueType.diagnostic("callback", "operator-valued callback parameters are unsupported")
                }
                call = try self.function(annotation)
            } else { call = nil }
            pending.append((node, call, true))
            pending.append(contentsOf: node.children.reversed().map { ($0, nil, false) })
        }
        return try require(resolvedExpressions[.init(expression: checked, function: function)])
    }

    private func captureArguments(
        for target: ResolvedFunctionID, call: CheckedOperatorCall, origin: OperatorID?,
        operatorParameters: Set<OperatorID>, captures: [CaptureKey: BinderID]
    ) throws -> [CompiledExpression] {
        try functionCaptures[target.ordinal].map { capture in
            var key = capture.key
            if let origin, operatorParameters.contains(origin) {
                key.callbacks.insert(origin, at: 0)
            } else if let parameter = key.callbacks.first, let actual = call.callbackArguments[parameter] {
                key.callbacks.removeFirst()
                if case .reference(let origin, _) = actual, operatorParameters.contains(origin) {
                    key.callbacks.insert(origin, at: 0)
                }
            }
            let binder = try captures[key] ?? require(key.callbacks.isEmpty ? key.binder : nil)
            return .init(operation: .boundValue(binder), resultType: capture.type, children: [])
        }
    }

    private func captureParameters(_ call: CheckedOperatorCall) -> [CaptureParameter] {
        var captures = call.specialization.captures.sorted { $0.key.ordinal < $1.key.ordinal }.map {
            (CaptureKey(callbacks: [], binder: $0.key), $0.value)
        }
        var pending = call.specialization.callbacks.sorted { $0.key.ordinal > $1.key.ordinal }.map {
            ([$0.key], $0.value)
        }
        while let (path, callback) = pending.popLast() {
            captures += callback.captures.sorted { $0.key.ordinal < $1.key.ordinal }.map {
                (CaptureKey(callbacks: path, binder: $0.key), $0.value)
            }
            pending += callback.callbacks.sorted { $0.key.ordinal > $1.key.ordinal }.map {
                (path + [$0.key], $0.value)
            }
        }
        return captures.map { key, type in
            defer { nextBinder += 1 }
            return .init(key: key, binder: .init(ordinal: nextBinder), type: type)
        }
    }

    func function(_ call: CheckedOperatorCall) throws -> ResolvedFunctionID {
        let key = call.specialization
        if let id = functionIDs[key] { return id }
        let id = ResolvedFunctionID(ordinal: functions.count)
        functionIDs[key] = id
        functions.append(nil)
        let parameters = captureParameters(call)
        functionCaptures.append(parameters)
        let captures = Dictionary(uniqueKeysWithValues: parameters.map { ($0.key, $0.binder) })
        guard case .checked(let checkedBody, let checkedGuard) = call.implementation else {
            return try require(nil)
        }
        let body = try expression(checkedBody, function: id, captures: captures)
        let domainGuard = try checkedGuard.map { try expression($0, function: id, captures: captures) }
        functions[id.ordinal] = .init(parameters: call.parameters + parameters.map { ($0.binder, $0.type) },
            resultType: call.result, body: body, domainGuard: domainGuard)
        return id
    }
}
