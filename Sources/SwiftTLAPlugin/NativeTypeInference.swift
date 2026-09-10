import SwiftTLA
import Foundation
import SwiftSyntax

/// Swift source declarations that supply type evidence absent from formal values.
/// This is consumed by the shared compiler inference pass, never at runtime.
package struct NativeSourceRecordField: Sendable {
    package let sourceName: String
    package let name: String
    package let swiftType: String
    package init(sourceName: String, name: String, swiftType: String) {
        self.sourceName = sourceName; self.name = name; self.swiftType = swiftType
    }
}

package struct NativeSourceTypeMetadata: Sendable {
    package let aliases: [String: String]
    package let records: [String: [NativeSourceRecordField]]
    package let enums: [String: [TLAValue]]
    package let finiteViewDomains: [String: [TLAValue]]
    package init(aliases: [String: String] = [:], records: [String: [NativeSourceRecordField]] = [:], enums: [String: [TLAValue]] = [:], finiteViewDomains: [String: [TLAValue]] = [:]) {
        self.aliases = aliases; self.records = records; self.enums = enums
        self.finiteViewDomains = finiteViewDomains
    }
}

extension NativeSourceTypeMetadata {
    package func formalShape(for swiftType: String) throws -> FormalValueShape {
        try shape(NativeTypeInference.declared(swiftType, metadata: self, forView: true))
    }

    private func shape(_ type: NativeType) throws -> FormalValueShape {
        switch type {
        case .int: return .integer
        case .bool: return .boolean
        case .string: return .string
        case .named(let name):
            guard let values = finiteViewDomains[name] else { return .unsupported(name) }
            return .finite(typeName: TokenSyntax.identifier(name).sourceIdentifierName, values: values)
        case .finite(let members):
            let values = try members.map { member -> TLAValue in
                switch member {
                case .integer(let value): return .int(value)
                case .boolean(let value): return .bool(value)
                case .string(let value): return .string(value)
                case .constant(let value): return .constant(value)
                default: throw NativeTypeInference.diagnostic("view", "finite view requires scalar members")
                }
            }
            return .finite(typeName: "", values: values)
        case .set(let item): return .set(try shape(item))
        case .array(let item): return .sequence(try shape(item))
        case .dictionary(let key, let item): return .function(key: try shape(key), value: try shape(item))
        case .tuple(let items): return .tuple(try items.map(shape))
        case .record(let fields): return .record(try fields.map { .init(name: $0.name, shape: try shape($0.type)) })
        case .union(let alternatives):
            let shapes = try alternatives.map(shape)
            return shapes.dropFirst().reduce(shapes[0]) { .union($0, $1) }
        default: return .unsupported(type.swiftType)
        }
    }
}

/// A compile-time function instance. No specialization metadata enters a machine.
struct NativeOperatorSpecialization: Hashable, Sendable {
    let operation: CompiledOperatorIdentity
    let arguments: [NativeType]
    let resultContext: NativeType
    let captures: [BinderID: NativeType]
    let callbacks: [OperatorID: NativeCallbackIdentity]
}

struct NativeCallbackIdentity: Hashable, Sendable {
    let operation: CompiledOperatorIdentity
    let captures: [BinderID: NativeType]
    let callbacks: [OperatorID: NativeCallbackIdentity]
    fileprivate func strictlyContains(_ other: NativeCallbackIdentity) -> Bool {
        self != other && callbacks.values.contains { $0 == other || $0.strictlyContains(other) }
    }

}

private struct NativeCallbackBinding: Sendable {
    let operation: CompiledFormalOperator
    let scope: NativeTypeInference
    let forwardedFrom: OperatorID?
    let identity: NativeCallbackIdentity

    init(operation: CompiledFormalOperator, scope: NativeTypeInference) {
        self.operation = operation
        self.scope = scope
        forwardedFrom = nil
        let captures = scope.captures(of: operation)
        identity = .init(operation: operation.identity, captures: captures.bindings, callbacks: captures.callbacks)
    }

    init(forwarding binding: NativeCallbackBinding, from origin: OperatorID) {
        operation = binding.operation
        scope = binding.scope
        forwardedFrom = origin
        identity = binding.identity
    }
}

private struct NativeArgumentSource: Sendable {
    let expression: CompiledStateExpr
    let scope: NativeTypeInference
}

/// A checked call argument retains its type and lexical source together.
private enum NativeCallArgument: Sendable {
    case value(type: NativeType, domain: Set<CompiledValue>?, source: NativeArgumentSource)
    case `operator`(NativeCallbackBinding)
}

private struct NativeArgumentRefinement: Hashable, Sendable {
    let expression: CompiledStateExpr
    let bindings: [BinderID: NativeType]
    let expected: NativeType
}

enum NativeOperatorImplementation: Sendable {
    case checked(body: NativeCheckedExpression, domainGuard: NativeCheckedExpression?)
    case recursive
}

final class NativeOperatorCall: Sendable {
    let specialization: NativeOperatorSpecialization
    let parameters: [BinderID]
    let implementation: NativeOperatorImplementation
    let result: NativeType
    fileprivate let refinedBindings: [BinderID: NativeType]
    fileprivate let boundOperators: [OperatorID: NativeCallbackBinding]
    let callbackUses: [OperatorID: [NativeOperatorCall]]
    let callbackArguments: [OperatorID: CompiledFormalOperator]

    fileprivate init(specialization: NativeOperatorSpecialization, parameters: [BinderID],
         implementation: NativeOperatorImplementation, result: NativeType,
         bindings: [BinderID: NativeType], boundOperators: [OperatorID: NativeCallbackBinding],
         callbackUses: [OperatorID: [NativeOperatorCall]],
         callbackArguments: [OperatorID: CompiledFormalOperator]) {
        self.specialization = .init(operation: specialization.operation,
            arguments: parameters.map { bindings[$0] ?? .unknown }, resultContext: result,
            captures: specialization.captures, callbacks: specialization.callbacks)
        self.parameters = parameters
        self.implementation = implementation
        self.result = result
        refinedBindings = bindings
        self.boundOperators = boundOperators
        self.callbackUses = callbackUses
        self.callbackArguments = callbackArguments
    }
}

/// Checking retains the representation before an implicit use-site conversion.
struct NativeCheckedType: Sendable {
    let type: NativeType
    let computationType: NativeType
    /// Context selected while checking operands, in expression order.
    let operandTypes: [NativeType]
    let call: NativeOperatorCall?
    var children: [NativeCheckedExpression] = []

    init(type: NativeType, computationType: NativeType, operandTypes: [NativeType] = [], call: NativeOperatorCall? = nil, children: [NativeCheckedExpression] = []) {
        self.type = type
        self.computationType = computationType
        self.operandTypes = operandTypes
        self.call = call
        self.children = children
    }
}

/// The finished occurrence owns its types; operand types belong to its children.
final class NativeCheckedExpression: Hashable, Sendable {
    let expression: CompiledStateExpr
    let operatorParameters: Set<OperatorID>
    let resultType: NativeType
    let computationType: NativeType
    let call: NativeOperatorCall?
    let children: [NativeCheckedExpression]

    init(expression: CompiledStateExpr, operatorParameters: Set<OperatorID>, resultType: NativeType,
         computationType: NativeType, call: NativeOperatorCall?, children: [NativeCheckedExpression]) {
        self.expression = expression
        self.operatorParameters = operatorParameters
        self.resultType = resultType
        self.computationType = computationType
        self.call = call
        self.children = children
    }

    static func == (lhs: NativeCheckedExpression, rhs: NativeCheckedExpression) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

}

private struct NativeOperatorBody {
    let specialization: NativeOperatorSpecialization
    let parameters: [BinderID]
    let body: CompiledStateExpr
    let domain: CompiledStateExpr?
    let context: NativeType
    let callbackArguments: [OperatorID: CompiledFormalOperator]
}

private enum NativeOperatorCheck {
    case recursive(NativeOperatorCall)
    case body(NativeOperatorBody)
}

private struct NativePendingCall {
    let expression: CompiledStateExpr
    let operation: CompiledFormalOperator
    let arguments: [CompiledFormalCallArgument]
    let checkedArguments: [NativeCallArgument]
    let callbackID: OperatorID?
    let expected: NativeType
}

private enum NativeBoundValueCheck {
    case checked(NativeCheckedType)
    case argument(NativeArgumentSource, NativeArgumentRefinement)
    case domain(CompiledStateExpr)
}

private enum NativeExpressionCheckTask {
    case check(CompiledStateExpr, expected: NativeType)
    case boundValue(BinderID, NativeBoundValueCheck, expected: NativeType)
    case call(CompiledStateExpr, CompiledFormalOperator, [CompiledFormalCallArgument], expected: NativeType)
    case enterCall(CompiledStateExpr, CompiledFormalOperator, [CompiledFormalCallArgument], expected: NativeType)
    case finishOperator(NativeOperatorBody)
    case leaveCall(NativePendingCall)
    case refineCallCaptures(CompiledFormalOperator, NativeOperatorCall)
    case refineCapture(BinderID, original: NativeType, refined: NativeType)
    case forwardCallbacks(NativeOperatorCall)
    case completeCall(CompiledStateExpr, NativeOperatorCall, expected: NativeType)
    case reconcile(CompiledStateExpr, CompiledStateExpr, expected: NativeType)
    case finish(expected: NativeType)
    case completeOccurrence(NativeCheckedType)
    case recordFields(ArraySlice<CompiledRecordExpression.Field>, expected: NativeType)
    case finishRecord(expected: NativeType)
    case updateKey(expected: NativeType)
    case updateValue(expected: NativeType)
    case finishUpdate(expected: NativeType)
    case applicationKey(expected: NativeType)
    case applicationSource(expected: NativeType)
    case finishApplication(expected: NativeType)
    case recordContext(expected: NativeType)
    case finishRecordAccess(expected: NativeType)
    case finishSequenceOperation(expected: NativeType)
    case sequenceContext(element: NativeType)
    case sequenceValue(CompiledStateExpr, expected: NativeType)
    case finishSequenceConstruction(expected: NativeType)
    case comparison(expected: NativeType)
    case subset(expected: NativeType)
    case setOperands(CompiledStateExpr, CompiledStateExpr, expected: NativeType)
    case bind(BinderID)
    case finishArgument(BinderID, NativeArgumentRefinement)
    case finishBindingDomain(BinderID)
    case bindDomain(BinderID, retainElement: Bool)
    case refineDomain(CompiledStateExpr, BinderID)
    case finishSetPredicate(choosing: Bool)
    case finishUnaryCollection(expected: NativeType)
    case finishFunctionSet(expected: NativeType)
    case set
    case setElements(ArraySlice<CompiledStateExpr>, element: NativeType)
    case mergeSetElement(ArraySlice<CompiledStateExpr>, previous: NativeType)
    case dictionary
    case result(NativeType)
    case discard
    case retainOperand(Int)
}

