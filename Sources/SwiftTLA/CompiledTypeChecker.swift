import Foundation

/// A compile-time function instance. No specialization metadata enters a machine.
package struct CheckedOperatorSpecialization: Hashable, Sendable {
    package let operation: CompiledFormalOperator
    package let arguments: [CompiledValueType]
    package let resultContext: CompiledValueType
    package let captures: [BinderID: CompiledValueType]
    package let callbacks: [OperatorID: CheckedCallbackIdentity]
}

package struct CheckedCallbackIdentity: Hashable, Sendable {
    package let operation: CompiledFormalOperator
    package let captures: [BinderID: CompiledValueType]
    package let callbacks: [OperatorID: CheckedCallbackIdentity]
    fileprivate func strictlyContains(_ other: CheckedCallbackIdentity) -> Bool {
        self != other && callbacks.values.contains { $0 == other || $0.strictlyContains(other) }
    }

}

private struct CheckedCallbackBinding: Sendable {
    let operation: CompiledFormalOperator
    let scope: CompiledTypeChecker
    let forwardedFrom: OperatorID?
    let identity: CheckedCallbackIdentity

    init(operation: CompiledFormalOperator, scope: CompiledTypeChecker) {
        self.operation = operation
        self.scope = scope
        forwardedFrom = nil
        let captures = scope.captures(of: operation)
        identity = .init(operation: operation, captures: captures.bindings, callbacks: captures.callbacks)
    }

    init(forwarding binding: CheckedCallbackBinding, from origin: OperatorID) {
        operation = binding.operation
        scope = binding.scope
        forwardedFrom = origin
        identity = binding.identity
    }
}

private struct ArgumentSource: Sendable {
    let expression: CompiledExpression
    let scope: CompiledTypeChecker
}

/// A checked call argument retains its type and lexical source together.
private enum CheckedCallArgument: Sendable {
    case value(type: CompiledValueType, domain: Set<CompiledValue>?, source: ArgumentSource)
    case `operator`(CheckedCallbackBinding)
}

private struct ArgumentRefinement: Hashable, Sendable {
    let expression: CompiledExpression
    let bindings: [BinderID: CompiledValueType]
    let expected: CompiledValueType
}

package enum CheckedOperatorImplementation: Sendable {
    case checked(body: CompiledExpression, domainGuard: CompiledExpression?)
    case recursive
}

package final class CheckedOperatorCall: Hashable, Sendable {
    package static func == (lhs: CheckedOperatorCall, rhs: CheckedOperatorCall) -> Bool { lhs === rhs }
    package func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    package let specialization: CheckedOperatorSpecialization
    package let parameters: [(binder: BinderID, type: CompiledValueType)]
    package let implementation: CheckedOperatorImplementation
    package let result: CompiledValueType
    package let callbackArguments: [OperatorID: CompiledFormalOperator]

    fileprivate init(specialization: CheckedOperatorSpecialization,
         parameters: [(binder: BinderID, type: CompiledValueType)],
         implementation: CheckedOperatorImplementation, result: CompiledValueType,
         callbackArguments: [OperatorID: CompiledFormalOperator]) {
        self.parameters = parameters
        self.specialization = .init(operation: specialization.operation,
            arguments: parameters.map(\.type), resultContext: result,
            captures: specialization.captures, callbacks: specialization.callbacks)
        self.implementation = implementation
        self.result = result
        self.callbackArguments = callbackArguments
    }
}

/// Lexical scopes are needed to finish checking callers, never by the checked program.
private struct CheckedCallResult: Sendable {
    let call: CheckedOperatorCall
    let refinedBindings: [BinderID: CompiledValueType]
    let boundOperators: [OperatorID: CheckedCallbackBinding]
    let callbackUses: [OperatorID: [CheckedCallResult]]

    init(specialization: CheckedOperatorSpecialization, parameters: [BinderID],
         implementation: CheckedOperatorImplementation, result: CompiledValueType,
         bindings: [BinderID: CompiledValueType], boundOperators: [OperatorID: CheckedCallbackBinding],
         callbackUses: [OperatorID: [CheckedCallResult]],
         callbackArguments: [OperatorID: CompiledFormalOperator]) {
        call = .init(specialization: specialization,
            parameters: parameters.map { (binder: $0, type: bindings[$0] ?? .unknown) },
            implementation: implementation, result: result,
            callbackArguments: callbackArguments)
        refinedBindings = bindings
        self.boundOperators = boundOperators
        self.callbackUses = callbackUses
    }
}

/// Checking retains the representation before an implicit use-site conversion.
struct CheckedType: Sendable {
    let type: CompiledValueType
    let computationType: CompiledValueType
    /// Expected types for pending operands; completed children own their result types.
    let operandContexts: [CompiledValueType]
    let call: CheckedOperatorCall?
    var children: [CompiledExpression] = []

    init(type: CompiledValueType, computationType: CompiledValueType, operandContexts: [CompiledValueType] = [], call: CheckedOperatorCall? = nil, children: [CompiledExpression] = []) {
        self.type = type
        self.computationType = computationType
        self.operandContexts = operandContexts
        self.call = call
        self.children = children
    }
}


private struct OperatorBodyCheck {
    let specialization: CheckedOperatorSpecialization
    let parameters: [BinderID]
    var inputTypes: [BinderID: CompiledValueType]
    let body: CompiledExpression
    let domain: CompiledExpression?
    var context: CompiledValueType
    let callbackArguments: [OperatorID: CompiledFormalOperator]
}

private enum OperatorCheck {
    case recursive(CheckedCallResult)
    case body(OperatorBodyCheck)
}

private struct PendingCallCheck {
    let expression: CompiledExpression
    let operation: CompiledFormalOperator
    let arguments: [CompiledFormalCallArgument]
    let checkedArguments: [CheckedCallArgument]
    let callbackID: OperatorID?
    let expected: CompiledValueType
}

private enum BoundValueCheck {
    case checked(CheckedType)
    case argument(ArgumentSource, ArgumentRefinement)
    case domain(CompiledExpression)
}

private enum ExpressionCheckTask {
    case check(CompiledExpression, expected: CompiledValueType)
    case boundValue(BinderID, BoundValueCheck, expected: CompiledValueType)
    case call(CompiledExpression, CompiledFormalOperator, [CompiledFormalCallArgument], expected: CompiledValueType)
    case enterCall(CompiledExpression, CompiledFormalOperator, [CompiledFormalCallArgument], expected: CompiledValueType)
    case finishOperator(OperatorBodyCheck)
    case leaveCall(PendingCallCheck)
    case refineCallCaptures(CompiledFormalOperator, CheckedCallResult)
    case refineCapture(BinderID, original: CompiledValueType, refined: CompiledValueType)
    case forwardCallbacks(CheckedCallResult)
    case completeCall(CompiledExpression, CheckedOperatorCall, expected: CompiledValueType)
    case reconcile(CompiledExpression, CompiledExpression, expected: CompiledValueType)
    case finish(expected: CompiledValueType)
    case completeOccurrence(CheckedType)
    case recordFields(ArraySlice<CompiledRecordEntry>, expected: CompiledValueType)
    case finishRecord(expected: CompiledValueType)
    case updateKey(expected: CompiledValueType)
    case updateValue(expected: CompiledValueType)
    case finishUpdate(expected: CompiledValueType)
    case applicationKey(expected: CompiledValueType)
    case applicationSource(expected: CompiledValueType)
    case finishApplication(expected: CompiledValueType)
    case recordContext(expected: CompiledValueType)
    case finishRecordAccess(expected: CompiledValueType)
    case finishSequenceOperation(expected: CompiledValueType)
    case sequenceContext(element: CompiledValueType, source: CompiledExpression)
    case sequenceValue(CompiledExpression, expected: CompiledValueType)
    case finishSequenceConstruction(expected: CompiledValueType)
    case comparison(expected: CompiledValueType)
    case subset(expected: CompiledValueType)
    case setOperands(CompiledExpression, CompiledExpression, expected: CompiledValueType)
    case bind(BinderID)
    case finishArgument(BinderID, ArgumentRefinement)
    case finishBindingDomain(BinderID)
    case bindDomain(BinderID, retainElement: Bool)
    case refineDomain(CompiledExpression, BinderID)
    case finishSetPredicate(choosing: Bool)
    case finishUnaryCollection(expected: CompiledValueType)
    case finishFunctionSet(expected: CompiledValueType)
    case set
    case setElements(ArraySlice<CompiledExpression>, element: CompiledValueType)
    case mergeSetElement(ArraySlice<CompiledExpression>, previous: CompiledValueType)
    case dictionary
    case result(CompiledValueType)
    case discard
    case retainOperand(Int)
}

