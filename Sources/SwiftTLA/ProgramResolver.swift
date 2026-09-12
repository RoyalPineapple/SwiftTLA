extension ResolvedProgram {
    package init(inputs: CompiledTypeInputs) throws {
        self = try ProgramResolver(checked: CheckedProgram(inputs: inputs)).resolve()
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
    let expression: CheckedExpression
    let function: ResolvedFunctionID?
}

/// Consumes checking annotations and retains only resolved calls for generation.
private final class ProgramResolver {
    let checked: CheckedProgram
    var projectionChecks: [ResolvedProjectionPair: Bool] = [:]
    var resolvedExpressions: [CheckedCallSite: ResolvedExpression] = [:]
    var functions: [ResolvedFunction?] = []
    var functionIDs: [ResolvedFunctionKey: ResolvedFunctionID] = [:]
    var functionCallbacks: [ResolvedFunctionID: [(OperatorID, CheckedOperatorCall, ResolvedCallbackID)]] = [:]
    var callbacks: [ResolvedCallback] = []

    init(checked: CheckedProgram) {
        self.checked = checked
    }

    func resolve() throws -> ResolvedProgram {
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
            behavior: behavior, enums: checked.types.enums,
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

    func root(_ checked: CheckedExpression) throws -> ResolvedExpression {
        try expression(checked, function: nil, callbackScope: [:])
    }

    func expression(
        _ checked: CheckedExpression, function: ResolvedFunctionID?,
        callbackScope: [CallbackUseKey: ResolvedCallbackID]
    ) throws -> ResolvedExpression {
        var pending: [(expression: CheckedExpression, call: ResolvedCall?, expanded: Bool)] = [
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
                if case .letIn = node.expression {
                    guard children.count == 1, let body = children.first,
                          body.resultType == node.resultType else {
                        throw CompiledValueType.diagnostic("resolution.scope", "local declarations must preserve their body's result type")
                    }
                    resolvedExpressions[site] = body
                    continue
                }
                let computation = ResolvedExpression(operation: try ResolvedOperation(node.expression, call: task.call),
                    resultType: node.computationType, children: children)
                if case .assertView = computation.operation, let source = children.first {
                    _ = self.checked.types.canProjectRead(source.resultType, to: computation.resultType, checks: &projectionChecks)
                }
                let resolved: ResolvedExpression
                if node.resultType == computation.resultType {
                    resolved = computation
                } else {
                    guard self.checked.types.canProjectRead(computation.resultType, to: node.resultType, checks: &projectionChecks) else {
                        throw CompiledValueType.diagnostic("conversion", "the checked expression requires an unsupported conversion")
                    }
                    resolved = .init(operation: .convert, resultType: node.resultType, children: [computation])
                }
                resolvedExpressions[site] = resolved
                continue
            }
            for type in [node.resultType, node.computationType] where !type.resolved {
                throw CompiledValueType.unresolvedDiagnostic(type, at: "expression.\(node.expression.diagnosticName)")
            }
            let call: ResolvedCall?
            if let annotation = node.call {
                let operation: OperatorID?
                switch node.expression {
                case .operatorApplication(.reference(let id, _), _), .functionApply(.operatorReference(let id), _): operation = id
                default: operation = nil
                }
                guard node.children.count == annotation.parameters.count else { return try require(nil) }
                call = try resolveCall(annotation, operation: operation,
                    operatorParameters: node.operatorParameters, callbackScope: callbackScope)
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

private extension ResolvedOperation {
    init(_ expression: CompiledStateExpr, call: ResolvedCall?) throws {
        if let call {
            self = .call(call)
            return
        }
        switch expression {
        case .value(let value): self = .value(value)
        case .stateVariable(let id): self = .stateVariable(id)
        case .boundValue(let id): self = .boundValue(id)
        case .controlLocation(let id): self = .controlLocation(id)
        case .operatorReference(let id): self = .operatorReference(id)
        case .add: self = .add
        case .subtract: self = .subtract
        case .multiply: self = .multiply
        case .divide: self = .divide
        case .modulo: self = .modulo
        case .negate: self = .negate
        case .assertView(_, let shape): self = .assertView(shape)
        case .integerDivide: self = .integerDivide
        case .equal: self = .equal
        case .notEqual: self = .notEqual
        case .lessThan: self = .lessThan
        case .lessOrEqual: self = .lessOrEqual
        case .greaterThan: self = .greaterThan
        case .greaterOrEqual: self = .greaterOrEqual
        case .and: self = .and
        case .or: self = .or
        case .not: self = .not
        case .ifThenElse: self = .ifThenElse
        case .setLiteral: self = .setLiteral
        case .in: self = .in
        case .subset: self = .subset
        case .union: self = .union
        case .intersection: self = .intersection
        case .setDifference: self = .setDifference
        case .cardinality: self = .cardinality
        case .setFilter(_, let binding, _): self = .setFilter(binding)
        case .setMap(_, let binding, _): self = .setMap(binding)
        case .powerSet: self = .powerSet
        case .unionAll: self = .unionAll
        case .integerRange: self = .integerRange
        case .tupleLiteral: self = .tupleLiteral
        case .tupleAccess(_, let index): self = .tupleAccess(index)
        case .tupleDynamicAccess: self = .tupleDynamicAccess
        case .tupleLength: self = .tupleLength
        case .tupleAppend: self = .tupleAppend
        case .tupleHead: self = .tupleHead
        case .tupleTail: self = .tupleTail
        case .tupleConcatenate: self = .tupleConcatenate
        case .tupleRemoving: self = .tupleRemoving
        case .sequenceSelect(_, let binding, _): self = .sequenceSelect(binding)
        case .recordLiteral(let record): self = .recordLiteral(record.map(\.declaration))
        case .recordAccess(_, let field): self = .recordAccess(field)
        case .domain: self = .domain
        case .functionLiteral(_, let binding, _): self = .functionLiteral(binding)
        case .functionApply: self = .functionApply
        case .except: self = .except
        case .caseExpr(_, _, let otherwise): self = .caseExpr(hasOtherwise: otherwise != nil)
        case .forAll(_, let binding, _): self = .forAll(binding)
        case .exists(_, let binding, _): self = .exists(binding)
        case .choose(_, let binding, _): self = .choose(binding)
        case .enabledAction(let id): self = .enabledAction(id)
        case .sequenceFromSet: self = .sequenceFromSet
        case .setSum: self = .setSum
        case .functionSet: self = .functionSet
        case .foldFunction(let parameters, _, _, _): self = .foldFunction(parameters)
        case .letValue(let binding, _, _): self = .letValue(binding)
        case .letIn:
            throw CompiledValueType.diagnostic("resolution.scope", "resolve local declarations to their body before constructing an operation")
        case .operatorApplication:
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
                path: "resolution.call", expected: "a resolved call target", actual: "missing call annotation",
                nextSafeAction: "Resolve the operator application before constructing the executable program.")
        }
    }
}