/// Derives native shapes from the resolved formal program and source hints.
/// Empty collection holes are refined by assignments before admission completes.
struct NativeTypeInference: Sendable {
    /// Shared immutable inputs stay outside lexical scope snapshots.
    private final class Inputs: Sendable {
        let compilation: CompiledSpecification
        let sourceTypes: NativeSourceTypeMetadata
        let namedDomains: [String: Set<CompiledValue>]
        let namedRepresentations: [String: NativeType]

        init(compilation: CompiledSpecification, sourceTypes: NativeSourceTypeMetadata) throws {
            self.compilation = compilation
            self.sourceTypes = sourceTypes
            var namedDomains: [String: Set<CompiledValue>] = [:]
            var namedRepresentations: [String: NativeType] = [:]
            for (name, values) in sourceTypes.enums {
                namedDomains[name] = Set(values.map(CompiledValue.init(formal:)))
                let represented = values.map { value -> NativeType in
                    switch value {
                    case .int: return .int
                    case .bool: return .bool
                    case .string: return .string
                    case .constant: return .atom
                    default: return .unknown
                    }
                }
                namedRepresentations[name] = try represented.reduce(.unknown, NativeTypeInference.merge)
            }
            self.namedDomains = namedDomains
            self.namedRepresentations = namedRepresentations
        }
    }

    static let maximumActiveSpecializations = 256

    private(set) var initializations: [(variable: VariableID, expression: NativeCheckedExpression)] = []
    private(set) var actions: [(id: ActionID, body: CompiledActionExpr<NativeCheckedExpression>)] = []
    private(set) var invariants: [(id: PropertyID, expression: NativeCheckedExpression)] = []
    private(set) var constraint: NativeCheckedExpression?
    private(set) var assume: NativeCheckedExpression?
    private(set) var variables: [VariableID: NativeType] = [:]
    private(set) var bindings: [BinderID: NativeType] = [:]
    private(set) var collectionDomains: [VariableID: Set<CompiledValue>] = [:]
    private let inputs: Inputs
    var namedDomains: [String: Set<CompiledValue>] { inputs.namedDomains }
    var namedRepresentations: [String: NativeType] { inputs.namedRepresentations }
    private var sourceTypes: NativeSourceTypeMetadata { inputs.sourceTypes }
    private var compilation: CompiledSpecification { inputs.compilation }
    private var bindingSources: [BinderID: CompiledStateExpr] = [:]
    private var argumentSources: [BinderID: NativeArgumentSource] = [:]
    private var activeArgumentRefinements: Set<NativeArgumentRefinement> = []
    private var activeBindingRefinements: Set<BinderID> = []
    private var bindingDomains: [BinderID: Set<CompiledValue>] = [:]
    private var localOperators: [OperatorID: CompiledLocalOperator] = [:]
    private var specializationResults: [NativeOperatorSpecialization: NativeType] = [:]
    private var activeOperators: Set<NativeOperatorSpecialization> = []
    private var localCaptures: [OperatorID: [BinderID: NativeType]] = [:]
    private var boundOperators: [OperatorID: NativeCallbackBinding] = [:]
    private var callbackUses: [OperatorID: [NativeOperatorCall]] = [:]
    fileprivate func captures(of operation: CompiledFormalOperator) -> (
        bindings: [BinderID: NativeType], callbacks: [OperatorID: NativeCallbackIdentity]
    ) {
        var values: [BinderID: NativeType]
        var pending: [OperatorID]
        switch operation {
        case .lambda(let lambda):
            values = bindings.filter { lambda.capturedBindings.contains($0.key) }
            pending = Array(lambda.referencedOperators)
        case .reference(let id, _):
            values = localCaptures[id] ?? [:]
            pending = [id]
        }
        var callbacks: [OperatorID: NativeCallbackIdentity] = [:]
        var visited: Set<OperatorID> = []
        while let id = pending.popLast() {
            guard visited.insert(id).inserted else { continue }
            if let callback = boundOperators[id] { callbacks[id] = callback.identity }
            if let local = localOperators[id] {
                values.merge(localCaptures[id] ?? [:]) { current, _ in current }
                pending.append(contentsOf: local.referencedOperators)
            }
        }
        return (values, callbacks)
    }


    private mutating func recordCallback(_ id: OperatorID, call: NativeOperatorCall) {
        if !(callbackUses[id] ?? []).contains(where: { existing in
            existing.result == call.result && existing.specialization.arguments == call.specialization.arguments
        }) {
            callbackUses[id, default: []].append(call)
        }
    }

    init(compilation: CompiledSpecification, sourceTypes: NativeSourceTypeMetadata = .init()) throws {
        inputs = try Inputs(compilation: compilation, sourceTypes: sourceTypes)
        for variable in compilation.layout.variables {
            if let collection = variable.collection,
               let element = collection.elementType, let value = collection.valueType {
                collectionDomains[variable.id] = Set(collection.members)
                variables[variable.id] = .dictionary(.collectionMember(variable.id, swiftType: "\(element).ID"), try Self.declared(value, metadata: sourceTypes))
            } else if let hint = variable.generatedSwiftType {
                variables[variable.id] = try Self.declared(hint, metadata: sourceTypes)
            } else {
                variables[variable.id] = .unknown
            }
        }
        for action in compilation.semantics.actions {
            let collection = action.collection.flatMap { id in compilation.layout.variables.first { $0.id == id }?.collection }
            for binding in action.bindings {
                let hint: NativeType
                if let variable = action.collection, let element = collection?.elementType {
                    hint = .collectionMember(variable, swiftType: "\(element).ID")
                } else { hint = try binding.generatedSwiftType.map { try Self.declared($0, metadata: sourceTypes) } ?? .unknown }
                let inferred = try binding.values.reduce(hint) { try Self.merge($0, literal($1, expected: hint)) }
                bindingDomains[binding.binder] = Set(binding.values)
                bindings[binding.binder] = try Self.merge(bindings[binding.binder] ?? .unknown, inferred)
            }
        }
        // Each pass can refine an unresolved component through another variable
        // or binder; stop at the fixed point rather than imposing a pass budget.
        var initializations: [(variable: VariableID, expression: NativeCheckedExpression)] = []
        var actions: [(id: ActionID, body: CompiledActionExpr<NativeCheckedExpression>)] = []
        var invariants: [(id: PropertyID, expression: NativeCheckedExpression)] = []
        var constraint: NativeCheckedExpression?
        var assume: NativeCheckedExpression?
        while true {
            initializations.removeAll(keepingCapacity: true)
            actions.removeAll(keepingCapacity: true)
            invariants.removeAll(keepingCapacity: true)
            let previousVariables = variables
            let previousBindings = bindings
            let previousOperators = specializationResults
            for initialization in compilation.semantics.variableInitializations {
                let expected = variables[initialization.variable] ?? .unknown
                let inferred: NativeType
                switch initialization.initialization {
                case .value(let value):
                    let checked = try checkOperand(.value(value), expected: expected)
                    initializations.append((initialization.variable, checked))
                    inferred = checked.resultType
                case .expression(let expression):
                    let checked = try checkOperand(expression, expected: expected)
                    initializations.append((initialization.variable, checked))
                    inferred = checked.resultType
                case .memberOf(let domain):
                    let checked = try checkOperand(domain, expected: .set(expected))
                    initializations.append((initialization.variable, checked))
                    inferred = try element(checked.resultType)
                }
                variables[initialization.variable] = try Self.merge(expected, inferred)
            }
            for action in compilation.semantics.actions {
                do { actions.append((action.id, try checkAction(action.body))) }
                catch let diagnostic as CompilationDiagnostic {
                    let name = compilation.layout.actions.first { $0.id == action.id }?.declaration.name ?? String(action.id.ordinal)
                    throw Self.diagnostic("actions.\(name)", causedBy: diagnostic)
                }
            }
            for invariant in compilation.semantics.invariants {
                do { invariants.append((invariant.id, try checkOperand(invariant.body, expected: .bool))) }
                catch let diagnostic as CompilationDiagnostic {
                    throw Self.diagnostic("invariants.\(invariant.name)", causedBy: diagnostic)
                }
            }
            constraint = try compilation.semantics.constraint.map { try checkOperand($0, expected: .bool) }
            assume = try compilation.semantics.assume.map { try checkOperand($0, expected: .bool) }
            if variables == previousVariables && bindings == previousBindings && specializationResults == previousOperators { break }
        }
        for variable in compilation.layout.variables {
            guard let type = variables[variable.id], type.resolved else {
                throw Self.unresolvedDiagnostic(variables[variable.id] ?? .unknown,
                    at: "variables.\(variable.declaration.name)")
            }
        }
        // Attach roots after convergence so deferred argument and callback scopes
        // do not retain expression graphs from earlier passes.
        self.initializations = initializations
        self.actions = actions
        self.invariants = invariants
        self.constraint = constraint
        self.assume = assume
    }

    private func viewType(_ shape: FormalValueShape) throws -> NativeType {
        switch shape {
        case .integer: return .int
        case .boolean: return .bool
        case .string: return .string
        case .finite(let name, let values):
            let members = Set(values.map(CompiledValue.init(formal:)))
            if let key = namedDomains.keys.first(where: {
                TokenSyntax.identifier($0).sourceIdentifierName == name && namedDomains[$0] == members
            }) { return .named(key) }
            return .finite(members.sorted())
        case .set(let item): return .set(try viewType(item))
        case .sequence(let item): return .array(try viewType(item))
        case .tuple(let items): return .tuple(try items.map(viewType))
        case .function(let key, let value): return .dictionary(try viewType(key), try viewType(value))
        case .record(let fields): return .record(try fields.map { .init(name: $0.name, type: try viewType($0.shape)) }.sorted { $0.name < $1.name })
        case .union(let first, let second): return try Self.normalizedUnion([viewType(first), viewType(second)], metadata: sourceTypes)
        case .unsupported(let name): throw Self.diagnostic("view", "unsupported formal shape " + name)
        }
    }