/// Checks declaration-local types and resolves dependent expressions before generation.
package struct CompiledTypeChecker: Sendable {
    package static let maximumActiveSpecializations = 256

    package private(set) var variables: [VariableID: CompiledValueType] = [:]
    private var bindings: [BinderID: CompiledValueType] = [:]
    private var actionBinders: Set<BinderID> = []
    package let inputs: CompiledTypeInputs
    package var enums: CompiledEnums { inputs.types.enums }
    package var namedDomains: [String: Set<CompiledValue>] { inputs.types.namedDomains }
    package var namedRepresentations: [String: CompiledValueType] { inputs.types.namedRepresentations }
    private var bindingSources: [BinderID: CompiledExpression] = [:]
    private var argumentSources: [BinderID: ArgumentSource] = [:]
    private var activeArgumentRefinements: Set<ArgumentRefinement> = []
    private var activeBindingRefinements: Set<BinderID> = []
    private var bindingDomains: [BinderID: Set<CompiledValue>] = [:]
    private var specializationResults: [CheckedOperatorSpecialization: CompiledValueType] = [:]
    private var activeOperators: Set<CheckedOperatorSpecialization> = []
    private var localCaptures: [OperatorID: [BinderID: CompiledValueType]] = [:]
    private var boundOperators: [OperatorID: CheckedCallbackBinding] = [:]
    private var callbackUses: [OperatorID: [CheckedCallResult]] = [:]
    fileprivate func captures(of operation: CompiledFormalOperator) -> (
        bindings: [BinderID: CompiledValueType], callbacks: [OperatorID: CheckedCallbackIdentity]
    ) {
        let id = operation.declarationID
        let dependencies = inputs.semantics.operators.dependencies[id]
        let valuesInScope: [BinderID: CompiledValueType]
        switch operation {
        case .lambda:
            let required = dependencies?.bindings ?? []
            valuesInScope = bindings.filter { required.contains($0.key) }
        case .reference:
            valuesInScope = localCaptures[id] ?? [:]
        }
        var values = valuesInScope
        var callbacks: [OperatorID: CheckedCallbackIdentity] = [:]
        let requiredOperators = (dependencies?.operators ?? []).union([id])
        for dependency in requiredOperators.sorted(by: { $0.ordinal < $1.ordinal }) {
            if let callback = boundOperators[dependency] { callbacks[dependency] = callback.identity }
            values.merge(localCaptures[dependency] ?? [:]) { current, _ in current }
        }
        return (values, callbacks)
    }


    private mutating func recordCallback(_ id: OperatorID, call: CheckedCallResult) {
        if !(callbackUses[id] ?? []).contains(where: { existing in
            existing.call.result == call.call.result && existing.call.specialization.arguments == call.call.specialization.arguments
        }) {
            callbackUses[id, default: []].append(call)
        }
    }

    package init(inputs: CompiledTypeInputs) throws {
        self.inputs = inputs
        variables = inputs.variableTypes
        for action in inputs.semantics.behavior.actions {
            for binding in action.bindings {
                actionBinders.insert(binding.binder)
                let hint = inputs.bindingTypes[binding.binder] ?? .unknown
                let inferred = try binding.values.reduce(hint) { try CompiledValueType.merge($0, literal($1, expected: hint)) }
                bindingDomains[binding.binder] = Set(binding.values)
                bindings[binding.binder] = try CompiledValueType.merge(bindings[binding.binder] ?? .unknown, inferred)
            }
        }
    }

    package mutating func checkProgram() throws -> CompiledProgram {
        var initializations: [(variable: VariableID, initialization: CompiledVariableInitialization)] = []
        var actions: [CompiledAction] = []
        var invariants: [CompiledInvariant] = []
        var temporalProperties: [CompiledTemporal<CompiledStateQuery>] = []
        var constraint: CompiledStateQuery?
        var assume: CompiledStateQuery?
        let declarations = Dictionary(uniqueKeysWithValues: inputs.layout.variables.map { ($0.id, $0.declaration) })
        for initialization in inputs.semantics.behavior.initializations {
            guard let declaration = declarations[initialization.variable] else {
                throw CompiledValueType.diagnostic("initialization", "missing variable declaration")
            }
            do {
                let expected = variables[initialization.variable] ?? .unknown
                let inferred: CompiledValueType
                switch initialization.initialization {
                case .value(let expression):
                    let checked = try checkOperand(expression, expected: expected)
                    initializations.append((initialization.variable, .value(checked)))
                    inferred = checked.resultType
                case .memberOf(let domain):
                    let checked = try checkOperand(domain, expected: .set(expected))
                    initializations.append((initialization.variable, .memberOf(checked)))
                    inferred = try element(checked.resultType)
                }
                variables[initialization.variable] = try CompiledValueType.merge(expected, inferred)
            } catch let diagnostic as CompilationDiagnostic {
                throw Self.contextualDiagnostic("variables.\(declaration.name).initialization", causedBy: diagnostic)
            }
            guard declaration.origin == .source else { continue }
            guard let type = variables[initialization.variable], type.resolved else {
                throw CompilationDiagnostic(code: .unresolvedGeneratedValueShape, stage: .validation,
                    path: "nativeMachine.variables.\(declaration.name)",
                    expected: "a complete type from the declaration or its initializer",
                    actual: "the initializer leaves part of the variable type unknown",
                    nextSafeAction: "Add a concrete type to the variable declaration or use a typed initializer; other declarations and later assignments do not infer its type.")
            }
        }
        for action in inputs.semantics.behavior.actions {
            do {
                actions.append(.init(id: action.id, bindings: action.bindings,
                    body: try checkAction(action.body), collection: action.collection))
            }
            catch let diagnostic as CompilationDiagnostic {
                let name = inputs.layout.actions.first { $0.id == action.id }?.declaration.name ?? String(action.id.ordinal)
                throw Self.contextualDiagnostic("actions.\(name)", causedBy: diagnostic)
            }
        }
        for invariant in inputs.semantics.behavior.invariants {
            do { invariants.append(try invariant.map { try checkOperand($0, expected: .bool) }) }
            catch let diagnostic as CompilationDiagnostic {
                throw Self.contextualDiagnostic("invariants.\(invariant.name)", causedBy: diagnostic)
            }
        }
        for property in inputs.semantics.behavior.temporalProperties {
            do {
                let checked = try property.map { predicate in
                    try predicate.map { try checkOperand($0, expected: .bool) }
                }
                temporalProperties.append(checked)
            } catch let diagnostic as CompilationDiagnostic {
                throw Self.contextualDiagnostic("temporalProperties.\(property.name)", causedBy: diagnostic)
            }
        }
        constraint = try inputs.semantics.behavior.constraint.map { predicate in
            try predicate.map { try checkOperand($0, expected: .bool) }
        }
        assume = try inputs.semantics.behavior.assume.map { predicate in
            try predicate.map { try checkOperand($0, expected: .bool) }
        }
        for variable in inputs.layout.variables {
            guard let type = variables[variable.id], type.resolved else {
                throw CompiledValueType.unresolvedDiagnostic(variables[variable.id] ?? .unknown,
                    at: "variables.\(variable.declaration.name)")
            }
        }
        var bindingTypes: [BinderID: CompiledValueType] = [:]
        for binder in actionBinders.sorted(by: { $0.ordinal < $1.ordinal }) {
            let type = bindings[binder] ?? .unknown
            guard type.resolved else {
                let name = inputs.bindings.binderName(binder) ?? String(binder.ordinal)
                throw CompiledValueType.unresolvedDiagnostic(type, at: "bindings.\(name)")
            }
            bindingTypes[binder] = type
        }
        // Generated storage, such as a procedure stack, can obtain its element
        // type from the lowered operations that construct it. Finish only those
        // initializers; authored declarations already have complete types.
        for index in initializations.indices {
            let initialization = initializations[index]
            let type = variables[initialization.variable]!
            let expected: CompiledValueType
            switch initialization.initialization {
            case .memberOf: expected = .set(type)
            case .value: expected = type
            }
            initializations[index].initialization = try initialization.initialization.map { expression in
                if expression.resultType == expected && expression.computationType.resolved { return expression }
                let source: CompiledExpression
                switch inputs.semantics.behavior.initializations[index].initialization {
                case .value(let value), .memberOf(let value): source = value
                }
                return try checkOperand(source, expected: expected)
            }
        }
        let behavior = CompiledBehavior(
            checkDeadlock: inputs.semantics.behavior.checkDeadlock,
            initializations: initializations,
            actions: actions,
            enabledActionIndices: inputs.semantics.behavior.enabledActionIndices,
            enabledActionDependencies: inputs.semantics.behavior.enabledActionDependencies,
            invariants: invariants,
            temporalProperties: temporalProperties,
            fairness: inputs.semantics.behavior.fairness,
            constraint: constraint,
            assume: assume)
        return CompiledProgram(identity: inputs.identity, layout: inputs.layout, behavior: behavior,
            enums: inputs.types.enums, projections: [], variableTypes: variables, bindingTypes: bindingTypes,
            functions: [])
    }

    private mutating func checkUnionConstructor(_ expression: CompiledExpression, expected: CompiledValueType) throws -> CheckedType? {
        guard case .union(let alternatives) = expected else { return nil }
        switch expression.operation {
        case .value, .setLiteral, .tupleLiteral, .recordLiteral, .functionLiteral, .union, .intersection, .setDifference: break
        default: return nil
        }
        var matches: [(scope: CompiledTypeChecker, checked: CompiledExpression)] = []
        for alternative in alternatives {
            var candidate = self
            if let checked = try? candidate.checkOperand(expression, expected: alternative) {
                matches.append((candidate, checked))
            }
        }
        guard matches.count == 1, let match = matches.first else {
            throw CompiledValueType.diagnostic("union", "expression must belong to exactly one declared union alternative")
        }
        self = match.scope
        return .init(type: expected, computationType: match.checked.resultType,
            children: match.checked.computation.children)
    }

    package func resolutionScope(_ expression: CompiledExpression, expected: CompiledValueType?) throws -> CompiledExpression {
        var scope = self
        let checked = try scope.checkOperand(expression, expected: expected ?? .unknown)
        guard checked.resultType.resolved else {
            throw CompiledValueType.unresolvedDiagnostic(checked.resultType, at: "resolution")
        }
        guard checked.computationType.resolved else {
            throw CompiledValueType.unresolvedDiagnostic(checked.computationType, at: "resolution")
        }
        return checked
    }

    private func checkedOccurrence(_ expression: CompiledExpression, annotation: CheckedType) -> CompiledExpression {
        let operation: CompiledOperation
        if let call = annotation.call {
            let origin: OperatorID?
            switch expression.operation {
            case .operatorApplication(.reference(let id, _), _): origin = id
            case .functionApply: origin = expression.children[0].referencedOperator
            default: origin = nil
            }
            operation = .checkedCall(call, origin: origin, operatorParameters: Set(boundOperators.keys))
        } else {
            operation = expression.operation
        }
        let computation = CompiledExpression(operation: operation,
            resultType: annotation.computationType, children: annotation.children)
        guard annotation.type != computation.resultType else { return computation }
        return .init(operation: .convert, resultType: annotation.type, children: [computation])
    }

    private mutating func refineOperand(
        _ checked: CompiledExpression, from expression: CompiledExpression, expected: CompiledValueType
    ) throws -> CompiledExpression {
        if checked.resultType == expected { return checked }
        return try checkOperand(expression, expected: expected)
    }

    package func type(of expression: CompiledExpression, expected: CompiledValueType? = nil) throws -> CompiledValueType {
        var inference = self
        let result = try inference.checkOperand(expression, expected: expected ?? .unknown).resultType
        guard result.resolved else { throw CompiledValueType.unresolvedDiagnostic(result, at: "expression") }
        return result
    }

    private mutating func checkMembership(value: CompiledExpression, domain: CompiledExpression, expected: CompiledValueType) throws -> CheckedType {
        let checkedDomain = try checkOperand(domain, expected: .set(.unknown))
        let checkedValue = try checkOperand(value)
        let context = try Self.operandContext(element(checkedDomain.resultType), checkedValue.resultType)
        let children = try [refineOperand(checkedValue, from: value, expected: context),
                            refineOperand(checkedDomain, from: domain, expected: .set(context))]
        return try checkedType(.bool, expected: expected, children: children)
    }

    /// Selects contextual evidence without admitting a conversion. Both
    /// expressions must subsequently prove that they can inhabit this shape.
    private static func operandContext(_ lhs: CompiledValueType, _ rhs: CompiledValueType) throws -> CompiledValueType {
        switch (lhs, rhs) {
        case (.set(let a), .set(let b)): return .set(try operandContext(a, b))
        case (.array(let a), .array(let b)): return .array(try operandContext(a, b))
        case (.dictionary(let ak, let av), .dictionary(let bk, let bv)):
            return .dictionary(try operandContext(ak, bk), try operandContext(av, bv))
        case (.tuple(let a), .tuple(let b)) where a.count == b.count:
            return .tuple(try zip(a, b).map { try operandContext($0, $1) })
        case (.record(let a), .record(let b)) where a.map(\.name) == b.map(\.name):
            return .record(try zip(a, b).map { .init(name: $0.name, type: try operandContext($0.type, $1.type)) })
        case (.collectionMember, .collectionMember), (.named, .named): return try CompiledValueType.merge(lhs, rhs)
        case (.collectionMember, _): return lhs
        case (_, .collectionMember): return rhs
        case (.finite, _): return lhs
        case (_, .finite): return rhs
        case (.named, _): return lhs
        case (_, .named): return rhs
        default: return try CompiledValueType.merge(lhs, rhs)
        }
    }

    private mutating func inferProjectionSource(_ value: CompiledExpression, index: Int, expected: CompiledValueType) throws -> CompiledExpression {
        let members: [CompiledExpression]?
        switch value.operation {
        case .tupleLiteral:
            let expressions = value.children
             members = expressions
        case .value(.tuple(let values)): members = values.map(CompiledExpression.value)
        default: members = nil
        }
        if let members {
            guard index >= 1, index <= members.count else { throw CompiledValueType.diagnostic("tupleAccess", "index outside tuple literal") }
            let children = try members.enumerated().map { offset, member in
                try checkOperand(member, expected: offset == index - 1 ? expected : .unknown)
            }
            let type = CompiledValueType.tuple(children.map(\.resultType))
            // A formal tuple value remains a literal; its components supplied the
            // contextual shape, while expression tuples retain their operands.
            if case .value = value.operation { return try checkOperand(value, expected: type) }
            return checkedOccurrence(value,
                annotation: .init(type: type, computationType: type, children: children))
        }
        let source = try checkOperand(value)
        if case .tuple(var elements) = source.resultType {
            guard index >= 1, index <= elements.count else { throw CompiledValueType.diagnostic("tupleAccess", "index outside tuple shape") }
            elements[index - 1] = try projectionStorageType(elements[index - 1], expected: expected)
            return try refineOperand(source, from: value, expected: .tuple(elements))
        }
        return try refineSequence(source, from: value, element: expected)
    }

    private func checkedType(
        _ source: CompiledValueType, expected: CompiledValueType, operandContexts: [CompiledValueType] = []
    ) throws -> CheckedType {
        if inputs.types.canProjectRead(source, to: expected) {
            return .init(type: expected, computationType: source, operandContexts: operandContexts)
        }
        let type = try CompiledValueType.merge(source, expected)
        return .init(type: type, computationType: type, operandContexts: operandContexts)
    }

    private func checkedType(_ source: CompiledValueType, expected: CompiledValueType, children: [CompiledExpression]) throws -> CheckedType {
        let checked = try checkedType(source, expected: expected)
        return .init(type: checked.type, computationType: checked.computationType, children: children)
    }

    private mutating func retaining(_ children: [CompiledExpression], from expressions: [CompiledExpression], in annotation: CheckedType) throws -> CheckedType {
        guard children.count == annotation.operandContexts.count && children.count == expressions.count else {
            throw CompiledValueType.diagnostic("checking", "missing checked operands")
        }
        let refined = try zip(zip(children, expressions), annotation.operandContexts).map { operand, expected in
            try refineOperand(operand.0, from: operand.1, expected: expected)
        }
        return .init(type: annotation.type, computationType: annotation.computationType,
            call: annotation.call, children: refined)
    }

    private func projectionStorageType(_ source: CompiledValueType, expected: CompiledValueType) throws -> CompiledValueType {
        if inputs.types.canProjectRead(source, to: expected) { return source }
        return try Self.operandContext(source, expected)
    }

    private mutating func inferDomainSource(_ expression: CompiledExpression, expected: CompiledValueType) throws -> CompiledExpression {
        let source = try checkOperand(expression)
        guard case .set(let element) = expected,
              case .dictionary(let key, let value) = source.resultType else { return source }
        let context = try projectionStorageType(key, expected: element)
        guard context != key else { return source }
        return try refineOperand(source, from: expression, expected: .dictionary(context, value))
    }

    private mutating func inferSequence(_ expression: CompiledExpression, element expected: CompiledValueType = .unknown) throws -> CompiledExpression {
        let source = try checkOperand(expression)
        return try refineSequence(source, from: expression, element: expected)
    }

    private mutating func refineSequence(_ source: CompiledExpression, from expression: CompiledExpression, element expected: CompiledValueType = .unknown) throws -> CompiledExpression {
        try refineOperand(source, from: expression, expected: sequenceContext(source.resultType, element: expected))
    }

    private func sequenceContext(_ source: CompiledValueType, element expected: CompiledValueType) throws -> CompiledValueType {
        switch source {
        case .array(let element): return .array(expected == .unknown ? element : expected)
        case .dictionary(.int, let element): return .dictionary(.int, expected == .unknown ? element : expected)
        case .unknown: return .array(expected)
        default: throw CompiledValueType.diagnostic("sequence", "expected an array or integer-keyed function, received \(source.swiftType)")
        }
    }

    private func sequenceElementType(_ source: CompiledValueType) throws -> CompiledValueType {
        switch source {
        case .array(let element), .dictionary(.int, let element): return element
        default: throw CompiledValueType.diagnostic("sequence", "invalid sequence representation")
        }
    }

    private static func contextualDiagnostic(_ context: String, causedBy cause: CompilationDiagnostic) -> CompilationDiagnostic {
        .init(code: cause.code, stage: cause.stage,
              path: "nativeMachine.\(context) → \(cause.path)",
              expected: cause.expected, actual: cause.actual, nextSafeAction: cause.nextSafeAction)
    }

    private func element(_ type: CompiledValueType) throws -> CompiledValueType {
        switch type {
        case .set(let value), .array(let value): return value
        case .unknown: return .unknown
        default: throw CompiledValueType.diagnostic("domain", "expected collection, found \(type.swiftType)")
        }
    }

    private func literal(_ value: CompiledValue, expected: CompiledValueType = .unknown) throws -> CompiledValueType {
        if case .union(let alternatives) = expected {
            let matches = alternatives.filter { (try? literal(value, expected: $0)) != nil }
            guard matches.count == 1 else { throw CompiledValueType.diagnostic("union", "literal must belong to exactly one union alternative") }
            return expected
        }
        if case .collectionMember(let variable, _) = expected {
            guard inputs.collectionDomains[variable]?.contains(value) == true else {
                throw CompiledValueType.diagnostic("collectionMember", "literal is outside the declared collection domain")
            }
            return expected
        }
        if case .finite(let members) = expected {
            guard members.contains(value) else { throw CompiledValueType.diagnostic("finiteValue", "literal is outside the declared union domain") }
            return expected
        }
        if case .named(let name) = expected {
            if let domain = namedDomains[name], !domain.contains(value) {
                throw CompiledValueType.diagnostic("namedValue", "literal is outside the declared domain of \(name)")
            }
            switch value {
            case .integer, .string, .constant: return expected
            default: break
            }
        }
        let result: CompiledValueType
        switch value {
        case .integer: result = .int
        case .boolean: result = .bool
        case .string: result = .string
        case .constant: result = .atom
        case .controlLocation: result = .control
        case .set(let values):
            let hint: CompiledValueType = if case .set(let type) = expected { type } else { .unknown }
            result = .set(try values.reduce(hint) { try CompiledValueType.merge($0, literal($1, expected: hint)) })
        case .tuple(let values):
            if case .tuple(let hints) = expected, hints.count == values.count {
                result = .tuple(try zip(values, hints).map { try literal($0, expected: $1) })
            } else {
                let hint: CompiledValueType = if case .array(let type) = expected { type } else { .unknown }
                let types = try values.map { try literal($0, expected: hint) }
                if hint == .unknown, let first = types.first, types.contains(where: { $0 != first }) {
                    result = .tuple(types)
                } else { result = .array(try types.reduce(hint, CompiledValueType.merge)) }
            }
        case .record(let record):
            let hints: [CompiledFieldType] = if case .record(let fields) = expected { fields } else { [] }
            result = .record(try record.fields.map { field in
                guard case .string(let name) = field.key else { throw CompiledValueType.diagnostic("record", "non-string field") }
                return .init(name: name, type: try literal(field.value, expected: hints.first { $0.name == name }?.type ?? .unknown))
            }.sorted { $0.name < $1.name })
        case .function(let entries):
            let hints: (CompiledValueType, CompiledValueType) = if case .dictionary(let key, let value) = expected { (key, value) } else { (.unknown, .unknown) }
            let types = try entries.reduce(hints) { result, entry in
                (try CompiledValueType.merge(result.0, literal(entry.key, expected: hints.0)), try CompiledValueType.merge(result.1, literal(entry.value, expected: hints.1)))
            }
            result = .dictionary(types.0, types.1)
        }
        return try CompiledValueType.merge(expected, result)
    }

    /// A conservative finite bound obtained from literal set construction only.
    /// A state's current initializer is not evidence about all future domains.
    private func literalDomain(_ expression: CompiledExpression) -> Set<CompiledValue>? {
        switch expression.operation {
        case .value(.set(let values)): return values
        case .setLiteral:
            let expressions = expression.children

            return expressions.reduce(Optional(Set<CompiledValue>())) { result, expression in
                guard let result, let values = literalValues(expression) else { return nil }
                return result.union(values)
            }
        case .union:
            let lhs = expression.children[0]
            let rhs = expression.children[1]

            guard let lhs = literalDomain(lhs), let rhs = literalDomain(rhs) else { return nil }
            return lhs.union(rhs)
        case .intersection:
            let lhs = expression.children[0]
            let rhs = expression.children[1]

            // Either known operand bounds every possible intersection member.
            if let lhs = literalDomain(lhs) { return lhs }
            return literalDomain(rhs)
        case .setDifference:
            let lhs = expression.children[0]
             return literalDomain(lhs)
        case .setFilter(_):
            let domain = expression.children[0]
             return literalDomain(domain)
        default: return nil
        }
    }

    private func literalValues(_ expression: CompiledExpression) -> Set<CompiledValue>? {
        switch expression.operation {
        case .value(let value): return [value]
        case .boundValue(let binder): return bindingDomains[binder]
        default: return nil
        }
    }

    private mutating func checkAction(
        _ action: CompiledActionExpr
    ) throws -> CompiledActionExpr {
        switch action {
        case .assign(let id, let expression):
            let checked = try checkOperand(expression, expected: variables[id] ?? .unknown)
            variables[id] = try CompiledValueType.merge(variables[id] ?? .unknown, checked.resultType)
            return .assign(id, checked)
        case .unchanged(let id): return .unchanged(id)
        case .guard_(let expression): return .guard_(try checkOperand(expression, expected: .bool))
        case .and(let lhs, let rhs): return .and(try checkAction(lhs), try checkAction(rhs))
        case .or(let lhs, let rhs): return .or(try checkAction(lhs), try checkAction(rhs))
        case .ifElse(let condition, let lhs, let rhs):
            return .ifElse(try checkOperand(condition, expected: .bool), try checkAction(lhs), try checkAction(rhs))
        case .define(let id, let value, let body):
            actionBinders.insert(id)
            bindingSources[id] = .setLiteral([value])
            bindingDomains[id] = literalValues(value)
            let checked = try checkOperand(value, expected: bindings[id] ?? .unknown)
            bindings[id] = checked.resultType
            let checkedBody = try checkActionBody(body, binding: id)
            let definition = try refineOperand(checked, from: value, expected: bindings[id]!)
            return .define(id, definition, checkedBody)
        case .existsAction(let id, let domain, let body):
            actionBinders.insert(id)
            bindingSources[id] = domain
            bindingDomains[id] = literalDomain(domain)
            let checked = try checkOperand(domain, expected: .set(bindings[id] ?? .unknown))
            bindings[id] = try element(checked.resultType)
            let checkedBody = try checkActionBody(body, binding: id)
            let checkedDomain = try refineOperand(checked, from: domain, expected: .set(bindings[id]!))
            return .existsAction(id, checkedDomain, checkedBody)
        }
    }

    private mutating func checkActionBody(
        _ body: CompiledActionExpr, binding: BinderID
    ) throws -> CompiledActionExpr {
        while true {
            let input = bindings[binding]
            let checked = try checkAction(body)
            // Context in a later statement can resolve this local binder. Earlier
            // occurrences must then use that same representation.
            if bindings[binding] == input { return checked }
        }
    }

    private func captureCallArguments(
        _ arguments: [CompiledFormalCallArgument], types argumentTypes: [CompiledValueType]
    ) -> [CheckedCallArgument] {
        // Infer every argument before capturing the caller scope: a later
        // argument can establish type information used by an earlier one.
        return zip(arguments, argumentTypes).map { argument, type -> CheckedCallArgument in
            switch argument {
            case .value(let value):
                let source: ArgumentSource
                if case .boundValue(let id) = value.operation, let existing = argumentSources[id] {
                    source = existing
                } else {
                    source = .init(expression: value, scope: self)
                }
                return .value(type: type, domain: literalValues(value), source: source)
            case .operator(let operation):
                if case .reference(let target, _) = operation, let binding = boundOperators[target] {
                    return .operator(.init(forwarding: binding, from: target))
                }
                return .operator(.init(operation: operation, scope: self))
            }
        }
    }

    private func capturedValueChecks(
        _ captures: [BinderID: CompiledValueType], using resolved: [BinderID: CompiledValueType]
    ) -> [ExpressionCheckTask] {
        captures.compactMap { binder, original in
            guard let refined = resolved[binder], refined != original else { return nil }
            return .refineCapture(binder, original: original, refined: refined)
        }
    }

    private mutating func prepareOperator(
        _ operation: CompiledFormalOperator,
        arguments: [CheckedCallArgument], expected: CompiledValueType
    ) throws -> OperatorCheck {
        let captured = captures(of: operation)
        guard let definition = inputs.semantics.operators[operation.declarationID] else {
            throw CompiledValueType.diagnostic("operator", "unknown operator identity \(operation.declarationID.ordinal)")
        }
        let formalParameters = definition.parameters
        let body = definition.body
        let domain = definition.domain
        guard formalParameters.count == arguments.count else { throw CompiledValueType.diagnostic("operator", "argument count mismatch") }
        var callbackArguments: [OperatorID: CompiledFormalOperator] = [:]
        var identities = captured.callbacks
        var valueTypes: [CompiledValueType] = []
        for (parameter, argument) in zip(formalParameters, arguments) {
            switch (parameter, argument) {
            case (.value, .value(let type, _, _)):
                valueTypes.append(type)
            case (.operator(let id, let arity), .operator(let callback)):
                guard callback.operation.arity == arity else {
                    throw CompiledValueType.diagnostic("operator", "operator argument arity mismatch")
                }
                identities[id] = callback.identity
                callbackArguments[id] = callback.forwardedFrom.map { .reference($0, arity: arity) } ?? callback.operation
            case (.value, .operator):
                throw CompiledValueType.diagnostic("operator", "expected value argument")
            case (.operator, .value):
                throw CompiledValueType.diagnostic("operator", "expected operator argument")
            }
        }
        let parameters = formalParameters.compactMap(\.valueBinder)
        let key = CheckedOperatorSpecialization(operation: operation, arguments: valueTypes,
            resultContext: expected, captures: captured.bindings, callbacks: identities)
        if activeOperators.contains(where: { active in
            guard active.operation == key.operation, active.arguments.count == key.arguments.count else { return false }
            let pairs = Array(zip(active.arguments, key.arguments))
            let argumentGrowth = pairs.contains { $1.strictlyContains($0) } && pairs.allSatisfy { $0 == $1 || $1.strictlyContains($0) }
            let callbackGrowth = active.callbacks.contains { id, previous in key.callbacks[id]?.strictlyContains(previous) == true }
            return argumentGrowth || callbackGrowth
        }) {
            throw CompiledValueType.diagnostic("operator", "recursive calls require a growing family of native specializations")
        }
        // Native specialization is compile-time work, distinct from the runtime
        // recursion counter. Limit active expansion even when structural growth
        // is not recognizable (for example, changing higher-order captures).
        if !activeOperators.contains(key), activeOperators.count >= Self.maximumActiveSpecializations {
            throw CompiledValueType.diagnostic("operator", "native specialization exceeds the compiler limit of \(Self.maximumActiveSpecializations) active function shapes")
        }
        let context = try Self.operandContext(specializationResults[key] ?? .unknown, expected)
        if activeOperators.contains(key) {
            return .recursive(.init(specialization: key, parameters: parameters, implementation: .recursive,
                result: context, bindings: bindings, boundOperators: boundOperators, callbackUses: callbackUses, callbackArguments: callbackArguments))
        }
        activeOperators.insert(key)
        specializationResults[key] = context
        callbackUses = [:]
        for (parameter, argument) in zip(formalParameters, arguments) {
            switch (parameter, argument) {
            case (.value(let binder, _), .value(let type, let domain, let source)):
                bindings[binder] = type
                argumentSources[binder] = source
                if let domain {
                    bindingSources[binder] = .value(.set(domain)); bindingDomains[binder] = domain
                } else {
                    bindingSources.removeValue(forKey: binder); bindingDomains.removeValue(forKey: binder)
                }
            case (.operator(let id, _), .operator(let callback)):
                boundOperators[id] = callback
            default:
                throw CompiledValueType.diagnostic("operator", "argument kind changed after validation")
            }
        }
        let inputs = captured.bindings.merging(Dictionary(uniqueKeysWithValues: zip(parameters, valueTypes))) { _, parameter in parameter }
        return .body(.init(specialization: key, parameters: parameters, inputTypes: inputs, body: body, domain: domain,
            context: context, callbackArguments: callbackArguments))
    }

    private mutating func checkOperand(_ expression: CompiledExpression, expected: CompiledValueType = .unknown) throws -> CompiledExpression {
        switch expression.operation {
        case .boundValue(let id):
            let check: BoundValueCheck
            do { check = try checkBoundValue(id, expected: expected) }
            catch let diagnostic as CompilationDiagnostic { throw annotated(diagnostic, at: expression) }
            if case .checked(let result) = check { return checkedOccurrence(expression, annotation: result) }
            return try checkWorklist(startingWith: .boundValue(id, check, expected: expected))
        case .letValue, .letIn, .and, .or, .not, .ifThenElse, .functionLiteral, .recordLiteral, .except, .recordAccess, .tupleDynamicAccess, .tupleLength, .tupleHead, .tupleTail, .tupleRemoving, .setMap, .setFilter, .choose, .forAll, .exists, .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .negate, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .integerRange, .equal, .notEqual, .subset, .union, .intersection, .setDifference, .setLiteral, .cardinality, .powerSet, .unionAll, .sequenceFromSet, .functionSet, .tupleAppend, .tupleConcatenate, .operatorApplication, .functionApply:
            return try checkWorklist(startingWith: .check(expression, expected: expected))
        default: break
        }
        do {
            let annotation = try inferResolved(expression, expected: expected)
            return checkedOccurrence(expression, annotation: annotation)
        } catch let diagnostic as CompilationDiagnostic {
            throw annotated(diagnostic, at: expression)
        }
    }

    private func annotated(_ diagnostic: CompilationDiagnostic, at expression: CompiledExpression) -> CompilationDiagnostic {
        let location: String
        switch expression.operation {
        case .boundValue(let id): location = "binder[\(id.ordinal)]"
        case .stateVariable(let id): location = "variable[\(inputs.layout.variables.first { $0.id == id }?.declaration.name ?? String(id.ordinal))]"
        case .tupleAccess(let index): location = "tupleAccess[\(index)]"
        case .operatorApplication(.reference(let id, _), _): location = "operator[\(id.ordinal)]"
        default: location = expression.diagnosticName
        }
        return CompilationDiagnostic(code: diagnostic.code, stage: diagnostic.stage,
            path: diagnostic.path + " <- " + location,
            expected: diagnostic.expected, actual: diagnostic.actual,
            nextSafeAction: diagnostic.nextSafeAction)
    }

    private mutating func checkBoundValue(_ id: BinderID, expected: CompiledValueType) throws -> BoundValueCheck {
        let result: CompiledValueType
        let existing = bindings[id] ?? .unknown
        // A use-site projection does not replace the binder's chosen native
        // representation. Later raw scalar reads must not erase enum identity.
        if inputs.types.canProjectRead(existing, to: expected) {
            return .checked(.init(type: expected, computationType: existing))
        }
        if expected != .unknown, existing != expected, let evidence = argumentSources[id] {
            let refinement = ArgumentRefinement(expression: evidence.expression, bindings: evidence.scope.bindings, expected: expected)
            if !activeArgumentRefinements.contains(refinement) {
                return .argument(evidence, refinement)
            }
            // Recursive construction proofs share the active obligation's
            // provisional type. Its outer invocation still validates every
            // constructor/base branch in the original lexical scope before
            // any successful call annotation can escape.
            bindings[id] = expected
            return .checked(.init(type: expected, computationType: expected))
        }
        if expected != .unknown, existing != expected, let domain = bindingSources[id],
           !activeBindingRefinements.contains(id) {
            return .domain(domain)
        }
        if case .finite(let values) = expected, let domain = bindingDomains[id], domain.isSubset(of: Set(values)) {
            bindings[id] = expected
            return .checked(.init(type: expected, computationType: expected))
        }
        if case .named(let name) = expected,
           let values = bindingDomains[id], let admitted = namedDomains[name],
           values.isSubset(of: admitted), namedRepresentations[name] == existing {
            result = expected
        } else {
            do { result = try CompiledValueType.merge(existing, expected) }
            catch {
                let representation: CompiledValueType? = if case .named(let name) = existing { namedRepresentations[name] } else { nil }
                throw CompiledValueType.diagnostic("binding[\(id.ordinal)]", "stored \(existing), requested \(expected); known representation \(String(describing: representation))")
            }
        }
        bindings[id] = result
        let checked = try checkedType(result, expected: expected)
        return .checked(.init(type: checked.type, computationType: result))
    }

    private mutating func inferTupleLiteral(_ expressions: [CompiledExpression], expected: CompiledValueType) throws -> CheckedType {
        let result: CompiledValueType
        let children: [CompiledExpression]
        if case .tuple(let hints) = expected, hints.count == expressions.count {
            children = try zip(expressions, hints).map { try checkOperand($0, expected: $1) }
            result = .tuple(children.map(\.resultType))
        } else {
            let hint: CompiledValueType = if case .array(let value) = expected { value } else { .unknown }
            children = try expressions.map { try checkOperand($0, expected: hint) }
            let types = children.map(\.resultType)
            if expected == .unknown, !types.isEmpty, types.allSatisfy({ $0 == .unknown }) { result = .tuple(types) }
            else if hint == .unknown, let first = types.first, types.contains(where: { $0 != first }) { result = .tuple(types) }
            else { result = .array(try types.reduce(hint, CompiledValueType.merge)) }
        }
        let checked = try checkedType(result, expected: expected)
        let operands: [CompiledValueType]
        switch checked.computationType {
        case .tuple(let types): operands = types
        case .array(let item): operands = Array(repeating: item, count: expressions.count)
        default: throw CompiledValueType.diagnostic("tuple", "expected tuple or sequence representation")
        }
        return try retaining(children, from: expressions, in: .init(type: checked.type, computationType: checked.computationType, operandContexts: operands))
    }

    private mutating func inferSequenceSelection(_ sequence: CompiledExpression, binder id: BinderID, predicate: CompiledExpression, expected: CompiledValueType) throws -> CheckedType {
        let hint: CompiledValueType = if case .array(let item) = expected { item } else { .unknown }
        let initial = try inferSequence(sequence)
        let item = try projectionStorageType(sequenceElementType(initial.resultType), expected: hint)
        let contextual = try refineSequence(initial, from: sequence, element: item)
        bindSequenceElement(id, type: item, source: sequence)
        let body = try checkOperand(predicate, expected: .bool)
        let selected = bindings[id] ?? item
        let source = try refineSequence(contextual, from: sequence, element: selected)
        return try checkedType(.array(selected), expected: expected, children: [source, body])
    }

    private mutating func bindSequenceElement(_ id: BinderID, type: CompiledValueType, source: CompiledExpression) {
        bindings[id] = type
        switch source.operation {
        case .value(.tuple(let members)): bindingDomains[id] = Set(members)
        case .tupleLiteral: bindingDomains[id] = literalDomain(.setLiteral(source.children))
        default: bindingDomains.removeValue(forKey: id)
        }
    }

    private mutating func inferFold(parameters: [BinderID], body expression: CompiledExpression, initial: CompiledExpression, sequence: CompiledExpression, expected: CompiledValueType) throws -> CheckedType {
        guard parameters.count == 2 else { throw CompiledValueType.diagnostic("fold", "expected two lambda parameters") }
        var accumulator = try checkOperand(initial, expected: expected)
        bindings[parameters[1]] = accumulator.resultType
        let initialSource = try inferSequence(sequence)
        let item = try sequenceElementType(initialSource.resultType)
        bindSequenceElement(parameters[0], type: item, source: sequence)
        let body = try checkOperand(expression, expected: accumulator.resultType)
        accumulator = try refineOperand(accumulator, from: initial, expected: body.resultType)
        let source = try refineSequence(initialSource, from: sequence, element: bindings[parameters[0]] ?? item)
        return try checkedType(body.resultType, expected: expected, children: [body, accumulator, source])
    }

    private mutating func inferTupleAccess(_ value: CompiledExpression, index: Int, expected: CompiledValueType) throws -> CheckedType {
        let source = try inferProjectionSource(value, index: index, expected: expected)
        let result: CompiledValueType
        if case .tuple(let elements) = source.resultType { result = elements[index - 1] }
        else { result = try sequenceElementType(source.resultType) }
        return try checkedType(result, expected: expected, children: [source])
    }

    private mutating func inferDomain(_ function: CompiledExpression, expected: CompiledValueType) throws -> CheckedType {
        let source = try inferDomainSource(function, expected: expected)
        let result: CompiledValueType
        switch source.resultType {
        case .dictionary(let key, _): result = .set(key)
        case .array, .tuple: result = .set(.int)
        case .record: result = .set(.string)
        case .unknown: result = .set(.unknown)
        default: throw CompiledValueType.diagnostic("domain", "unsupported domain shape")
        }
        return try checkedType(result, expected: expected, children: [source])
    }

    /// Visit operands in source order and retain ancestry for diagnostics.
    private mutating func checkWorklist(startingWith task: ExpressionCheckTask) throws -> CompiledExpression {
        // Tasks are appended in reverse execution order.
        var pending = [task]
        var results: [CompiledValueType] = []
        var ancestors: [CompiledExpression] = []
        var completed: CompiledExpression?
        var operandFrames: [[Int: CompiledExpression]] = []
        var suspendedScopes: [CompiledTypeChecker] = []
        var checkedCalls: [CheckedCallResult] = []
        func finish(_ annotation: CheckedType, in scope: inout CompiledTypeChecker, refineOperands: Bool = true) throws {
            guard let expression = ancestors.last, let operands = operandFrames.last else {
                throw CompiledValueType.diagnostic("checking", "missing checked occurrence")
            }
            let orderedOperands = operands.sorted { $0.key < $1.key }
            let children = orderedOperands.map(\.value)
            if refineOperands, annotation.call == nil, !children.isEmpty {
                guard children.count == annotation.operandContexts.count else {
                    throw CompiledValueType.diagnostic("checking", "missing checked operands")
                }
                let refinements = zip(orderedOperands, annotation.operandContexts).filter { operand, expected in
                    operand.value.resultType != expected
                }
                if !refinements.isEmpty {
                    pending.append(.completeOccurrence(annotation))
                    for (operand, expected) in refinements.reversed() {
                        pending.append(contentsOf: [
                            .discard, .retainOperand(operand.key),
                            .check(expression.children[operand.key], expected: expected)
                        ])
                    }
                    return
                }
            }
            _ = ancestors.popLast()
            _ = operandFrames.popLast()
            var checked = annotation
            if !children.isEmpty || annotation.call != nil { checked.children = children }
            completed = scope.checkedOccurrence(expression, annotation: checked)
        }
        let initialArgumentRefinements = activeArgumentRefinements
        let initialBindingRefinements = activeBindingRefinements
        do {
            while let task = pending.popLast() {
                switch task {
                case .check(let expression, let expected):
                    if case .union = expected {
                        switch expression.operation {
                        case .functionLiteral, .setLiteral, .recordLiteral, .union, .intersection, .setDifference:
                            ancestors.append(expression)
                            operandFrames.append([:])
                            if let checked = try checkUnionConstructor(expression, expected: expected) {
                                results.append(checked.type)
                                try finish(checked, in: &self)
                                continue
                            }
                            _ = operandFrames.popLast()
                            ancestors.removeLast()
                        default: break
                        }
                    }
                    switch expression.operation {
                    case .recordAccess(_):
                        let source = expression.children[0]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [.recordContext(expected: expected), .discard, .retainOperand(0), .check(source, expected: .unknown)])
                    case .tupleDynamicAccess:
                        let source = expression.children[0]
                        let index = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finishSequenceOperation(expected: expected), .discard, .retainOperand(0),
                            .sequenceContext(element: expected, source: source), .check(source, expected: .unknown),
                            .discard, .retainOperand(1), .check(index, expected: .int)
                        ])
                    case .tupleRemoving:
                        let source = expression.children[0]
                        let index = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        let hint = if case .array(let element) = expected { element } else { CompiledValueType.unknown }
                        pending.append(contentsOf: [
                            .finishSequenceOperation(expected: expected), .discard, .retainOperand(1), .check(index, expected: .int),
                            .discard, .retainOperand(0), .sequenceContext(element: hint, source: source), .check(source, expected: .unknown)
                        ])
                    case .tupleLength, .tupleHead, .tupleTail:
                        let source = expression.children[0]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        let hint: CompiledValueType
                        switch expression.operation {
                        case .tupleHead: hint = expected
                        case .tupleTail: hint = if case .array(let element) = expected { element } else { .unknown }
                        default: hint = .unknown
                        }
                        pending.append(contentsOf: [
                            .finishSequenceOperation(expected: expected), .discard, .retainOperand(0),
                            .sequenceContext(element: hint, source: source), .check(source, expected: .unknown)
                        ])
                    case .except:
                        let source = expression.children[0]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [.updateKey(expected: expected), .discard, .retainOperand(0), .check(source, expected: expected)])
                    case .recordLiteral(let declarations):
                        let record = zip(declarations, expression.children).map { CompiledRecordEntry(name: $0, value: $1) }

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [.finishRecord(expected: expected), .recordFields(record[...], expected: expected)])
                    case .tupleAppend, .tupleConcatenate:
                        let sequence = expression.children[0]
                        let value = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        let element = if case .array(let element) = expected { element } else { CompiledValueType.unknown }
                        pending.append(contentsOf: [
                            .sequenceValue(value, expected: expected), .retainOperand(0),
                            .sequenceContext(element: element, source: sequence), .check(sequence, expected: .unknown)
                        ])
                    case .operatorApplication(let operation, let arguments):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(.call(expression, operation, arguments, expected: expected))
                    case .functionApply where expression.children[0].referencedOperator != nil:
                let id = expression.children[0].referencedOperator!
                let argument = expression.children[1]
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(.call(expression, .reference(id, arity: 1), [.value(argument)], expected: expected))
                    case .functionApply:
                        let source = expression.children[0]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [.applicationKey(expected: expected), .discard, .retainOperand(0), .check(source, expected: .unknown)])
                    case .setLiteral:
                        let elements = expression.children

                        ancestors.append(expression)
                        operandFrames.append([:])
                        let hint: CompiledValueType = if case .set(let item) = expected { item } else { .unknown }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .setElements(elements[...], element: hint),
                        ])
                    case .boundValue(let id):
                        do {
                            pending.append(.boundValue(id, try checkBoundValue(id, expected: expected), expected: expected))
                        } catch let diagnostic as CompilationDiagnostic {
                            throw annotated(diagnostic, at: expression)
                        }
                    case .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .integerRange:
                        let lhs = expression.children[0]
                        let rhs = expression.children[1]

                        let result: CompiledValueType = switch expression.operation {
                        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual: .bool
                        case .integerRange: .set(.int)
                        default: .int
                        }
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected), .result(result),
                            .discard, .retainOperand(1), .check(rhs, expected: .int),
                            .discard, .retainOperand(0), .check(lhs, expected: .int),
                        ])
                    case .negate:
                        let operand = expression.children[0]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected), .result(.int),
                            .discard, .retainOperand(0), .check(operand, expected: .int),
                        ])
                    case .equal, .notEqual, .subset:
                        let lhs = expression.children[0]
                        let rhs = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        if case .subset = expression.operation { pending.append(.subset(expected: expected)) }
                        else { pending.append(.comparison(expected: expected)) }
                        pending.append(contentsOf: [
                            .reconcile(lhs, rhs, expected: .unknown),
                            .retainOperand(1), .check(rhs, expected: .unknown),
                            .retainOperand(0), .check(lhs, expected: .unknown),
                        ])
                    case .union, .intersection, .setDifference:
                        let lhs = expression.children[0]
                        let rhs = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .setOperands(lhs, rhs, expected: expected),
                            .reconcile(lhs, rhs, expected: .unknown),
                            .retainOperand(1), .check(rhs, expected: .unknown),
                            .retainOperand(0), .check(lhs, expected: .unknown),
                        ])
                    case .ifThenElse:
                        let condition = expression.children[0]
                        let yes = expression.children[1]
                        let no = expression.children[2]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .reconcile(yes, no, expected: expected),
                            .retainOperand(2), .check(no, expected: expected),
                            .retainOperand(1), .check(yes, expected: expected),
                            .discard,
                            .retainOperand(0), .check(condition, expected: .bool),
                        ])
                    case .and, .or:
                        let lhs = expression.children[0]
                        let rhs = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .result(.bool),
                            .discard,
                            .retainOperand(1), .check(rhs, expected: .bool),
                            .discard,
                            .retainOperand(0), .check(lhs, expected: .bool),
                        ])
                    case .not:
                        let operand = expression.children[0]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .result(.bool),
                            .discard,
                            .retainOperand(0), .check(operand, expected: .bool),
                        ])
                    case .letValue(let id):
                        let value = expression.children[0]
                        let body = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        bindingSources[id] = .setLiteral([value])
                        bindingDomains[id] = literalValues(value)
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .retainOperand(1), .check(body, expected: expected),
                            .bind(id),
                            .retainOperand(0), .check(value, expected: bindings[id] ?? .unknown),
                        ])
                    case .letIn(let ids):
                        let body = expression.children[0]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        for id in ids {
                            let captures = inputs.semantics.operators.dependencies[id]?.bindings ?? []
                            localCaptures[id] = bindings.filter { captures.contains($0.key) }
                        }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .retainOperand(0), .check(body, expected: expected),
                        ])
                    case .functionLiteral(let id):
                        let domain = expression.children[0]
                        let body = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        let hints: (key: CompiledValueType, value: CompiledValueType)
                        if case .dictionary(let key, let value) = expected { hints = (key, value) }
                        else { hints = (.unknown, .unknown) }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .dictionary,
                            .retainOperand(1), .check(body, expected: hints.value),
                            .bindDomain(id, retainElement: true),
                            .retainOperand(0), .check(domain, expected: .set(hints.key)),
                        ])
                    case .cardinality, .powerSet, .unionAll, .sequenceFromSet:
                        let domain = expression.children[0]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        let hint: CompiledValueType
                        switch expression.operation {
                        case .powerSet:
                            hint = if case .set(let item) = expected { item } else { .set(.unknown) }
                        case .unionAll:
                            hint = .set(expected == .unknown ? .set(.unknown) : expected)
                        case .sequenceFromSet:
                            hint = if case .array(let item) = expected { .set(item) } else { .set(.unknown) }
                        default: hint = .set(.unknown)
                        }
                        pending.append(contentsOf: [.finishUnaryCollection(expected: expected), .retainOperand(0), .check(domain, expected: hint)])
                    case .functionSet:
                        let domain = expression.children[0]
                        let range = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        let candidate: CompiledValueType = if case .set(let item) = expected { item } else { .unknown }
                        let hint: CompiledValueType = candidate == .unknown ? .dictionary(.unknown, .unknown) : candidate
                        guard case .dictionary(let key, let value) = hint else {
                            throw CompiledValueType.diagnostic("functionSet", "expected set of dictionaries")
                        }
                        pending.append(contentsOf: [
                            .finishFunctionSet(expected: expected),
                            .retainOperand(1), .check(range, expected: .set(value)),
                            .retainOperand(0), .check(domain, expected: .set(key)),
                        ])
                    case .setFilter(let id), .choose(let id):
                        let domain = expression.children[0]
                        let predicate = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        let choosing: Bool = if case .choose = expression.operation { true } else { false }
                        let hint: CompiledValueType = choosing ? .set(expected) : (expected == .unknown ? .set(.unknown) : expected)
                        pending.append(contentsOf: [
                            .finishSetPredicate(choosing: choosing),
                            .refineDomain(domain, id),
                            .discard, .retainOperand(1), .check(predicate, expected: .bool),
                            .bindDomain(id, retainElement: false),
                            .retainOperand(0), .check(domain, expected: hint),
                        ])
                    case .setMap(let id):
                        let body = expression.children[0]
                        let domain = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        let hint: CompiledValueType = if case .set(let item) = expected { item } else { .unknown }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .set,
                            .retainOperand(0), .check(body, expected: hint),
                            .bindDomain(id, retainElement: false),
                            .retainOperand(1), .check(domain, expected: .set(.unknown)),
                        ])
                    case .forAll(let id), .exists(let id):
                        let domain = expression.children[0]
                        let body = expression.children[1]

                        ancestors.append(expression)
                        operandFrames.append([:])
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .result(.bool),
                            .discard,
                            .retainOperand(1), .check(body, expected: .bool),
                            .bindDomain(id, retainElement: false),
                            .retainOperand(0), .check(domain, expected: .set(.unknown)),
                        ])
                    default:
                        let checked = try checkOperand(expression, expected: expected)
                        results.append(checked.resultType)
                        completed = checked
                    }
                case .call(let expression, let operation, let arguments, let expected):
                    let target = boundOperators[operation.declarationID]?.operation ?? operation
                    guard let definition = inputs.semantics.operators[target.declarationID],
                          definition.parameters.count == arguments.count else {
                        throw CompiledValueType.diagnostic("operator", "unknown operator or argument count mismatch")
                    }
                    pending.append(.enterCall(expression, operation, arguments, expected: expected))
                    for (index, pair) in zip(definition.parameters, arguments).enumerated().reversed() {
                        switch pair.1 {
                        case .value(let value):
                            let context = pair.0.valueBinder.flatMap { inputs.bindingTypes[$0] } ?? .unknown
                            pending.append(contentsOf: [.retainOperand(index), .check(value, expected: context)])
                        case .operator: pending.append(.result(.unknown))
                        }
                    }
                case .enterCall(let expression, let requested, let arguments, let expected):
                    guard results.count >= arguments.count else {
                        throw CompiledValueType.diagnostic("checking", "missing checked call arguments")
                    }
                    let types = Array(results.suffix(arguments.count))
                    results.removeLast(arguments.count)
                    let argumentsWithSources = captureCallArguments(arguments, types: types)
                    let callbackID: OperatorID?
                    if case .reference(let id, _) = requested, boundOperators[id] != nil { callbackID = id }
                    else { callbackID = nil }
                    let callback = callbackID.flatMap { boundOperators[$0] }
                    let operation = callback?.operation ?? requested
                    let call = PendingCallCheck(expression: expression, operation: operation,
                        arguments: arguments, checkedArguments: argumentsWithSources,
                        callbackID: callbackID, expected: expected)
                    var callee = callback?.scope ?? self
                    callee.activeOperators = activeOperators
                    callee.activeArgumentRefinements = activeArgumentRefinements
                    callee.specializationResults.merge(specializationResults) { _, current in current }
                    suspendedScopes.append(self)
                    self = callee
                    pending.append(.leaveCall(call))
                    switch try prepareOperator(operation, arguments: argumentsWithSources, expected: expected) {
                    case .recursive(let resolved):
                        checkedCalls.append(resolved)
                    case .body(let operation):
                        pending.append(contentsOf: [.finishOperator(operation), .check(operation.body, expected: operation.context)])
                        if let domain = operation.domain, let binder = operation.parameters.first {
                            pending.append(contentsOf: [
                                .bindDomain(binder, retainElement: false),
                                .check(domain, expected: .set(bindings[binder] ?? .unknown)),
                            ])
                        }
                    }
                case .finishOperator(var operation):
                    guard let result = results.popLast(), let body = completed else {
                        throw CompiledValueType.diagnostic("checking", "missing checked operator body")
                    }
                    let inferred = try Self.operandContext(operation.context, result)
                    specializationResults[operation.specialization] = inferred
                    let inputTypes = operation.inputTypes
                    let refinedInputs = Dictionary(uniqueKeysWithValues: inputTypes.map { binder, type in
                        (binder, bindings[binder] ?? type)
                    })
                    // A concrete representation can still change through contextual typing.
                    // Recheck only this operator when its parameters, captures, or result change.
                    if inferred != operation.context || refinedInputs != inputTypes {
                        operation.context = inferred
                        operation.inputTypes = refinedInputs
                        pending.append(contentsOf: [.finishOperator(operation), .check(operation.body, expected: inferred)])
                        continue
                    }
                    let domainGuard: CompiledExpression?
                    if let domain = operation.domain, let parameter = operation.parameters.first {
                        domainGuard = try checkOperand(.init(operation: .in, children: [.boundValue(parameter), domain]), expected: .bool)
                    } else { domainGuard = nil }
                    activeOperators.remove(operation.specialization)
                    checkedCalls.append(.init(specialization: operation.specialization, parameters: operation.parameters,
                        implementation: .checked(body: body, domainGuard: domainGuard), result: result, bindings: bindings, boundOperators: boundOperators,
                        callbackUses: callbackUses, callbackArguments: operation.callbackArguments))
                case .leaveCall(let call):
                    guard let resolved = checkedCalls.popLast(), var caller = suspendedScopes.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked call or caller context")
                    }
                    caller.specializationResults.merge(specializationResults) { _, current in current }
                    caller.variables = variables
                    self = caller
                    if let callbackID = call.callbackID { recordCallback(callbackID, call: resolved) }
                    pending.append(contentsOf: [
                        .completeCall(call.expression, resolved.call, expected: call.expected),
                        .refineCallCaptures(call.operation, resolved),
                    ])
                    let values = zip(call.arguments, call.checkedArguments).enumerated().compactMap { index, pair -> (Int, CompiledExpression, CompiledValueType)? in
                        let (argument, checked) = pair
                        guard case .value(let value) = argument, case .value(let type, _, _) = checked else { return nil }
                        return (index, value, type)
                    }
                    for (argument, refined) in zip(values, resolved.call.parameters.map(\.type)).reversed() {
                        if argument.2 != refined {
                            pending.append(contentsOf: [.discard, .retainOperand(argument.0), .check(argument.1, expected: refined)])
                        }
                    }
                case .refineCallCaptures(let operation, let resolved):
                    var checks: [ExpressionCheckTask] = []
                    if case .reference(let id, _) = operation, let captures = localCaptures[id] {
                        checks.append(contentsOf: capturedValueChecks(captures, using: resolved.refinedBindings))
                    }
                    for (parameter, uses) in resolved.callbackUses {
                        guard resolved.call.callbackArguments[parameter] != nil,
                              let binding = resolved.boundOperators[parameter],
                              binding.forwardedFrom == nil else { continue }
                        let parameters: Set<BinderID>
                        if case .lambda(let id, _) = binding.operation,
                           let declaration = inputs.semantics.operators[id] {
                            parameters = Set(declaration.parameters.compactMap(\.valueBinder))
                        }
                        else { parameters = [] }
                        let captures = binding.scope.bindings.filter { !parameters.contains($0.key) }
                        for use in uses { checks.append(contentsOf: capturedValueChecks(captures, using: use.refinedBindings)) }
                    }
                    pending.append(.forwardCallbacks(resolved))
                    pending.append(contentsOf: checks.reversed())
                case .refineCapture(let binder, let original, let refined):
                    if bindings[binder] == original {
                        pending.append(contentsOf: [.discard, .check(.boundValue(binder), expected: refined)])
                    }
                case .forwardCallbacks(let resolved):
                    for (parameter, uses) in resolved.callbackUses {
                        if resolved.call.callbackArguments[parameter] == nil, boundOperators[parameter] != nil {
                            for use in uses { recordCallback(parameter, call: use) }
                        } else if let origin = resolved.boundOperators[parameter]?.forwardedFrom {
                            for use in uses { recordCallback(origin, call: use) }
                        }
                    }
                case .completeCall(let expression, let call, let expected):
                    let checked: CheckedType
                    if case .functionApply = expression.operation {
                        checked = .init(type: call.result, computationType: call.result, call: call)
                    } else {
                        let result = try checkedType(call.result, expected: expected)
                        checked = .init(type: result.type, computationType: result.computationType,
                            operandContexts: result.operandContexts, call: call)
                    }
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .finishArgument(let id, let refinement):
                    guard let refined = results.popLast(), var caller = suspendedScopes.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing suspended argument context")
                    }
                    caller.specializationResults.merge(specializationResults) { _, current in current }
                    caller.bindings[id] = refined
                    caller.activeArgumentRefinements.remove(refinement)
                    self = caller
                    results.append(refined)
                    try finish(.init(type: refined, computationType: refined), in: &self)
                case .finishBindingDomain(let id):
                    guard let domain = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing refined binding domain")
                    }
                    let refined = try element(domain)
                    bindings[id] = refined
                    activeBindingRefinements.remove(id)
                    results.append(refined)
                    try finish(.init(type: refined, computationType: refined), in: &self)
                case .bind(let id):
                    guard let type = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked binding type")
                    }
                    bindings[id] = type
                case .bindDomain(let id, let retainElement):
                    guard let domain = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked binding domain")
                    }
                    let item = try element(domain)
                    bindings[id] = item
                    if retainElement { results.append(item) }
                case .finishUnaryCollection(let expected):
                    guard let source = results.popLast(), let expression = ancestors.last else {
                        throw CompiledValueType.diagnostic("checking", "missing checked collection operand")
                    }
                    let result: CompiledValueType
                    switch expression.operation {
                    case .cardinality: result = .int
                    case .powerSet: result = .set(source)
                    case .unionAll: result = try element(source)
                    case .sequenceFromSet: result = .array(try element(source))
                    default: throw CompiledValueType.diagnostic("checking", "unexpected collection operation")
                    }
                    let checked = try checkedType(result, expected: expected, operandContexts: [source])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .finishFunctionSet(let expected):
                    guard let range = results.popLast(), let domain = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked function-set operands")
                    }
                    let result = CompiledValueType.set(.dictionary(try element(domain), try element(range)))
                    let checked = try checkedType(result, expected: expected, operandContexts: [domain, range])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .refineDomain(let domain, let id):
                    pending.append(contentsOf: [.retainOperand(0), .check(domain, expected: .set(bindings[id] ?? .unknown))])
                case .finishSetPredicate(let choosing):
                    guard let domain = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked predicate domain")
                    }
                    let result = choosing ? try element(domain) : domain
                    // Preserve nominal refinements established by the predicate.
                    results.append(result)
                    try finish(.init(type: result, computationType: result, operandContexts: [domain, .bool]), in: &self)
                case .set:
                    guard let item = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked set element")
                    }
                    results.append(.set(item))
                case .setElements(var remaining, let element):
                    if let next = remaining.popFirst() {
                        pending.append(contentsOf: [
                            .mergeSetElement(remaining, previous: element),
                            .retainOperand(remaining.startIndex - 1), .check(next, expected: element),
                        ])
                    } else {
                        results.append(.set(element))
                    }
                case .mergeSetElement(let remaining, let previous):
                    guard let item = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked set member")
                    }
                    let element = try CompiledValueType.merge(previous, item)
                    pending.append(.setElements(remaining, element: element))
                case .dictionary:
                    guard let value = results.popLast(), let key = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked function operands")
                    }
                    results.append(.dictionary(key, value))
                case .reconcile(let yes, let no, let expected):
                    guard let right = results.popLast(), let left = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked branch types")
                    }
                    let context = try Self.operandContext(left, right)
                    let offset: Int = if case .ifThenElse = ancestors.last?.operation { 1 } else { 0 }
                    pending.append(.result(context))
                    // Recheck only branches whose context changed, preserving
                    // the same left-to-right order as initial branch checking.
                    if context != expected {
                        if right != context {
                            pending.append(contentsOf: [
                                .discard,
                                .retainOperand(offset + 1), .check(no, expected: context),
                            ])
                        }
                        if left != context {
                            pending.append(contentsOf: [
                                .discard,
                                .retainOperand(offset), .check(yes, expected: context),
                            ])
                        }
                    }
                case .setOperands(let lhs, let rhs, let expected):
                    guard let compared = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked set operand types")
                    }
                    let context = try Self.operandContext(compared, expected)
                    _ = try element(context)
                    if context == compared {
                        results.append(context)
                        continue
                    }
                    pending.append(contentsOf: [
                        .retainOperand(1), .check(rhs, expected: context),
                        .discard, .retainOperand(0), .check(lhs, expected: context),
                    ])
                case .comparison(let expected), .subset(let expected):
                    guard let context = results.popLast() else {
                        throw CompiledValueType.diagnostic("checking", "missing checked comparison operands")
                    }
                    if case .subset = task { _ = try element(context) }
                    let checked = try checkedType(.bool, expected: expected, operandContexts: [context, context])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .finish(let expected):
                    guard let result = results.popLast(), let expression = ancestors.last else {
                        throw CompiledValueType.diagnostic("checking", "missing checked expression type")
                    }
                    let checked = try finishExpression(expression, result: result, expected: expected)
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .boundValue(let id, let check, let expected):
                    ancestors.append(.boundValue(id))
                    operandFrames.append([:])
                    switch check {
                    case .checked(let checked):
                        results.append(checked.type)
                        try finish(checked, in: &self)
                    case .argument(let source, let refinement):
                        activeArgumentRefinements.insert(refinement)
                        suspendedScopes.append(self)
                        var caller = source.scope
                        caller.activeArgumentRefinements = activeArgumentRefinements
                        caller.activeOperators = activeOperators
                        caller.specializationResults.merge(specializationResults) { _, current in current }
                        self = caller
                        pending.append(contentsOf: [
                            .finishArgument(id, refinement),
                            .check(source.expression, expected: expected),
                        ])
                    case .domain(let domain):
                        activeBindingRefinements.insert(id)
                        pending.append(contentsOf: [
                            .finishBindingDomain(id),
                            .check(domain, expected: .set(expected)),
                        ])
                    }
                case .recordContext(let expected):
                    guard let expression = ancestors.last, case .recordAccess(let name) = expression.operation, let source = operandFrames.last?[0] else {
                        throw CompiledValueType.diagnostic("recordAccess", "missing checked record source")
                    }
                    pending.append(.finishRecordAccess(expected: expected))
                    if source.resultType == .unknown { continue }
                    guard case .record(var fields) = source.resultType,
                          let index = fields.firstIndex(where: { $0.name == name }) else {
                        throw CompiledValueType.diagnostic("recordAccess", "unknown record field")
                    }
                    fields[index] = .init(name: name, type: try projectionStorageType(fields[index].type, expected: expected))
                    let context = CompiledValueType.record(fields)
                    if source.resultType != context {
                        pending.append(contentsOf: [.discard, .retainOperand(0), .check(expression.children[0], expected: context)])
                    }
                case .finishRecordAccess(let expected):
                    guard let expression = ancestors.last, case .recordAccess(let name) = expression.operation, let source = operandFrames.last?[0] else {
                        throw CompiledValueType.diagnostic("recordAccess", "missing checked record source")
                    }
                    let result: CompiledValueType
                    if case .record(let fields) = source.resultType,
                       let field = fields.first(where: { $0.name == name }) { result = field.type }
                    else { result = .unknown }
                    let checked = try checkedType(result, expected: expected, operandContexts: [source.resultType])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .finishSequenceOperation(let expected):
                    guard let expression = ancestors.last, let operands = operandFrames.last, let source = operands[0] else {
                        throw CompiledValueType.diagnostic("sequence", "missing checked sequence source")
                    }
                    let result: CompiledValueType
                    switch expression.operation {
                    case .tupleLength: result = .int
                    case .tupleHead, .tupleDynamicAccess: result = try sequenceElementType(source.resultType)
                    case .tupleTail, .tupleRemoving: result = try .array(sequenceElementType(source.resultType))
                    default: throw CompiledValueType.diagnostic("sequence", "unexpected sequence operation")
                    }
                    let operandContexts = operands.sorted { $0.key < $1.key }.map { $0.value.resultType }
                    let checked = try checkedType(result, expected: expected, operandContexts: operandContexts)
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .applicationKey(let expected):
                    guard case .functionApply = ancestors.last?.operation, let key = ancestors.last?.children[1], let source = operandFrames.last?[0] else {
                        throw CompiledValueType.diagnostic("function", "missing checked application source")
                    }
                    let keyType: CompiledValueType
                    switch source.resultType {
                    case .unknown:
                        pending.append(contentsOf: [.applicationSource(expected: expected), .check(key, expected: .unknown)])
                        continue
                    case .dictionary(let domain, _): keyType = domain
                    case .array, .tuple: keyType = .int
                    case .record: keyType = .string
                    default: throw CompiledValueType.diagnostic("function", "expected a native dictionary, sequence, or record")
                    }
                    pending.append(contentsOf: [.finishApplication(expected: expected), .discard, .retainOperand(1), .check(key, expected: keyType)])
                case .applicationSource(let expected):
                    guard case .functionApply = ancestors.last?.operation, let source = ancestors.last?.children[0], let keyType = results.popLast() else {
                        throw CompiledValueType.diagnostic("function", "missing inferred application domain")
                    }
                    pending.append(contentsOf: [
                        .applicationKey(expected: expected), .discard, .retainOperand(0),
                        .check(source, expected: .dictionary(keyType, expected))
                    ])
                case .finishApplication(let expected):
                    guard case .functionApply = ancestors.last?.operation, let key = ancestors.last?.children[1],
                          let operands = operandFrames.last, let source = operands[0], let checkedKey = operands[1] else {
                        throw CompiledValueType.diagnostic("function", "missing checked application operands")
                    }
                    let result: CompiledValueType
                    var sourceType = source.resultType
                    switch source.resultType {
                    case .dictionary(let domain, let value):
                        result = try Self.operandContext(value, expected)
                        sourceType = .dictionary(domain, result)
                    case .array(let value):
                        result = try Self.operandContext(value, expected)
                        sourceType = .array(result)
                    case .tuple(let elements):
                        if case .value(.integer(let index)) = key.operation, index >= 1, index <= elements.count {
                            var hints = elements
                            hints[index - 1] = try Self.operandContext(elements[index - 1], expected)
                            sourceType = .tuple(hints)
                            result = hints[index - 1]
                        } else if case .value(.integer) = key.operation, expected != .unknown {
                            result = expected
                        } else {
                            result = try elements.reduce(expected, CompiledValueType.merge)
                            sourceType = .tuple(elements.map { _ in result })
                        }
                    case .record(let fields):
                        if case .value(.string(let name)) = key.operation {
                            if let selected = fields.first(where: { $0.name == name }) {
                                result = try Self.operandContext(selected.type, expected)
                                sourceType = .record(fields.map { .init(name: $0.name, type: $0.name == name ? result : $0.type) })
                            } else { result = expected }
                        } else {
                            result = try fields.map(\.type).reduce(expected, CompiledValueType.merge)
                            sourceType = .record(fields.map { .init(name: $0.name, type: result) })
                        }
                    default: throw CompiledValueType.diagnostic("function", "expected a native dictionary, sequence, or record")
                    }
                    let checked = try checkedType(result, expected: expected, operandContexts: [sourceType, checkedKey.resultType])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .updateKey(let expected):
                    guard case .except = ancestors.last?.operation, let key = ancestors.last?.children[1], let source = operandFrames.last?[0] else {
                        throw CompiledValueType.diagnostic("except", "missing checked update source")
                    }
                    let keyType: CompiledValueType
                    switch source.resultType {
                    case .array: keyType = .int
                    case .dictionary(let domain, _): keyType = domain
                    case .record: keyType = .string
                    case .unknown: keyType = .unknown
                    default: throw CompiledValueType.diagnostic("except", "unsupported update shape \(source.resultType.swiftType)")
                    }
                    pending.append(contentsOf: [.updateValue(expected: expected), .discard, .retainOperand(1), .check(key, expected: keyType)])
                case .updateValue(let expected):
                    guard case .except = ancestors.last?.operation, let key = ancestors.last?.children[1], let value = ancestors.last?.children[2], let source = operandFrames.last?[0] else {
                        throw CompiledValueType.diagnostic("except", "missing checked update key")
                    }
                    let valueType: CompiledValueType
                    switch source.resultType {
                    case .array(let item), .dictionary(_, let item): valueType = item
                    case .record(let fields):
                        if case .value(.string(let name)) = key.operation {
                            valueType = fields.first { $0.name == name }?.type ?? .unknown
                        } else {
                            let item = fields.first?.type ?? .unknown
                            guard fields.allSatisfy({ $0.type == item }) else {
                                throw CompiledValueType.diagnostic("except", "dynamic record keys require homogeneous field types")
                            }
                            valueType = item
                        }
                    case .unknown: valueType = .unknown
                    default: throw CompiledValueType.diagnostic("except", "unsupported update shape \(source.resultType.swiftType)")
                    }
                    pending.append(contentsOf: [.finishUpdate(expected: expected), .discard, .retainOperand(2), .check(value, expected: valueType)])
                case .finishUpdate(let expected):
                    guard let operands = operandFrames.last,
                          let source = operands[0], let key = operands[1], let value = operands[2] else {
                        throw CompiledValueType.diagnostic("except", "missing checked update operands")
                    }
                    let result: CompiledValueType
                    switch source.resultType {
                    case .array: result = .array(value.resultType)
                    case .dictionary(let domain, _): result = .dictionary(domain, value.resultType)
                    case .record: result = source.resultType
                    case .unknown: result = .dictionary(key.resultType, value.resultType)
                    default: throw CompiledValueType.diagnostic("except", "unsupported update shape \(source.resultType.swiftType)")
                    }
                    let checked = try checkedType(result, expected: expected)
                    results.append(checked.type)
                    try finish(.init(type: checked.type, computationType: checked.computationType,
                        operandContexts: [checked.computationType, key.resultType, value.resultType]), in: &self)
                case .recordFields(var remaining, let expected):
                    guard let field = remaining.popFirst() else { continue }
                    let hints: [CompiledFieldType] = if case .record(let fields) = expected { fields } else { [] }
                    pending.append(contentsOf: [
                        .recordFields(remaining, expected: expected), .discard,
                        .retainOperand(remaining.startIndex - 1),
                        .check(field.value, expected: hints.first { $0.name == field.name }?.type ?? .unknown)
                    ])
                case .finishRecord(let expected):
                    guard case .recordLiteral(let record) = ancestors.last?.operation, let operands = operandFrames.last else {
                        throw CompiledValueType.diagnostic("record", "missing checked record")
                    }
                    let fields = try record.enumerated().map { index, name -> CompiledFieldType in
                        guard let child = operands[index] else {
                            throw CompiledValueType.diagnostic("record", "missing checked field")
                        }
                        return .init(name: name, type: child.resultType)
                    }
                    let operandContexts = fields.map(\.type)
                    let checked = try checkedType(.record(fields.sorted { $0.name < $1.name }), expected: expected, operandContexts: operandContexts)
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .sequenceContext(let element, let expression):
                    guard let type = results.popLast() else {
                        throw CompiledValueType.diagnostic("sequence", "missing checked sequence")
                    }
                    if case .tupleLength = ancestors.last?.operation, case .tuple = type {
                        results.append(type)
                        continue
                    }
                    let context = try sequenceContext(type, element: element)
                    if type == context { results.append(type) }
                    else { pending.append(.check(expression, expected: context)) }
                case .sequenceValue(let value, let expected):
                    guard let source = results.last, let expression = ancestors.last else {
                        throw CompiledValueType.diagnostic("sequence", "missing checked construction source")
                    }
                    let element = try sequenceElementType(source)
                    pending.append(contentsOf: [.finishSequenceConstruction(expected: expected), .retainOperand(1)])
                    if case .tupleConcatenate = expression.operation {
                        pending.append(contentsOf: [.sequenceContext(element: element, source: value), .check(value, expected: .unknown)])
                    } else {
                        pending.append(.check(value, expected: element))
                    }
                case .finishSequenceConstruction(let expected):
                    guard let value = results.popLast(), let source = results.popLast(), let expression = ancestors.last else {
                        throw CompiledValueType.diagnostic("sequence", "missing checked construction operands")
                    }
                    let valueElement: CompiledValueType
                    if case .tupleConcatenate = expression.operation { valueElement = try sequenceElementType(value) }
                    else { valueElement = value }
                    let element = try CompiledValueType.merge(sequenceElementType(source), valueElement)
                    let valueContext: CompiledValueType
                    if case .tupleConcatenate = expression.operation { valueContext = try sequenceContext(value, element: element) }
                    else { valueContext = element }
                    let checked = try checkedType(.array(element), expected: expected,
                        operandContexts: [sequenceContext(source, element: element), valueContext])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .completeOccurrence(let annotation):
                    try finish(annotation, in: &self, refineOperands: false)
                case .result(let type):
                    results.append(type)
                case .retainOperand(let index):
                    guard let completed, !operandFrames.isEmpty else {
                        throw CompiledValueType.diagnostic("checking", "missing checked operand")
                    }
                    operandFrames[operandFrames.count - 1][index] = completed
                case .discard:
                    _ = results.popLast()
                }
            }
        } catch {
            while let caller = suspendedScopes.popLast() { self = caller }
            activeArgumentRefinements = initialArgumentRefinements
            activeBindingRefinements = initialBindingRefinements
            if let diagnostic = error as? CompilationDiagnostic {
                throw ancestors.reversed().reduce(diagnostic) { annotated($0, at: $1) }
            }
            throw error
        }
        guard let completed else {
            throw CompiledValueType.diagnostic("checking", "missing checked expression")
        }
        return completed
    }

    private func finishExpression(
        _ expression: CompiledExpression, result: CompiledValueType, expected: CompiledValueType
    ) throws -> CheckedType {
        let checked = try checkedType(result, expected: expected)
        let type = checked.computationType
        let operands: [CompiledValueType]
        switch expression.operation {
        case .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .integerRange:
            operands = [.int, .int]
        case .negate: operands = [.int]
        case .and, .or: operands = [.bool, .bool]
        case .not: operands = [.bool]
        case .ifThenElse: operands = [.bool, type, type]
        case .union, .intersection, .setDifference: operands = [type, type]
        case .setLiteral:
            let values = expression.children

            operands = Array(repeating: try element(type), count: values.count)
        case .letValue(let id): operands = [bindings[id] ?? .unknown, type]
        case .letIn: operands = [type]
        case .functionLiteral:
            guard case .dictionary(let key, let value) = type else {
                throw CompiledValueType.diagnostic("function", "expected dictionary representation")
            }
            operands = [.set(key), value]
        case .setMap(let id):
            operands = [try element(type), .set(bindings[id] ?? .unknown)]
        case .forAll(let id), .exists(let id):
            operands = [.set(bindings[id] ?? .unknown), .bool]
        default:
            throw CompiledValueType.diagnostic("checking", "missing operand types for \(expression.diagnosticName)")
        }
        return .init(type: checked.type, computationType: type, operandContexts: operands)
    }

    private mutating func inferCases(_ first: CompiledCaseBranch, rest: [CompiledCaseBranch], otherwise: CompiledExpression?, expected: CompiledValueType) throws -> CheckedType {
        var type = expected
        var children: [CompiledExpression] = []
        for branch in [first] + rest {
            children.append(try checkOperand(branch.condition, expected: .bool))
            let value = try checkOperand(branch.value, expected: type)
            children.append(value)
            type = value.resultType
        }
        if let otherwise {
            let value = try checkOperand(otherwise, expected: type)
            children.append(value)
            type = value.resultType
        }
        let checked = try checkedType(type, expected: expected)
        let operands = ([first] + rest).flatMap { _ in [CompiledValueType.bool, checked.computationType] }
            + (otherwise == nil ? [] : [checked.computationType])
        let expressions = ([first] + rest).flatMap { [$0.condition, $0.value] } + (otherwise.map { [$0] } ?? [])
        return try retaining(children, from: expressions, in: .init(type: checked.type, computationType: checked.computationType, operandContexts: operands))
    }

    private mutating func inferResolved(_ expression: CompiledExpression, expected: CompiledValueType = .unknown) throws -> CheckedType {
        if case .union = expected, let checked = try checkUnionConstructor(expression, expected: expected) {
            return checked
        }
        let result: CompiledValueType
        switch expression.operation {
        case .assertView(let shape):
            let value = expression.children[0]

            let source = try checkOperand(value)
            result = try inputs.types.resolve(shape)
            return try checkedType(result, expected: expected, children: [source])
        case .value(let value):
            let type = try literal(value, expected: expected)
            return .init(type: type, computationType: type)
        case .stateVariable(let id):
            let existing = variables[id] ?? .unknown
            if inputs.types.canProjectRead(existing, to: expected) { return .init(type: expected, computationType: existing) }
            else { result = try CompiledValueType.merge(existing, expected); variables[id] = result }
        case .controlLocation: result = .control
        case .enabledAction: result = .bool
        case .in:
            let value = expression.children[0]
            let domain = expression.children[1]

            return try checkMembership(value: value, domain: domain, expected: expected)
        case .sequenceSelect(let id):
            let sequence = expression.children[0]
            let predicate = expression.children[1]

            return try inferSequenceSelection(sequence, binder: id, predicate: predicate, expected: expected)
        case .setSum:
            let function = expression.children[0]
            let domain = expression.children[1]

            let source = try checkOperand(domain, expected: .set(.unknown))
            let key = try element(source.resultType)
            let operation = try checkOperand(function, expected: .dictionary(key, .int))
            return try checkedType(.int, expected: expected, children: [operation, source])
        case .foldFunction(let parameters):
            let body = expression.children[0]
            let initial = expression.children[1]
            let sequence = expression.children[2]

            return try inferFold(parameters: parameters, body: body, initial: initial, sequence: sequence, expected: expected)
        case .tupleLiteral:
            let expressions = expression.children
             return try inferTupleLiteral(expressions, expected: expected)
        case .tupleAccess(let index):
            let value = expression.children[0]

            return try inferTupleAccess(value, index: index, expected: expected)
        case .domain:
            let function = expression.children[0]

            return try inferDomain(function, expected: expected)
        case .caseExpr(let hasOtherwise):
            let branches = stride(from: 0, to: expression.children.count - (hasOtherwise ? 1 : 0), by: 2).map { CompiledCaseBranch(condition: expression.children[$0], value: expression.children[$0 + 1]) }
            let first = branches[0]
            let rest = Array(branches.dropFirst())
            let otherwise = hasOtherwise ? expression.children.last : nil

            return try inferCases(first, rest: rest, otherwise: otherwise, expected: expected)
        default: throw CompiledValueType.diagnostic("expression", "expression is outside the native machine subset: \(expression.diagnosticName)")
        }
        return try checkedType(result, expected: expected)
    }
}