    private mutating func checkUnionConstructor(_ expression: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType? {
        guard case .union(let alternatives) = expected else { return nil }
        switch expression {
        case .value, .setLiteral, .tupleLiteral, .recordLiteral, .functionLiteral,
             .union, .intersection, .setDifference: break
        default: return nil
        }
        var matches: [(scope: NativeTypeInference, checked: NativeCheckedExpression)] = []
        for alternative in alternatives {
            var candidate = self
            if let checked = try? candidate.checkOperand(expression, expected: alternative) {
                matches.append((candidate, checked))
            }
        }
        guard matches.count == 1, let match = matches.first else {
            throw Self.diagnostic("union", "expression must belong to exactly one declared union alternative")
        }
        self = match.scope
        return .init(type: expected, computationType: match.checked.resultType,
            operandTypes: match.checked.children.map(\.resultType), call: match.checked.call, children: match.checked.children)
    }

    func resolutionScope(_ expression: CompiledStateExpr, expected: NativeType?) throws -> NativeCheckedExpression {
        var scope = self
        let checked = try scope.checkOperand(expression, expected: expected ?? .unknown)
        guard checked.resultType.resolved else {
            throw Self.unresolvedDiagnostic(checked.resultType, at: "resolution")
        }
        guard checked.computationType.resolved else {
            throw Self.unresolvedDiagnostic(checked.computationType, at: "resolution")
        }
        return checked
    }

    private func checkedOccurrence(_ expression: CompiledStateExpr, annotation: NativeCheckedType) -> NativeCheckedExpression {
        .init(expression: expression, operatorParameters: annotation.call == nil ? [] : Set(boundOperators.keys),
            resultType: annotation.type, computationType: annotation.computationType,
            call: annotation.call, children: annotation.children)
    }

    private mutating func refineOperand(_ checked: NativeCheckedExpression, expected: NativeType) throws -> NativeCheckedExpression {
        if checked.resultType == expected { return checked }
        return try checkOperand(checked.expression, expected: expected)
    }

    func type(of expression: CompiledStateExpr, expected: NativeType? = nil) throws -> NativeType {
        var inference = self
        let result = try inference.checkOperand(expression, expected: expected ?? .unknown).resultType
        guard result.resolved else { throw Self.unresolvedDiagnostic(result, at: "expression") }
        return result
    }

    private mutating func checkMembership(value: CompiledStateExpr, domain: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let domain = try checkOperand(domain, expected: .set(.unknown))
        let value = try checkOperand(value)
        let context = try Self.operandContext(element(domain.resultType), value.resultType)
        let children = try [refineOperand(value, expected: context), refineOperand(domain, expected: .set(context))]
        return try checkedType(.bool, expected: expected, children: children)
    }

    /// Selects contextual evidence without admitting a conversion. Both
    /// expressions must subsequently prove that they can inhabit this shape.
    private static func operandContext(_ lhs: NativeType, _ rhs: NativeType) throws -> NativeType {
        switch (lhs, rhs) {
        case (.set(let a), .set(let b)): return .set(try operandContext(a, b))
        case (.array(let a), .array(let b)): return .array(try operandContext(a, b))
        case (.dictionary(let ak, let av), .dictionary(let bk, let bv)):
            return .dictionary(try operandContext(ak, bk), try operandContext(av, bv))
        case (.tuple(let a), .tuple(let b)) where a.count == b.count:
            return .tuple(try zip(a, b).map { try operandContext($0, $1) })
        case (.record(let a), .record(let b)) where a.map(\.name) == b.map(\.name):
            return .record(try zip(a, b).map { .init(name: $0.name, type: try operandContext($0.type, $1.type)) })
        case (.collectionMember, .collectionMember), (.named, .named): return try merge(lhs, rhs)
        case (.collectionMember, _): return lhs
        case (_, .collectionMember): return rhs
        case (.finite, _): return lhs
        case (_, .finite): return rhs
        case (.named, _): return lhs
        case (_, .named): return rhs
        default: return try merge(lhs, rhs)
        }
    }

    private mutating func inferProjectionSource(_ value: CompiledStateExpr, index: Int, expected: NativeType) throws -> NativeCheckedExpression {
        let members: [CompiledStateExpr]?
        switch value {
        case .tupleLiteral(let expressions): members = expressions
        case .value(.tuple(let values)): members = values.map(CompiledStateExpr.value)
        default: members = nil
        }
        if let members {
            guard index >= 1, index <= members.count else { throw Self.diagnostic("tupleAccess", "index outside tuple literal") }
            let children = try members.enumerated().map { offset, member in
                try checkOperand(member, expected: offset == index - 1 ? expected : .unknown)
            }
            let type = NativeType.tuple(children.map(\.resultType))
            // A formal tuple value remains a literal; its components supplied the
            // contextual shape, while expression tuples retain their operands.
            if case .value = value { return try checkOperand(value, expected: type) }
            return checkedOccurrence(value,
                annotation: .init(type: type, computationType: type, operandTypes: children.map(\.resultType), children: children))
        }
        let source = try checkOperand(value)
        if case .tuple(var elements) = source.resultType {
            guard index >= 1, index <= elements.count else { throw Self.diagnostic("tupleAccess", "index outside tuple shape") }
            elements[index - 1] = try projectionStorageType(elements[index - 1], expected: expected)
            return try refineOperand(source, expected: .tuple(elements))
        }
        return try refineSequence(source, element: expected)
    }

    func canProjectRead(_ source: NativeType, to expected: NativeType) -> Bool {
        if source == expected { return true }
        if case .union(let sources) = source { return sources.allSatisfy { canProjectRead($0, to: expected) } }
        if case .union(let targets) = expected { return targets.filter { canProjectRead(source, to: $0) }.count == 1 }

        switch (source, expected) {
        case (.dictionary(let a, let b), .dictionary(let c, let d)):
            return canProjectRead(a, to: c) && canProjectRead(b, to: d)
        case (.array(let a), .array(let b)), (.set(let a), .set(let b)):
            return canProjectRead(a, to: b)
        case (.tuple(let a), .tuple(let b)) where a.count == b.count:
            return zip(a, b).allSatisfy { canProjectRead($0, to: $1) }
        case (.record(let a), .record(let b)) where a.map(\.name) == b.map(\.name):
            return zip(a, b).allSatisfy { canProjectRead($0.type, to: $1.type) }
        default: break
        }
        switch source {
        case .named(let name):
            if expected != .unknown, namedRepresentations[name] == expected { return true }
            if case .finite(let members) = expected, let domain = namedDomains[name] {
                return domain.isSubset(of: Set(members))
            }
        case .finite(let members):
            if case .named(let name) = expected, let domain = namedDomains[name] {
                return !members.isEmpty && Set(members).isSubset(of: domain)
            }
            if case .finite(let destination) = expected {
                return Set(members).isSubset(of: Set(destination))
            }
            guard !members.isEmpty else { return false }
            return members.allSatisfy { member in
                switch (member, expected) {
                case (.integer, .int), (.boolean, .bool), (.string, .string), (.constant, .atom): true
                default: false
                }
            }
        default: break
        }
        return false
    }

    private func checkedType(
        _ source: NativeType, expected: NativeType, operandTypes: [NativeType] = []
    ) throws -> NativeCheckedType {
        if canProjectRead(source, to: expected) {
            return .init(type: expected, computationType: source, operandTypes: operandTypes)
        }
        let type = try Self.merge(source, expected)
        return .init(type: type, computationType: type, operandTypes: operandTypes)
    }

    private func checkedType(_ source: NativeType, expected: NativeType, children: [NativeCheckedExpression]) throws -> NativeCheckedType {
        var checked = try checkedType(source, expected: expected, operandTypes: children.map(\.resultType))
        checked.children = children
        return checked
    }

    private mutating func retaining(_ children: [NativeCheckedExpression], in annotation: NativeCheckedType) throws -> NativeCheckedType {
        guard children.count == annotation.operandTypes.count else {
            throw Self.diagnostic("checking", "missing checked operands")
        }
        var result = annotation
        result.children = try zip(children, annotation.operandTypes).map { try refineOperand($0, expected: $1) }
        return result
    }

    private func projectionStorageType(_ source: NativeType, expected: NativeType) throws -> NativeType {
        if canProjectRead(source, to: expected) { return source }
        return try Self.operandContext(source, expected)
    }

    private mutating func inferDomainSource(_ expression: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedExpression {
        let source = try checkOperand(expression)
        guard case .set(let element) = expected,
              case .dictionary(let key, let value) = source.resultType else { return source }
        let context = try projectionStorageType(key, expected: element)
        guard context != key else { return source }
        return try refineOperand(source, expected: .dictionary(context, value))
    }

    private mutating func inferSequence(_ expression: CompiledStateExpr, element expected: NativeType = .unknown) throws -> NativeCheckedExpression {
        let source = try checkOperand(expression)
        return try refineSequence(source, element: expected)
    }

    private mutating func refineSequence(_ source: NativeCheckedExpression, element expected: NativeType = .unknown) throws -> NativeCheckedExpression {
        try refineOperand(source, expected: sequenceContext(source.resultType, element: expected))
    }

    private func sequenceContext(_ source: NativeType, element expected: NativeType) throws -> NativeType {
        switch source {
        case .array(let element): return .array(expected == .unknown ? element : expected)
        case .dictionary(.int, let element): return .dictionary(.int, expected == .unknown ? element : expected)
        case .unknown: return .array(expected)
        default: throw Self.diagnostic("sequence", "expected an array or integer-keyed function, received \(source.swiftType)")
        }
    }

    private func sequenceElementType(_ source: NativeType) throws -> NativeType {
        switch source {
        case .array(let element), .dictionary(.int, let element): return element
        default: throw Self.diagnostic("sequence", "invalid sequence representation")
        }
    }

    static func diagnostic(_ path: String, _ actual: String) -> CompilationDiagnostic {
        .init(code: .unsupportedGeneratedValueShape, stage: .lowering,
              path: "nativeMachine.\(path)", expected: "a statically resolved native Swift value shape",
              actual: actual, nextSafeAction: "Use a concrete typed value and an operation supported by native machine generation.")
    }

    static func unresolvedDiagnostic(_ type: NativeType, at path: String) -> CompilationDiagnostic {
        .init(code: .unresolvedGeneratedValueShape, stage: .lowering,
              path: "nativeMachine.\(path)", expected: "concrete Swift types for every value",
              actual: "type inference could not determine \(type.missingTypePaths().joined(separator: ", "))",
              nextSafeAction: "Inspect compiler type propagation for this expression; this diagnostic does not establish that the model is unsupported.")
    }

    private static func diagnostic(_ context: String, causedBy cause: CompilationDiagnostic) -> CompilationDiagnostic {
        .init(code: cause.code, stage: cause.stage,
              path: "nativeMachine.\(context) → \(cause.path)",
              expected: cause.expected, actual: cause.actual, nextSafeAction: cause.nextSafeAction)
    }

    private static func merge(_ lhs: NativeType, _ rhs: NativeType) throws -> NativeType {
        if lhs == rhs || rhs == .unknown { return lhs }
        if lhs == .unknown { return rhs }
        switch (lhs, rhs) {
        case (.set(let a), .set(let b)): return .set(try merge(a, b))
        case (.array(let a), .array(let b)): return .array(try merge(a, b))
        case (.dictionary(let ak, let av), .dictionary(let bk, let bv)):
            return .dictionary(try merge(ak, bk), try merge(av, bv))
        case (.tuple(let a), .tuple(let b)) where a.count == b.count:
            return .tuple(try zip(a, b).map { try merge($0, $1) })
        case (.record(let a), .record(let b)) where a.map(\.name) == b.map(\.name):
            return .record(try zip(a, b).map { .init(name: $0.name, type: try merge($0.type, $1.type)) })
        default: throw diagnostic("type", "incompatible shapes \(lhs.swiftType) and \(rhs.swiftType)")
        }
    }

    fileprivate static func declared(_ source: String, metadata: NativeSourceTypeMetadata, resolving: Set<String> = [], forView: Bool = false) throws -> NativeType {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let alias = metadata.aliases[source] {
            guard !resolving.contains(source) else { throw diagnostic("aliases.\(source)", "cyclic type alias") }
            return try declared(alias, metadata: metadata, resolving: resolving.union([source]), forView: forView)
        }
        switch source {
        case "TLAValue", "SwiftTLA.TLAValue":
            throw diagnostic("type", "raw TLAValue is a formal-engine value, not a generated Swift state type")
        case "Int": return .int
        case "Bool": return .bool
        case "String": return .string
        default: break
        }
        func split(_ source: String, separator: Character) -> [String] {
            var depth = 0
            var parts = [String]()
            var part = ""
            for character in source {
                if character == separator && depth == 0 { parts.append(part); part = ""; continue }
                if "<[(".contains(character) { depth += 1 }
                if ">])".contains(character) { depth -= 1 }
                part.append(character)
            }
            return parts + [part]
        }
        if source.hasPrefix("["), source.hasSuffix("]") {
            let parts = split(String(source.dropFirst().dropLast()), separator: ":")
            return parts.count == 2 ? .dictionary(try declared(parts[0], metadata: metadata, resolving: resolving, forView: forView), try declared(parts[1], metadata: metadata, resolving: resolving, forView: forView)) : .array(try declared(parts[0], metadata: metadata, resolving: resolving, forView: forView))
        }
        if let opening = source.firstIndex(of: "<"), source.hasSuffix(">") {
            let name = String(source[..<opening])
            let argumentSources = split(String(source[source.index(after: opening)..<source.index(before: source.endIndex)]), separator: ",")
            if forView && (name == "Function" || name == "ZeroBasedSequence") { return .unknown }
            let parts = try argumentSources.map { try declared($0, metadata: metadata, resolving: resolving, forView: forView) }
            switch (name, parts.count) {
            case ("Set", 1), ("SetExpr", 1): return .set(parts[0])
            case ("Array", 1), ("TupleExpr", 1): return .array(parts[0])
            case ("ZeroBasedSequence", 1): return .dictionary(.int, parts[0])
            case ("Dictionary", 2), ("Function", 2), ("FunctionExpr", 2), ("PartialFunction", 2): return .dictionary(parts[0], parts[1])
            case ("Pair", 2): return .tuple(parts)
            // Record is a schema wrapper, not an opaque application value. Its
            // field evidence comes from the shared resolved record expressions.
            case ("Record", 1), ("TLARecord", 1):
                let schema = argumentSources[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let fields = metadata.records[schema] else { return .unknown }
                let identity = "record-schema:\(schema)"
                guard !resolving.contains(identity) else { throw diagnostic("schemas.\(schema)", "recursive record schema requires a finite nonrecursive native field shape") }
                return .record(try fields.map { field in
                    .init(name: field.name, type: try declared(field.swiftType, metadata: metadata, resolving: resolving.union([identity]), forView: forView))
                }.sorted { $0.name < $1.name })
            case ("OneOf", 2):
                if forView { return .union(parts) }
                return try normalizedUnion(parts, metadata: metadata)
            default: break
            }
        }
        return .named(source)
    }

    fileprivate static func normalizedUnion(_ branches: [NativeType], metadata: NativeSourceTypeMetadata) throws -> NativeType {
        var scalarValues = Set<CompiledValue>()
        var composite: [NativeType] = []
        func append(_ branch: NativeType) throws {
            switch branch {
            case .union(let nested): for item in nested { try append(item) }
            case .finite(let values): scalarValues.formUnion(values)
            case .named(let name):
                guard let values = metadata.enums[name] else { throw diagnostic("union", "union branch has no finite declared domain") }
                scalarValues.formUnion(values.map(CompiledValue.init(formal:)))
            default:
                if !composite.contains(branch) { composite.append(branch) }
            }
        }
        for branch in branches { try append(branch) }
        func kind(_ type: NativeType) -> Int? {
            switch type {
            case .int: 0
            case .bool: 1
            case .string: 2
            case .atom: 8
            case .set: 4
            case .array, .tuple: 5
            case .record: 6
            case .dictionary: 7
            default: nil
            }
        }
        for (index, branch) in composite.enumerated() {
            guard let rank = kind(branch), branch.resolved else { throw diagnostic("union", "union alternatives require finite scalars or resolved collection shapes") }
            if composite.prefix(index).contains(where: { kind($0) == rank }) {
                throw diagnostic("union", "overlapping composite union alternatives are ambiguous")
            }
            if scalarValues.contains(where: { value in
                switch (value, branch) {
                case (.set, .set), (.tuple, .array), (.tuple, .tuple), (.record, .record), (.function, .dictionary): true
                default: false
                }
            }) { throw diagnostic("union", "finite and composite union alternatives overlap") }
        }
        scalarValues = scalarValues.filter { member in
            !composite.contains { type in
                let primitive = member.orderingKind < 4 || member.orderingKind == 8
                return primitive && kind(type) == member.orderingKind
            }
        }
        if composite.isEmpty { return .finite(scalarValues.sorted()) }
        var alternatives = composite.sorted { kind($0)! < kind($1)! }
        if !scalarValues.isEmpty { alternatives.insert(.finite(scalarValues.sorted()), at: 0) }
        return alternatives.count == 1 ? alternatives[0] : .union(alternatives)
    }

    private func element(_ type: NativeType) throws -> NativeType {
        switch type {
        case .set(let value), .array(let value): return value
        case .unknown: return .unknown
        default: throw Self.diagnostic("domain", "expected collection, found \(type.swiftType)")
        }
    }

    private func literal(_ value: CompiledValue, expected: NativeType = .unknown) throws -> NativeType {
        if case .union(let alternatives) = expected {
            let matches = alternatives.filter { (try? literal(value, expected: $0)) != nil }
            guard matches.count == 1 else { throw Self.diagnostic("union", "literal must belong to exactly one union alternative") }
            return expected
        }
        if case .collectionMember(let variable, _) = expected {
            guard collectionDomains[variable]?.contains(value) == true else {
                throw Self.diagnostic("collectionMember", "literal is outside the declared collection domain")
            }
            return expected
        }
        if case .finite(let members) = expected {
            guard members.contains(value) else { throw Self.diagnostic("finiteValue", "literal is outside the declared union domain") }
            return expected
        }
        if case .named(let name) = expected {
            if let domain = namedDomains[name], !domain.contains(value) {
                throw Self.diagnostic("namedValue", "literal is outside the declared domain of \(name)")
            }
            switch value {
            case .integer, .string, .constant: return expected
            default: break
            }
        }
        let result: NativeType
        switch value {
        case .integer: result = .int
        case .boolean: result = .bool
        case .string: result = .string
        case .constant: result = .atom
        case .controlLocation: result = .control
        case .set(let values):
            let hint: NativeType = if case .set(let type) = expected { type } else { .unknown }
            result = .set(try values.reduce(hint) { try Self.merge($0, literal($1, expected: hint)) })
        case .tuple(let values):
            if case .tuple(let hints) = expected, hints.count == values.count {
                result = .tuple(try zip(values, hints).map { try literal($0, expected: $1) })
            } else {
                let hint: NativeType = if case .array(let type) = expected { type } else { .unknown }
                let types = try values.map { try literal($0, expected: hint) }
                if hint == .unknown, let first = types.first, types.contains(where: { $0 != first }) {
                    result = .tuple(types)
                } else { result = .array(try types.reduce(hint, Self.merge)) }
            }
        case .record(let record):
            let hints: [NativeField] = if case .record(let fields) = expected { fields } else { [] }
            result = .record(try record.fields.map { field in
                guard case .string(let name) = field.key else { throw Self.diagnostic("record", "non-string field") }
                return .init(name: name, type: try literal(field.value, expected: hints.first { $0.name == name }?.type ?? .unknown))
            }.sorted { $0.name < $1.name })
        case .function(let entries):
            let hints: (NativeType, NativeType) = if case .dictionary(let key, let value) = expected { (key, value) } else { (.unknown, .unknown) }
            let types = try entries.reduce(hints) { result, entry in
                (try Self.merge(result.0, literal(entry.key, expected: hints.0)), try Self.merge(result.1, literal(entry.value, expected: hints.1)))
            }
            result = .dictionary(types.0, types.1)
        }
        return try Self.merge(expected, result)
    }

    /// A conservative finite bound obtained from literal set construction only.
    /// A state's current initializer is not evidence about all future domains.
    private func literalDomain(_ expression: CompiledStateExpr) -> Set<CompiledValue>? {
        switch expression {
        case .value(.set(let values)): return values
        case .setLiteral(let expressions):
            return expressions.reduce(Optional(Set<CompiledValue>())) { result, expression in
                guard let result, let values = literalValues(expression) else { return nil }
                return result.union(values)
            }
        case .union(let lhs, let rhs):
            guard let lhs = literalDomain(lhs), let rhs = literalDomain(rhs) else { return nil }
            return lhs.union(rhs)
        case .intersection(let lhs, let rhs):
            // Either known operand bounds every possible intersection member.
            if let lhs = literalDomain(lhs) { return lhs }
            return literalDomain(rhs)
        case .setDifference(let lhs, _): return literalDomain(lhs)
        case .setFilter(let domain, _, _): return literalDomain(domain)
        default: return nil
        }
    }

    private func literalValues(_ expression: CompiledStateExpr) -> Set<CompiledValue>? {
        switch expression {
        case .value(let value): return [value]
        case .boundValue(let binder): return bindingDomains[binder]
        default: return nil
        }
    }

    private mutating func checkAction(
        _ action: CompiledActionExpr<CompiledStateExpr>
    ) throws -> CompiledActionExpr<NativeCheckedExpression> {
        switch action {
        case .assign(let id, let expression):
            let checked = try checkOperand(expression, expected: variables[id] ?? .unknown)
            variables[id] = try Self.merge(variables[id] ?? .unknown, checked.resultType)
            return .assign(id, checked)
        case .unchanged(let id): return .unchanged(id)
        case .guard_(let expression): return .guard_(try checkOperand(expression, expected: .bool))
        case .and(let lhs, let rhs): return .and(try checkAction(lhs), try checkAction(rhs))
        case .or(let lhs, let rhs): return .or(try checkAction(lhs), try checkAction(rhs))
        case .ifElse(let condition, let lhs, let rhs):
            return .ifElse(try checkOperand(condition, expected: .bool), try checkAction(lhs), try checkAction(rhs))
        case .define(let id, let value, let body):
            bindingSources[id] = .setLiteral([value])
            bindingDomains[id] = literalValues(value)
            let checked = try checkOperand(value, expected: bindings[id] ?? .unknown)
            bindings[id] = checked.resultType
            return .define(id, checked, try checkAction(body))
        case .existsAction(let id, let domain, let body):
            bindingSources[id] = domain
            bindingDomains[id] = literalDomain(domain)
            let checked = try checkOperand(domain, expected: .set(bindings[id] ?? .unknown))
            bindings[id] = try element(checked.resultType)
            return .existsAction(id, checked, try checkAction(body))
        }
    }

    private func captureCallArguments(
        _ arguments: [CompiledFormalCallArgument], types argumentTypes: [NativeType]
    ) -> [NativeCallArgument] {
        // Infer every argument before capturing the caller scope: a later
        // argument can establish type information used by an earlier one.
        return zip(arguments, argumentTypes).map { argument, type -> NativeCallArgument in
            switch argument {
            case .value(let value):
                let source: NativeArgumentSource
                if case .boundValue(let id) = value, let existing = argumentSources[id] {
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
        _ captures: [BinderID: NativeType], using resolved: [BinderID: NativeType]
    ) -> [NativeExpressionCheckTask] {
        captures.compactMap { binder, original in
            guard let refined = resolved[binder], refined != original else { return nil }
            return .refineCapture(binder, original: original, refined: refined)
        }
    }

    private mutating func prepareOperator(
        _ operation: CompiledFormalOperator,
        arguments: [NativeCallArgument], expected: NativeType
    ) throws -> NativeOperatorCheck {
        let formalParameters: [CompiledFormalParameter]
        let body: CompiledStateExpr
        let domain: CompiledStateExpr?
        let captured = captures(of: operation)
        switch operation {
        case .lambda(let lambda):
            formalParameters = lambda.parameters.map { .value($0) }
            body = lambda.body; domain = nil
        case .reference(let id, _):
            if let definition = compilation.semantics.formalOperatorDefinitions.first(where: { $0.id == id }) {
                formalParameters = definition.parameters; body = definition.body; domain = nil
            } else if let definition = localOperators[id] {
                formalParameters = definition.parameters.map { .value($0) }
                body = definition.body; domain = definition.domain
            } else if let definition = compilation.semantics.recursiveFunctions.first(where: { $0.id == id }) {
                formalParameters = definition.parameters.map { .value($0) }
                body = definition.body; domain = nil
            } else { throw Self.diagnostic("operator", "unknown operator identity \(id.ordinal)") }
        }
        guard formalParameters.count == arguments.count else { throw Self.diagnostic("operator", "argument count mismatch") }
        var callbackArguments: [OperatorID: CompiledFormalOperator] = [:]
        var identities = captured.callbacks
        var valueTypes: [NativeType] = []
        for (parameter, argument) in zip(formalParameters, arguments) {
            switch (parameter, argument) {
            case (.value, .value(let type, _, _)):
                valueTypes.append(type)
            case (.operator(let id, let arity), .operator(let callback)):
                guard callback.operation.arity == arity else {
                    throw Self.diagnostic("operator", "operator argument arity mismatch")
                }
                identities[id] = callback.identity
                callbackArguments[id] = callback.forwardedFrom.map { .reference($0, arity: arity) } ?? callback.operation
            case (.value, .operator):
                throw Self.diagnostic("operator", "expected value argument")
            case (.operator, .value):
                throw Self.diagnostic("operator", "expected operator argument")
            }
        }
        let parameters = formalParameters.compactMap { parameter -> BinderID? in
            if case .value(let binder) = parameter { return binder }; return nil
        }
        let key = NativeOperatorSpecialization(operation: operation.identity, arguments: valueTypes,
            resultContext: expected, captures: captured.bindings, callbacks: identities)
        if activeOperators.contains(where: { active in
            guard active.operation == key.operation, active.arguments.count == key.arguments.count else { return false }
            let pairs = Array(zip(active.arguments, key.arguments))
            let argumentGrowth = pairs.contains { $1.strictlyContains($0) } && pairs.allSatisfy { $0 == $1 || $1.strictlyContains($0) }
            let callbackGrowth = active.callbacks.contains { id, previous in key.callbacks[id]?.strictlyContains(previous) == true }
            return argumentGrowth || callbackGrowth
        }) {
            throw Self.diagnostic("operator", "recursive calls require a growing family of native specializations")
        }
        // Native specialization is compile-time work, distinct from the runtime
        // recursion counter. Limit active expansion even when structural growth
        // is not recognizable (for example, changing higher-order captures).
        if !activeOperators.contains(key), activeOperators.count >= Self.maximumActiveSpecializations {
            throw Self.diagnostic("operator", "native specialization exceeds the compiler limit of \(Self.maximumActiveSpecializations) active function shapes")
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
            case (.value(let binder), .value(let type, let domain, let source)):
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
                throw Self.diagnostic("operator", "argument kind changed after validation")
            }
        }
        return .body(.init(specialization: key, parameters: parameters, body: body, domain: domain,
            context: context, callbackArguments: callbackArguments))
    }

    private mutating func checkOperand(_ expression: CompiledStateExpr, expected: NativeType = .unknown) throws -> NativeCheckedExpression {
        switch expression {
        case .boundValue(let id):
            let check: NativeBoundValueCheck
            do { check = try checkBoundValue(id, expected: expected) }
            catch let diagnostic as CompilationDiagnostic { throw annotated(diagnostic, at: expression) }
            if case .checked(let result) = check { return checkedOccurrence(expression, annotation: result) }
            return try checkWorklist(startingWith: .boundValue(id, check, expected: expected))
        case .letValue, .letIn, .and, .or, .not, .ifThenElse, .functionLiteral, .recordLiteral, .except,
             .recordAccess, .tupleDynamicAccess, .tupleLength, .tupleHead, .tupleTail, .tupleRemoving,
             .setMap, .setFilter, .choose, .forAll, .exists, .add, .subtract, .multiply, .divide,
             .integerDivide, .modulo, .negate, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
             .integerRange, .equal, .notEqual, .subset, .union, .intersection, .setDifference, .setLiteral,
             .cardinality, .powerSet, .unionAll, .sequenceFromSet, .functionSet, .tupleAppend, .tupleConcatenate,
             .operatorApplication, .recursiveCall, .lambdaApplication, .functionApply:
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

    private func annotated(_ diagnostic: CompilationDiagnostic, at expression: CompiledStateExpr) -> CompilationDiagnostic {
        let location: String
        switch expression {
        case .boundValue(let id): location = "binder[\(id.ordinal)]"
        case .stateVariable(let id): location = "variable[\(compilation.layout.variables.first { $0.id == id }?.declaration.name ?? String(id.ordinal))]"
        case .tupleAccess(_, let index): location = "tupleAccess[\(index)]"
        case .operatorApplication(let id, _), .recursiveCall(let id, _): location = "operator[\(id.ordinal)]"
        default: location = expression.diagnosticName
        }
        return CompilationDiagnostic(code: diagnostic.code, stage: diagnostic.stage,
            path: diagnostic.path + " <- " + location,
            expected: diagnostic.expected, actual: diagnostic.actual,
            nextSafeAction: diagnostic.nextSafeAction)
    }

    private mutating func checkBoundValue(_ id: BinderID, expected: NativeType) throws -> NativeBoundValueCheck {
        let result: NativeType
        let existing = bindings[id] ?? .unknown
        // A use-site projection does not replace the binder's chosen native
        // representation. Later raw scalar reads must not erase enum identity.
        if canProjectRead(existing, to: expected) {
            return .checked(.init(type: expected, computationType: existing))
        }
        if expected != .unknown, existing != expected, let evidence = argumentSources[id] {
            let refinement = NativeArgumentRefinement(expression: evidence.expression, bindings: evidence.scope.bindings, expected: expected)
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
            do { result = try Self.merge(existing, expected) }
            catch {
                let representation: NativeType? = if case .named(let name) = existing { namedRepresentations[name] } else { nil }
                throw Self.diagnostic("binding[\(id.ordinal)]", "stored \(existing), requested \(expected); known representation \(String(describing: representation))")
            }
        }
        bindings[id] = result
        let checked = try checkedType(result, expected: expected)
        return .checked(.init(type: checked.type, computationType: result))
    }

    private mutating func inferTupleLiteral(_ expressions: [CompiledStateExpr], expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let children: [NativeCheckedExpression]
        if case .tuple(let hints) = expected, hints.count == expressions.count {
            children = try zip(expressions, hints).map { try checkOperand($0, expected: $1) }
            result = .tuple(children.map(\.resultType))
        } else {
            let hint: NativeType = if case .array(let value) = expected { value } else { .unknown }
            children = try expressions.map { try checkOperand($0, expected: hint) }
            let types = children.map(\.resultType)
            if expected == .unknown, !types.isEmpty, types.allSatisfy({ $0 == .unknown }) { result = .tuple(types) }
            else if hint == .unknown, let first = types.first, types.contains(where: { $0 != first }) { result = .tuple(types) }
            else { result = .array(try types.reduce(hint, Self.merge)) }
        }
        let checked = try checkedType(result, expected: expected)
        let operands: [NativeType]
        switch checked.computationType {
        case .tuple(let types): operands = types
        case .array(let item): operands = Array(repeating: item, count: expressions.count)
        default: throw Self.diagnostic("tuple", "expected tuple or sequence representation")
        }
        return try retaining(children, in: .init(type: checked.type, computationType: checked.computationType, operandTypes: operands))
    }

    private mutating func inferSequenceSelection(_ sequence: CompiledStateExpr, binder id: BinderID, predicate: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let hint: NativeType = if case .array(let item) = expected { item } else { .unknown }
        let initial = try inferSequence(sequence)
        let item = try projectionStorageType(sequenceElementType(initial.resultType), expected: hint)
        let contextual = try refineSequence(initial, element: item)
        bindings[id] = item
        switch sequence {
        case .value(.tuple(let members)): bindingDomains[id] = Set(members)
        case .tupleLiteral(let members): bindingDomains[id] = literalDomain(.setLiteral(members))
        default: bindingDomains.removeValue(forKey: id)
        }
        let body = try checkOperand(predicate, expected: .bool)
        let selected = bindings[id] ?? item
        let source = try refineSequence(contextual, element: selected)
        return try checkedType(.array(selected), expected: expected, children: [source, body])
    }

    private mutating func inferFold(_ operation: CompiledFormalLambda, initial: CompiledStateExpr, sequence: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        guard operation.parameters.count == 2 else { throw Self.diagnostic("fold", "expected two lambda parameters") }
        var accumulator = try checkOperand(initial, expected: expected)
        bindings[operation.parameters[1]] = accumulator.resultType
        let source = try inferSequence(sequence)
        bindings[operation.parameters[0]] = try sequenceElementType(source.resultType)
        let body = try checkOperand(operation.body, expected: accumulator.resultType)
        accumulator = try refineOperand(accumulator, expected: body.resultType)
        return try checkedType(body.resultType, expected: expected, children: [body, accumulator, source])
    }

    private mutating func inferTupleAccess(_ value: CompiledStateExpr, index: Int, expected: NativeType) throws -> NativeCheckedType {
        let source = try inferProjectionSource(value, index: index, expected: expected)
        let result: NativeType
        if case .tuple(let elements) = source.resultType { result = elements[index - 1] }
        else { result = try sequenceElementType(source.resultType) }
        return try checkedType(result, expected: expected, children: [source])
    }

    private mutating func inferDomain(_ function: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let source = try inferDomainSource(function, expected: expected)
        let result: NativeType
        switch source.resultType {
        case .dictionary(let key, _): result = .set(key)
        case .array, .tuple: result = .set(.int)
        case .record: result = .set(.string)
        case .unknown: result = .set(.unknown)
        default: throw Self.diagnostic("domain", "unsupported domain shape")
        }
        return try checkedType(result, expected: expected, children: [source])
    }

    /// Visit operands in source order and retain ancestry for diagnostics.
    private mutating func checkWorklist(startingWith task: NativeExpressionCheckTask) throws -> NativeCheckedExpression {
        // Tasks are appended in reverse execution order.
        var pending = [task]
        var results: [NativeType] = []
        var ancestors: [CompiledStateExpr] = []
        var completed: NativeCheckedExpression?
        var operandFrames: [[Int: NativeCheckedExpression]] = []
        var suspendedScopes: [NativeTypeInference] = []
        var checkedCalls: [NativeOperatorCall] = []
        func finish(_ annotation: NativeCheckedType, in scope: inout NativeTypeInference, refineOperands: Bool = true) throws {
            guard let expression = ancestors.last, let operands = operandFrames.last else {
                throw Self.diagnostic("checking", "missing checked occurrence")
            }
            let orderedOperands = operands.sorted { $0.key < $1.key }
            let children = orderedOperands.map(\.value)
            if refineOperands, annotation.call == nil, !children.isEmpty {
                guard children.count == annotation.operandTypes.count else {
                    throw Self.diagnostic("checking", "missing checked operands")
                }
                let refinements = zip(orderedOperands, annotation.operandTypes).filter { operand, expected in
                    operand.value.resultType != expected
                }
                if !refinements.isEmpty {
                    pending.append(.completeOccurrence(annotation))
                    for (operand, expected) in refinements.reversed() {
                        pending.append(contentsOf: [
                            .discard, .retainOperand(operand.key),
                            .check(operand.value.expression, expected: expected)
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
                        switch expression {
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
                    switch expression {
                    case .recordAccess(let source, _, _):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [.recordContext(expected: expected), .discard, .retainOperand(0), .check(source, expected: .unknown)])
                    case .tupleDynamicAccess(let source, let index):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finishSequenceOperation(expected: expected), .discard, .retainOperand(0),
                            .sequenceContext(element: expected), .check(source, expected: .unknown),
                            .discard, .retainOperand(1), .check(index, expected: .int)
                        ])
                    case .tupleRemoving(let source, let index):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
                        pending.append(contentsOf: [
                            .finishSequenceOperation(expected: expected), .discard, .retainOperand(1), .check(index, expected: .int),
                            .discard, .retainOperand(0), .sequenceContext(element: hint), .check(source, expected: .unknown)
                        ])
                    case .tupleLength(let source), .tupleHead(let source), .tupleTail(let source):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        let hint: NativeType
                        switch expression {
                        case .tupleHead: hint = expected
                        case .tupleTail: hint = if case .array(let element) = expected { element } else { .unknown }
                        default: hint = .unknown
                        }
                        pending.append(contentsOf: [
                            .finishSequenceOperation(expected: expected), .discard, .retainOperand(0),
                            .sequenceContext(element: hint), .check(source, expected: .unknown)
                        ])
                    case .except(let source, _, _):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [.updateKey(expected: expected), .discard, .retainOperand(0), .check(source, expected: expected)])
                    case .recordLiteral(let record):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [.finishRecord(expected: expected), .recordFields(record.fields[...], expected: expected)])
                    case .tupleAppend(let sequence, let value), .tupleConcatenate(let sequence, let value):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        let element = if case .array(let element) = expected { element } else { NativeType.unknown }
                        pending.append(contentsOf: [
                            .sequenceValue(value, expected: expected), .retainOperand(0),
                            .sequenceContext(element: element), .check(sequence, expected: .unknown)
                        ])
                    case .operatorApplication(let id, let arguments):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(.call(expression, .reference(id, arity: arguments.count), arguments, expected: expected))
                    case .recursiveCall(let id, let arguments):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(.call(expression, .reference(id, arity: arguments.count), arguments.map { .value($0) }, expected: expected))
                    case .lambdaApplication(let lambda, let arguments):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(.call(expression, .lambda(lambda), arguments.map { .value($0) }, expected: expected))
                    case .functionApply(.operatorReference(let id), let argument):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(.call(expression, .reference(id, arity: 1), [.value(argument)], expected: expected))
                    case .functionApply(let source, _):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [.applicationKey(expected: expected), .discard, .retainOperand(0), .check(source, expected: .unknown)])
                    case .setLiteral(let elements):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        let hint: NativeType = if case .set(let item) = expected { item } else { .unknown }
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
                    case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
                         .divide(let lhs, let rhs), .integerDivide(let lhs, let rhs), .modulo(let lhs, let rhs),
                         .lessThan(let lhs, let rhs), .lessOrEqual(let lhs, let rhs),
                         .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
                         .integerRange(let lhs, let rhs):
                        let result: NativeType = switch expression {
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
                    case .negate(let operand):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected), .result(.int),
                            .discard, .retainOperand(0), .check(operand, expected: .int),
                        ])
                    case .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .subset(let lhs, let rhs):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        if case .subset = expression { pending.append(.subset(expected: expected)) }
                        else { pending.append(.comparison(expected: expected)) }
                        pending.append(contentsOf: [
                            .reconcile(lhs, rhs, expected: .unknown),
                            .retainOperand(1), .check(rhs, expected: .unknown),
                            .retainOperand(0), .check(lhs, expected: .unknown),
                        ])
                    case .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .setOperands(lhs, rhs, expected: expected),
                            .reconcile(lhs, rhs, expected: .unknown),
                            .retainOperand(1), .check(rhs, expected: .unknown),
                            .retainOperand(0), .check(lhs, expected: .unknown),
                        ])
                    case .ifThenElse(let condition, let yes, let no):
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
                    case .and(let lhs, let rhs), .or(let lhs, let rhs):
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
                    case .not(let operand):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .result(.bool),
                            .discard,
                            .retainOperand(0), .check(operand, expected: .bool),
                        ])
                    case .letValue(let id, let value, let body):
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
                    case .letIn(let definitions, let body):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        for definition in definitions { localOperators[definition.id] = definition }
                        for definition in definitions {
                            let captures = capturedBindings(of: definition)
                            localCaptures[definition.id] = bindings.filter { captures.contains($0.key) }
                        }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .retainOperand(0), .check(body, expected: expected),
                        ])
                    case .functionLiteral(let domain, let id, let body):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        let hints: (key: NativeType, value: NativeType)
                        if case .dictionary(let key, let value) = expected { hints = (key, value) }
                        else { hints = (.unknown, .unknown) }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .dictionary,
                            .retainOperand(1), .check(body, expected: hints.value),
                            .bindDomain(id, retainElement: true),
                            .retainOperand(0), .check(domain, expected: .set(hints.key)),
                        ])
                    case .cardinality(let domain), .powerSet(let domain), .unionAll(let domain), .sequenceFromSet(let domain):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        let hint: NativeType
                        switch expression {
                        case .powerSet:
                            hint = if case .set(let item) = expected { item } else { .set(.unknown) }
                        case .unionAll:
                            hint = .set(expected == .unknown ? .set(.unknown) : expected)
                        case .sequenceFromSet:
                            hint = if case .array(let item) = expected { .set(item) } else { .set(.unknown) }
                        default: hint = .set(.unknown)
                        }
                        pending.append(contentsOf: [.finishUnaryCollection(expected: expected), .retainOperand(0), .check(domain, expected: hint)])
                    case .functionSet(let domain, let range):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        let candidate: NativeType = if case .set(let item) = expected { item } else { .unknown }
                        let hint: NativeType = candidate == .unknown ? .dictionary(.unknown, .unknown) : candidate
                        guard case .dictionary(let key, let value) = hint else {
                            throw Self.diagnostic("functionSet", "expected set of dictionaries")
                        }
                        pending.append(contentsOf: [
                            .finishFunctionSet(expected: expected),
                            .retainOperand(1), .check(range, expected: .set(value)),
                            .retainOperand(0), .check(domain, expected: .set(key)),
                        ])
                    case .setFilter(let domain, let id, let predicate), .choose(let domain, let id, let predicate):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        let choosing: Bool = if case .choose = expression { true } else { false }
                        let hint: NativeType = choosing ? .set(expected) : (expected == .unknown ? .set(.unknown) : expected)
                        pending.append(contentsOf: [
                            .finishSetPredicate(choosing: choosing),
                            .refineDomain(domain, id),
                            .discard, .retainOperand(1), .check(predicate, expected: .bool),
                            .bindDomain(id, retainElement: false),
                            .retainOperand(0), .check(domain, expected: hint),
                        ])
                    case .setMap(let body, let id, let domain):
                        ancestors.append(expression)
                        operandFrames.append([:])
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        let hint: NativeType = if case .set(let item) = expected { item } else { .unknown }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .set,
                            .retainOperand(0), .check(body, expected: hint),
                            .bindDomain(id, retainElement: false),
                            .retainOperand(1), .check(domain, expected: .set(.unknown)),
                        ])
                    case .forAll(let domain, let id, let body), .exists(let domain, let id, let body):
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
                    pending.append(.enterCall(expression, operation, arguments, expected: expected))
                    for (index, argument) in arguments.enumerated().reversed() {
                        switch argument {
                        case .value(let value): pending.append(contentsOf: [.retainOperand(index), .check(value, expected: .unknown)])
                        case .operator: pending.append(.result(.unknown))
                        }
                    }
                case .enterCall(let expression, let requested, let arguments, let expected):
                    guard results.count >= arguments.count else {
                        throw Self.diagnostic("checking", "missing checked call arguments")
                    }
                    let types = Array(results.suffix(arguments.count))
                    results.removeLast(arguments.count)
                    let argumentsWithSources = captureCallArguments(arguments, types: types)
                    let callbackID: OperatorID?
                    if case .reference(let id, _) = requested, boundOperators[id] != nil { callbackID = id }
                    else { callbackID = nil }
                    let callback = callbackID.flatMap { boundOperators[$0] }
                    let operation = callback?.operation ?? requested
                    let call = NativePendingCall(expression: expression, operation: operation,
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
                case .finishOperator(let operation):
                    guard let result = results.popLast(), let body = completed else {
                        throw Self.diagnostic("checking", "missing checked operator body")
                    }
                    let domainGuard: NativeCheckedExpression?
                    if let domain = operation.domain, let parameter = operation.parameters.first {
                        domainGuard = try checkOperand(.in(.boundValue(parameter), domain), expected: .bool)
                    } else { domainGuard = nil }
                    specializationResults[operation.specialization] = try Self.operandContext(operation.context, result)
                    activeOperators.remove(operation.specialization)
                    checkedCalls.append(.init(specialization: operation.specialization, parameters: operation.parameters,
                        implementation: .checked(body: body, domainGuard: domainGuard), result: result, bindings: bindings, boundOperators: boundOperators,
                        callbackUses: callbackUses, callbackArguments: operation.callbackArguments))
                case .leaveCall(let call):
                    guard let resolved = checkedCalls.popLast(), var caller = suspendedScopes.popLast() else {
                        throw Self.diagnostic("checking", "missing checked call or caller context")
                    }
                    caller.specializationResults.merge(specializationResults) { _, current in current }
                    caller.variables = variables
                    self = caller
                    if let callbackID = call.callbackID { recordCallback(callbackID, call: resolved) }
                    pending.append(contentsOf: [
                        .completeCall(call.expression, resolved, expected: call.expected),
                        .refineCallCaptures(call.operation, resolved),
                    ])
                    let values = zip(call.arguments, call.checkedArguments).enumerated().compactMap { index, pair -> (Int, CompiledStateExpr, NativeType)? in
                        let (argument, checked) = pair
                        guard case .value(let value) = argument, case .value(let type, _, _) = checked else { return nil }
                        return (index, value, type)
                    }
                    for (argument, refined) in zip(values, resolved.specialization.arguments).reversed() {
                        if argument.2 != refined {
                            pending.append(contentsOf: [.discard, .retainOperand(argument.0), .check(argument.1, expected: refined)])
                        }
                    }
                case .refineCallCaptures(let operation, let resolved):
                    var checks: [NativeExpressionCheckTask] = []
                    if case .reference(let id, _) = operation, let captures = localCaptures[id] {
                        checks.append(contentsOf: capturedValueChecks(captures, using: resolved.refinedBindings))
                    }
                    for (parameter, uses) in resolved.callbackUses {
                        guard resolved.callbackArguments[parameter] != nil,
                              let binding = resolved.boundOperators[parameter],
                              binding.forwardedFrom == nil else { continue }
                        let parameters: Set<BinderID>
                        if case .lambda(let lambda) = binding.operation { parameters = Set(lambda.parameters) }
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
                        if resolved.callbackArguments[parameter] == nil, boundOperators[parameter] != nil {
                            for use in uses { recordCallback(parameter, call: use) }
                        } else if let origin = resolved.boundOperators[parameter]?.forwardedFrom {
                            for use in uses { recordCallback(origin, call: use) }
                        }
                    }
                case .completeCall(let expression, let call, let expected):
                    let checked: NativeCheckedType
                    if case .functionApply = expression {
                        checked = .init(type: call.result, computationType: call.result, call: call)
                    } else {
                        let result = try checkedType(call.result, expected: expected)
                        checked = .init(type: result.type, computationType: result.computationType,
                            operandTypes: result.operandTypes, call: call)
                    }
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .finishArgument(let id, let refinement):
                    guard let refined = results.popLast(), var caller = suspendedScopes.popLast() else {
                        throw Self.diagnostic("checking", "missing suspended argument context")
                    }
                    caller.specializationResults.merge(specializationResults) { _, current in current }
                    caller.bindings[id] = refined
                    caller.activeArgumentRefinements.remove(refinement)
                    self = caller
                    results.append(refined)
                    try finish(.init(type: refined, computationType: refined), in: &self)
                case .finishBindingDomain(let id):
                    guard let domain = results.popLast() else {
                        throw Self.diagnostic("checking", "missing refined binding domain")
                    }
                    let refined = try element(domain)
                    bindings[id] = refined
                    activeBindingRefinements.remove(id)
                    results.append(refined)
                    try finish(.init(type: refined, computationType: refined), in: &self)
                case .bind(let id):
                    guard let type = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked binding type")
                    }
                    bindings[id] = type
                case .bindDomain(let id, let retainElement):
                    guard let domain = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked binding domain")
                    }
                    let item = try element(domain)
                    bindings[id] = item
                    if retainElement { results.append(item) }
                case .finishUnaryCollection(let expected):
                    guard let source = results.popLast(), let expression = ancestors.last else {
                        throw Self.diagnostic("checking", "missing checked collection operand")
                    }
                    let result: NativeType
                    switch expression {
                    case .cardinality: result = .int
                    case .powerSet: result = .set(source)
                    case .unionAll: result = try element(source)
                    case .sequenceFromSet: result = .array(try element(source))
                    default: throw Self.diagnostic("checking", "unexpected collection operation")
                    }
                    let checked = try checkedType(result, expected: expected, operandTypes: [source])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .finishFunctionSet(let expected):
                    guard let range = results.popLast(), let domain = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked function-set operands")
                    }
                    let result = NativeType.set(.dictionary(try element(domain), try element(range)))
                    let checked = try checkedType(result, expected: expected, operandTypes: [domain, range])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .refineDomain(let domain, let id):
                    pending.append(contentsOf: [.retainOperand(0), .check(domain, expected: .set(bindings[id] ?? .unknown))])
                case .finishSetPredicate(let choosing):
                    guard let domain = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked predicate domain")
                    }
                    let result = choosing ? try element(domain) : domain
                    // Preserve nominal refinements established by the predicate.
                    results.append(result)
                    try finish(.init(type: result, computationType: result, operandTypes: [domain, .bool]), in: &self)
                case .set:
                    guard let item = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked set element")
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
                        throw Self.diagnostic("checking", "missing checked set member")
                    }
                    let element = try Self.merge(previous, item)
                    pending.append(.setElements(remaining, element: element))
                case .dictionary:
                    guard let value = results.popLast(), let key = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked function operands")
                    }
                    results.append(.dictionary(key, value))
                case .reconcile(let yes, let no, let expected):
                    guard let right = results.popLast(), let left = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked branch types")
                    }
                    let context = try Self.operandContext(left, right)
                    let offset: Int = if case .ifThenElse = ancestors.last { 1 } else { 0 }
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
                        throw Self.diagnostic("checking", "missing checked set operand types")
                    }
                    let context = try Self.operandContext(compared, expected)
                    _ = try element(context)
                    pending.append(contentsOf: [
                        .retainOperand(1), .check(rhs, expected: context),
                        .discard, .retainOperand(0), .check(lhs, expected: context),
                    ])
                case .comparison(let expected), .subset(let expected):
                    guard let context = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked comparison operands")
                    }
                    if case .subset = task { _ = try element(context) }
                    let checked = try checkedType(.bool, expected: expected, operandTypes: [context, context])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .finish(let expected):
                    guard let result = results.popLast(), let expression = ancestors.last else {
                        throw Self.diagnostic("checking", "missing checked expression type")
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
                    guard case .recordAccess(_, _, let key) = ancestors.last, let source = operandFrames.last?[0] else {
                        throw Self.diagnostic("recordAccess", "missing checked record source")
                    }
                    pending.append(.finishRecordAccess(expected: expected))
                    if source.resultType == .unknown { continue }
                    guard case .string(let name) = key, case .record(var fields) = source.resultType,
                          let index = fields.firstIndex(where: { $0.name == name }) else {
                        throw Self.diagnostic("recordAccess", "unknown record field")
                    }
                    fields[index] = .init(name: name, type: try projectionStorageType(fields[index].type, expected: expected))
                    let context = NativeType.record(fields)
                    if source.resultType != context {
                        pending.append(contentsOf: [.discard, .retainOperand(0), .check(source.expression, expected: context)])
                    }
                case .finishRecordAccess(let expected):
                    guard case .recordAccess(_, _, let key) = ancestors.last, let source = operandFrames.last?[0] else {
                        throw Self.diagnostic("recordAccess", "missing checked record source")
                    }
                    let result: NativeType
                    if case .string(let name) = key, case .record(let fields) = source.resultType,
                       let field = fields.first(where: { $0.name == name }) { result = field.type }
                    else { result = .unknown }
                    let checked = try checkedType(result, expected: expected, operandTypes: [source.resultType])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .finishSequenceOperation(let expected):
                    guard let expression = ancestors.last, let operands = operandFrames.last, let source = operands[0] else {
                        throw Self.diagnostic("sequence", "missing checked sequence source")
                    }
                    let result: NativeType
                    switch expression {
                    case .tupleLength: result = .int
                    case .tupleHead, .tupleDynamicAccess: result = try sequenceElementType(source.resultType)
                    case .tupleTail, .tupleRemoving: result = try .array(sequenceElementType(source.resultType))
                    default: throw Self.diagnostic("sequence", "unexpected sequence operation")
                    }
                    let operandTypes = operands.sorted { $0.key < $1.key }.map { $0.value.resultType }
                    let checked = try checkedType(result, expected: expected, operandTypes: operandTypes)
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .applicationKey(let expected):
                    guard case .functionApply(_, let key) = ancestors.last, let source = operandFrames.last?[0] else {
                        throw Self.diagnostic("function", "missing checked application source")
                    }
                    let keyType: NativeType
                    switch source.resultType {
                    case .unknown:
                        pending.append(contentsOf: [.applicationSource(expected: expected), .check(key, expected: .unknown)])
                        continue
                    case .dictionary(let domain, _): keyType = domain
                    case .array, .tuple: keyType = .int
                    case .record: keyType = .string
                    default: throw Self.diagnostic("function", "expected a native dictionary, sequence, or record")
                    }
                    pending.append(contentsOf: [.finishApplication(expected: expected), .discard, .retainOperand(1), .check(key, expected: keyType)])
                case .applicationSource(let expected):
                    guard case .functionApply(let source, _) = ancestors.last, let keyType = results.popLast() else {
                        throw Self.diagnostic("function", "missing inferred application domain")
                    }
                    pending.append(contentsOf: [
                        .applicationKey(expected: expected), .discard, .retainOperand(0),
                        .check(source, expected: .dictionary(keyType, expected))
                    ])
                case .finishApplication(let expected):
                    guard case .functionApply(_, let key) = ancestors.last,
                          let operands = operandFrames.last, let source = operands[0], let checkedKey = operands[1] else {
                        throw Self.diagnostic("function", "missing checked application operands")
                    }
                    let result: NativeType
                    var sourceType = source.resultType
                    switch source.resultType {
                    case .dictionary(let domain, let value):
                        result = try Self.operandContext(value, expected)
                        sourceType = .dictionary(domain, result)
                    case .array(let value):
                        result = try Self.operandContext(value, expected)
                        sourceType = .array(result)
                    case .tuple(let elements):
                        if case .value(.integer(let index)) = key, index >= 1, index <= elements.count {
                            var hints = elements
                            hints[index - 1] = try Self.operandContext(elements[index - 1], expected)
                            sourceType = .tuple(hints)
                            result = hints[index - 1]
                        } else if case .value(.integer) = key, expected != .unknown {
                            result = expected
                        } else {
                            result = try elements.reduce(expected, Self.merge)
                            sourceType = .tuple(elements.map { _ in result })
                        }
                    case .record(let fields):
                        if case .value(.string(let name)) = key {
                            if let selected = fields.first(where: { $0.name == name }) {
                                result = try Self.operandContext(selected.type, expected)
                                sourceType = .record(fields.map { .init(name: $0.name, type: $0.name == name ? result : $0.type) })
                            } else { result = expected }
                        } else {
                            result = try fields.map(\.type).reduce(expected, Self.merge)
                            sourceType = .record(fields.map { .init(name: $0.name, type: result) })
                        }
                    default: throw Self.diagnostic("function", "expected a native dictionary, sequence, or record")
                    }
                    let checked = try checkedType(result, expected: expected, operandTypes: [sourceType, checkedKey.resultType])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .updateKey(let expected):
                    guard case .except(_, let key, _) = ancestors.last, let source = operandFrames.last?[0] else {
                        throw Self.diagnostic("except", "missing checked update source")
                    }
                    let keyType: NativeType
                    switch source.resultType {
                    case .array: keyType = .int
                    case .dictionary(let domain, _): keyType = domain
                    case .record: keyType = .string
                    case .unknown: keyType = .unknown
                    default: throw Self.diagnostic("except", "unsupported update shape \(source.resultType.swiftType)")
                    }
                    pending.append(contentsOf: [.updateValue(expected: expected), .discard, .retainOperand(1), .check(key, expected: keyType)])
                case .updateValue(let expected):
                    guard case .except(_, let key, let value) = ancestors.last, let source = operandFrames.last?[0] else {
                        throw Self.diagnostic("except", "missing checked update key")
                    }
                    let valueType: NativeType
                    switch source.resultType {
                    case .array(let item), .dictionary(_, let item): valueType = item
                    case .record(let fields):
                        if case .value(.string(let name)) = key {
                            valueType = fields.first { $0.name == name }?.type ?? .unknown
                        } else {
                            let item = fields.first?.type ?? .unknown
                            guard fields.allSatisfy({ $0.type == item }) else {
                                throw Self.diagnostic("except", "dynamic record keys require homogeneous field types")
                            }
                            valueType = item
                        }
                    case .unknown: valueType = .unknown
                    default: throw Self.diagnostic("except", "unsupported update shape \(source.resultType.swiftType)")
                    }
                    pending.append(contentsOf: [.finishUpdate(expected: expected), .discard, .retainOperand(2), .check(value, expected: valueType)])
                case .finishUpdate(let expected):
                    guard let operands = operandFrames.last,
                          let source = operands[0], let key = operands[1], let value = operands[2] else {
                        throw Self.diagnostic("except", "missing checked update operands")
                    }
                    let result: NativeType
                    switch source.resultType {
                    case .array: result = .array(value.resultType)
                    case .dictionary(let domain, _): result = .dictionary(domain, value.resultType)
                    case .record: result = source.resultType
                    case .unknown: result = .dictionary(key.resultType, value.resultType)
                    default: throw Self.diagnostic("except", "unsupported update shape \(source.resultType.swiftType)")
                    }
                    let checked = try checkedType(result, expected: expected)
                    results.append(checked.type)
                    try finish(.init(type: checked.type, computationType: checked.computationType,
                        operandTypes: [checked.computationType, key.resultType, value.resultType]), in: &self)
                case .recordFields(var remaining, let expected):
                    guard let field = remaining.popFirst() else { continue }
                    guard case .string(let name) = field.key else {
                        throw Self.diagnostic("record", "non-string field")
                    }
                    let hints: [NativeField] = if case .record(let fields) = expected { fields } else { [] }
                    pending.append(contentsOf: [
                        .recordFields(remaining, expected: expected), .discard,
                        .retainOperand(remaining.startIndex - 1),
                        .check(field.value, expected: hints.first { $0.name == name }?.type ?? .unknown)
                    ])
                case .finishRecord(let expected):
                    guard case .recordLiteral(let record) = ancestors.last, let operands = operandFrames.last else {
                        throw Self.diagnostic("record", "missing checked record")
                    }
                    let fields = try record.fields.enumerated().map { index, field -> NativeField in
                        guard case .string(let name) = field.key, let child = operands[index] else {
                            throw Self.diagnostic("record", "missing checked field")
                        }
                        return .init(name: name, type: child.resultType)
                    }
                    let operandTypes = fields.map(\.type)
                    let checked = try checkedType(.record(fields.sorted { $0.name < $1.name }), expected: expected, operandTypes: operandTypes)
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .sequenceContext(let element):
                    guard let source = completed, let type = results.popLast() else {
                        throw Self.diagnostic("sequence", "missing checked sequence")
                    }
                    if case .tupleLength = ancestors.last, case .tuple = type {
                        results.append(type)
                        continue
                    }
                    let context = try sequenceContext(type, element: element)
                    if type == context { results.append(type) }
                    else { pending.append(.check(source.expression, expected: context)) }
                case .sequenceValue(let value, let expected):
                    guard let source = results.last, let expression = ancestors.last else {
                        throw Self.diagnostic("sequence", "missing checked construction source")
                    }
                    let element = try sequenceElementType(source)
                    pending.append(contentsOf: [.finishSequenceConstruction(expected: expected), .retainOperand(1)])
                    if case .tupleConcatenate = expression {
                        pending.append(contentsOf: [.sequenceContext(element: element), .check(value, expected: .unknown)])
                    } else {
                        pending.append(.check(value, expected: element))
                    }
                case .finishSequenceConstruction(let expected):
                    guard let value = results.popLast(), let source = results.popLast(), let expression = ancestors.last else {
                        throw Self.diagnostic("sequence", "missing checked construction operands")
                    }
                    let valueElement: NativeType
                    if case .tupleConcatenate = expression { valueElement = try sequenceElementType(value) }
                    else { valueElement = value }
                    let element = try Self.merge(sequenceElementType(source), valueElement)
                    let valueContext: NativeType
                    if case .tupleConcatenate = expression { valueContext = try sequenceContext(value, element: element) }
                    else { valueContext = element }
                    let checked = try checkedType(.array(element), expected: expected,
                        operandTypes: [sequenceContext(source, element: element), valueContext])
                    results.append(checked.type)
                    try finish(checked, in: &self)
                case .completeOccurrence(let annotation):
                    try finish(annotation, in: &self, refineOperands: false)
                case .result(let type):
                    results.append(type)
                case .retainOperand(let index):
                    guard let completed, !operandFrames.isEmpty else {
                        throw Self.diagnostic("checking", "missing checked operand")
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
            throw Self.diagnostic("checking", "missing checked expression")
        }
        return completed
    }

    private func finishExpression(
        _ expression: CompiledStateExpr, result: NativeType, expected: NativeType
    ) throws -> NativeCheckedType {
        let checked = try checkedType(result, expected: expected)
        let type = checked.computationType
        let operands: [NativeType]
        switch expression {
        case .add, .subtract, .multiply, .divide, .integerDivide, .modulo,
             .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual, .integerRange:
            operands = [.int, .int]
        case .negate: operands = [.int]
        case .and, .or: operands = [.bool, .bool]
        case .not: operands = [.bool]
        case .ifThenElse: operands = [.bool, type, type]
        case .union, .intersection, .setDifference: operands = [type, type]
        case .setLiteral(let values):
            operands = Array(repeating: try element(type), count: values.count)
        case .letValue(let id, _, _): operands = [bindings[id] ?? .unknown, type]
        case .letIn: operands = [type]
        case .functionLiteral:
            guard case .dictionary(let key, let value) = type else {
                throw Self.diagnostic("function", "expected dictionary representation")
            }
            operands = [.set(key), value]
        case .setMap(_, let id, _):
            operands = [try element(type), .set(bindings[id] ?? .unknown)]
        case .forAll(_, let id, _), .exists(_, let id, _):
            operands = [.set(bindings[id] ?? .unknown), .bool]
        default:
            throw Self.diagnostic("checking", "missing operand types for \(expression.diagnosticName)")
        }
        return .init(type: checked.type, computationType: type, operandTypes: operands)
    }

    private func capturedBindings(of definition: CompiledLocalOperator) -> Set<BinderID> {
        var captures = definition.capturedBindings
        var pending = Array(definition.referencedOperators)
        var visited: Set<OperatorID> = [definition.id]
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let referenced = localOperators[id] else { continue }
            captures.formUnion(referenced.capturedBindings)
            pending.append(contentsOf: referenced.referencedOperators)
        }
        return captures
    }

    private mutating func inferCases(_ first: CompiledCaseBranch, rest: [CompiledCaseBranch], otherwise: CompiledStateExpr?, expected: NativeType) throws -> NativeCheckedType {
        var type = expected
        var children: [NativeCheckedExpression] = []
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
        let operands = ([first] + rest).flatMap { _ in [NativeType.bool, checked.computationType] }
            + (otherwise == nil ? [] : [checked.computationType])
        return try retaining(children, in: .init(type: checked.type, computationType: checked.computationType, operandTypes: operands))
    }

    private mutating func inferResolved(_ expression: CompiledStateExpr, expected: NativeType = .unknown) throws -> NativeCheckedType {
        if case .union = expected, let checked = try checkUnionConstructor(expression, expected: expected) {
            return checked
        }
        let result: NativeType
        switch expression {
        case .assertView(let value, let shape):
            let source = try checkOperand(value)
            result = try viewType(shape)
            return try checkedType(result, expected: expected, children: [source])
        case .value(let value):
            let type = try literal(value, expected: expected)
            return .init(type: type, computationType: type)
        case .stateVariable(let id):
            let existing = variables[id] ?? .unknown
            if canProjectRead(existing, to: expected) { return .init(type: expected, computationType: existing) }
            else { result = try Self.merge(existing, expected); variables[id] = result }
        case .controlLocation: result = .control
        case .enabledAction: result = .bool
        case .in(let value, let domain):
            return try checkMembership(value: value, domain: domain, expected: expected)
        case .sequenceSelect(let sequence, let id, let predicate):
            return try inferSequenceSelection(sequence, binder: id, predicate: predicate, expected: expected)
        case .setSum(let function, let domain):
            let source = try checkOperand(domain, expected: .set(.unknown))
            let key = try element(source.resultType)
            let operation = try checkOperand(function, expected: .dictionary(key, .int))
            return try checkedType(.int, expected: expected, children: [operation, source])
        case .foldFunction(let operation, let initial, let sequence):
            return try inferFold(operation, initial: initial, sequence: sequence, expected: expected)
        case .tupleLiteral(let expressions): return try inferTupleLiteral(expressions, expected: expected)
        case .tupleAccess(let value, let index):
            return try inferTupleAccess(value, index: index, expected: expected)
        case .domain(let function):
            return try inferDomain(function, expected: expected)
        case .caseExpr(let first, let rest, let otherwise):
            return try inferCases(first, rest: rest, otherwise: otherwise, expected: expected)
        default: throw Self.diagnostic("expression", "expression is outside the native machine subset: \(expression.diagnosticName)")
        }
        return try checkedType(result, expected: expected)
    }
}
