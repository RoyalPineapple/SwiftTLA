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

package struct NativeField: Hashable, Sendable {
    package let name: String
    package let type: NativeType

    package init(name: String, type: NativeType) {
        self.name = name
        self.type = type
    }
}

/// Type evidence for code generation, never a runtime value representation.
package indirect enum NativeType: Hashable, Sendable {
    case unknown
    case int, bool, string, atom, control
    case named(String)
    case finite([CompiledValue])
    case union([NativeType])
    case collectionMember(VariableID, swiftType: String)
    case set(NativeType)
    case array(NativeType)
    case dictionary(NativeType, NativeType)
    case record([NativeField])
    case tuple([NativeType])

    var components: [NativeType] {
        switch self {
        case .set(let value), .array(let value): [value]
        case .dictionary(let key, let value): [key, value]
        case .record(let fields): fields.map(\.type)
        case .tuple(let values), .union(let values): values
        default: []
        }
    }

    private func embeds(_ other: NativeType) -> Bool {
        if self == other { return true }
        guard other != .unknown else { return false }
        if components.contains(where: { $0.embeds(other) }) { return true }
        switch (self, other) {
        case (.array(let a), .array(let b)), (.set(let a), .set(let b)): return a.embeds(b)
        case (.dictionary(let a, let b), .dictionary(let c, let d)): return a.embeds(c) && b.embeds(d)
        case (.tuple(let a), .tuple(let b)), (.union(let a), .union(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.embeds($1) }
        case (.record(let a), .record(let b)) where a.map(\.name) == b.map(\.name):
            return zip(a, b).allSatisfy { $0.type.embeds($1.type) }
        default: return false
        }
    }

    fileprivate func strictlyContains(_ other: NativeType) -> Bool { self != other && embeds(other) }

    package var swiftType: String {
        switch self {
        case .unknown: "<unresolved>"
        case .int: "Int"
        case .bool: "Bool"
        case .string: "String"
        case .atom: "_Atom"
        case .control: "_ControlLocation"
        case .named(let name): name
        case .finite: "FiniteValue"
        case .union: "UnionValue"
        case .collectionMember(_, let name): name
        case .set(let element): "Set<\(element.swiftType)>"
        case .array(let element): "[\(element.swiftType)]"
        case .dictionary(let key, let value): "[\(key.swiftType): \(value.swiftType)]"
        case .record(let fields): "(" + fields.map { "\($0.name): \($0.type.swiftType)" }.joined(separator: ", ") + ")"
        case .tuple(let elements): "(" + elements.map(\.swiftType).joined(separator: ", ") + ")"
        }
    }

    var resolved: Bool {
        switch self {
        case .unknown: false
        case .set(let element), .array(let element): element.resolved
        case .dictionary(let key, let value): key.resolved && value.resolved
        case .record(let fields): fields.allSatisfy { $0.type.resolved }
        case .tuple(let elements), .union(let elements): elements.allSatisfy(\.resolved)
        default: true
        }
    }

    func missingTypePaths(from path: String = "value") -> [String] {
        switch self {
        case .unknown: return [path]
        case .set(let element), .array(let element):
            return element.missingTypePaths(from: path + ".element")
        case .dictionary(let key, let value):
            return key.missingTypePaths(from: path + ".key")
                + value.missingTypePaths(from: path + ".value")
        case .record(let fields):
            return fields.flatMap { $0.type.missingTypePaths(from: path + "." + $0.name) }
        case .tuple(let elements), .union(let elements):
            return elements.enumerated().flatMap {
                $0.element.missingTypePaths(from: path + "[\($0.offset + 1)]")
            }
        default: return []
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
        identity = .init(operation: operation.identity, captures: scope.bindings, callbacks: scope.callbackIdentities)
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

struct NativeOperatorCall: Sendable {
    let specialization: NativeOperatorSpecialization
    let parameters: [BinderID]
    let body: CompiledStateExpr
    let domain: CompiledStateExpr?
    let result: NativeType
    let inference: NativeTypeInference
    let callbackUses: [OperatorID: [NativeOperatorCall]]
    let callbackArguments: [OperatorID: CompiledFormalOperator]
}

/// Checking retains the representation before an implicit use-site conversion.
private struct NativeCheckedType: Sendable {
    let type: NativeType
    let computationType: NativeType
    /// Context selected while checking operands, in expression order.
    let operandTypes: [NativeType]
    let call: NativeOperatorCall?

    init(type: NativeType, computationType: NativeType, operandTypes: [NativeType] = [], call: NativeOperatorCall? = nil) {
        self.type = type
        self.computationType = computationType
        self.operandTypes = operandTypes
        self.call = call
    }
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
    case comparison(expected: NativeType)
    case subset(expected: NativeType)
    case setOperands(CompiledStateExpr, CompiledStateExpr, expected: NativeType)
    case bind(BinderID)
    case finishArgument(BinderID, NativeArgumentRefinement)
    case finishBindingDomain(BinderID)
    case bindDomain(BinderID, retainElement: Bool)
    case set
    case setElements(ArraySlice<CompiledStateExpr>, element: NativeType)
    case mergeSetElement(ArraySlice<CompiledStateExpr>, previous: NativeType)
    case dictionary
    case result(NativeType)
    case discard
}

/// Derives native shapes from the resolved formal program and source hints.
/// Empty collection holes are refined by assignments before admission completes.
struct NativeTypeInference: Sendable {
    /// Shared immutable inputs stay outside lexical scope snapshots.
    private final class Inputs: Sendable {
        let plan: NativeMachinePlan
        let sourceTypes: NativeSourceTypeMetadata
        let namedDomains: [String: Set<CompiledValue>]
        let namedRepresentations: [String: NativeType]

        init(plan: NativeMachinePlan, sourceTypes: NativeSourceTypeMetadata) throws {
            self.plan = plan
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

    private(set) var variables: [VariableID: NativeType] = [:]
    private(set) var bindings: [BinderID: NativeType] = [:]
    private(set) var collectionDomains: [VariableID: Set<CompiledValue>] = [:]
    private let inputs: Inputs
    var namedDomains: [String: Set<CompiledValue>] { inputs.namedDomains }
    var namedRepresentations: [String: NativeType] { inputs.namedRepresentations }
    private var sourceTypes: NativeSourceTypeMetadata { inputs.sourceTypes }
    private var plan: NativeMachinePlan { inputs.plan }
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
    fileprivate var callbackIdentities: [OperatorID: NativeCallbackIdentity] {
        boundOperators.mapValues(\.identity)
    }

    func isOperatorParameter(_ id: OperatorID) -> Bool { boundOperators[id] != nil }

    private mutating func recordCallback(_ id: OperatorID, call: NativeOperatorCall) {
        if !(callbackUses[id] ?? []).contains(where: { existing in
            existing.result == call.result && existing.parameters.map { existing.inference.bindings[$0] } == call.parameters.map { call.inference.bindings[$0] }
        }) {
            callbackUses[id, default: []].append(call)
        }
    }

    init(plan: NativeMachinePlan, sourceTypes: NativeSourceTypeMetadata = .init()) throws {
        inputs = try Inputs(plan: plan, sourceTypes: sourceTypes)
        for variable in plan.variables {
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
        for action in plan.actions {
            let collection = action.collection.flatMap { id in plan.variables.first { $0.id == id }?.collection }
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
        while true {
            let previousVariables = variables
            let previousBindings = bindings
            let previousOperators = specializationResults
            for initialization in plan.initializations {
                let expected = variables[initialization.variable] ?? .unknown
                let inferred: NativeType
                switch initialization.initialization {
                case .value(let value): inferred = try literal(value, expected: expected)
                case .expression(let expression): inferred = try infer(expression, expected: expected)
                case .memberOf(let domain):
                    inferred = try element(infer(domain, expected: .set(expected)))
                }
                variables[initialization.variable] = try Self.merge(expected, inferred)
            }
            for action in plan.actions {
                do { try actionTypes(action.body) }
                catch let diagnostic as CompilationDiagnostic {
                    let name = plan.actionLayouts.first { $0.id == action.id }?.declaration.name ?? String(action.id.ordinal)
                    throw Self.diagnostic("actions.\(name)", causedBy: diagnostic)
                }
            }
            for invariant in plan.invariants {
                do { _ = try infer(invariant.body, expected: .bool) }
                catch let diagnostic as CompilationDiagnostic {
                    throw Self.diagnostic("invariants.\(invariant.name)", causedBy: diagnostic)
                }
            }
            if let constraint = plan.constraint { _ = try infer(constraint, expected: .bool) }
            if let assume = plan.assume { _ = try infer(assume, expected: .bool) }
            if variables == previousVariables && bindings == previousBindings && specializationResults == previousOperators { break }
        }
        for variable in plan.variables {
            guard let type = variables[variable.id], type.resolved else {
                throw Self.unresolvedDiagnostic(variables[variable.id] ?? .unknown,
                    at: "variables.\(variable.declaration.name)")
            }
        }
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
        var matches: [(scope: NativeTypeInference, checked: NativeCheckedType)] = []
        for alternative in alternatives {
            var candidate = self
            if let checked = try? candidate.inferExpression(expression, expected: alternative) {
                matches.append((candidate, checked))
            }
        }
        guard matches.count == 1, let match = matches.first else {
            throw Self.diagnostic("union", "expression must belong to exactly one declared union alternative")
        }
        self = match.scope
        return .init(type: expected, computationType: match.checked.type,
            operandTypes: match.checked.operandTypes, call: match.checked.call)
    }

    func resolutionScope(_ expression: CompiledStateExpr, expected: NativeType?) throws -> (scope: NativeTypeInference, resultType: NativeType, computationType: NativeType, operandTypes: [NativeType], call: NativeOperatorCall?) {
        var scope = self
        let resolved = try scope.inferExpression(expression, expected: expected ?? .unknown)
        let result = resolved.type
        guard result.resolved else {
            throw Self.unresolvedDiagnostic(result, at: "resolution")
        }
        guard resolved.computationType.resolved else {
            throw Self.unresolvedDiagnostic(resolved.computationType, at: "resolution")
        }
        return (scope, result, resolved.computationType, resolved.operandTypes, resolved.call)
    }

    func type(of expression: CompiledStateExpr, expected: NativeType? = nil) throws -> NativeType {
        var inference = self
        let result = try inference.infer(expression, expected: expected ?? .unknown)
        guard result.resolved else { throw Self.unresolvedDiagnostic(result, at: "expression") }
        return result
    }

    private mutating func membershipElement(value: CompiledStateExpr, domain: CompiledStateExpr) throws -> NativeType {
        // Either operand may carry nominal evidence: a stored domain or a
        // selected field tested against a literal domain. Validate both under
        // that shared context without replacing stored representations.
        let domainElement = try element(infer(domain, expected: .set(.unknown)))
        let candidate = try infer(value)
        let context = try Self.operandContext(domainElement, candidate)
        if candidate != context { _ = try infer(value, expected: context) }
        if domainElement != context {
            return try element(infer(domain, expected: .set(context)))
        }
        return domainElement
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

    private mutating func inferProjectionSource(_ value: CompiledStateExpr, index: Int, expected: NativeType) throws -> NativeType {
        let members: [CompiledStateExpr]?
        switch value {
        case .tupleLiteral(let expressions): members = expressions
        case .value(.tuple(let values)): members = values.map(CompiledStateExpr.value)
        default: members = nil
        }
        if let members {
            guard index >= 1, index <= members.count else { throw Self.diagnostic("tupleAccess", "index outside tuple literal") }
            var elements: [NativeType] = []
            for (offset, member) in members.enumerated() {
                elements.append(try infer(member, expected: offset == index - 1 ? expected : .unknown))
            }
            return .tuple(elements)
        }
        let type = try infer(value)
        if case .tuple(var elements) = type {
            guard index >= 1, index <= elements.count else { throw Self.diagnostic("tupleAccess", "index outside tuple shape") }
            elements[index - 1] = try projectionStorageType(elements[index - 1], expected: expected)
            return try infer(value, expected: .tuple(elements))
        }
        return try inferSequence(value, element: expected)
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

    private func projectionStorageType(_ source: NativeType, expected: NativeType) throws -> NativeType {
        if canProjectRead(source, to: expected) { return source }
        return try Self.operandContext(source, expected)
    }

    private mutating func inferRecordProjectionSource(
        _ value: CompiledStateExpr, key: CompiledValue, expected: NativeType
    ) throws -> NativeType {
        let source = try infer(value)
        if source == .unknown { return .unknown }
        guard case .string(let name) = key, case .record(var fields) = source,
              let index = fields.firstIndex(where: { $0.name == name }) else {
            throw Self.diagnostic("recordAccess", "unknown record field")
        }
        fields[index] = .init(name: name, type: try projectionStorageType(fields[index].type, expected: expected))
        // Keep every sibling in the contextual shape. The source expression
        // must prove the selected field's nominal domain; stored raw data
        // cannot acquire a different representation from a projection alone.
        return try infer(value, expected: .record(fields))
    }

    private mutating func inferDomainSource(_ expression: CompiledStateExpr, expected: NativeType) throws -> NativeType {
        let source = try infer(expression)
        guard case .set(let element) = expected,
              case .dictionary(let key, let value) = source else { return source }
        let context = try projectionStorageType(key, expected: element)
        guard context != key else { return source }
        return try infer(expression, expected: .dictionary(context, value))
    }

    private mutating func inferSequence(_ expression: CompiledStateExpr, element expected: NativeType = .unknown) throws -> NativeType {
        let source = try infer(expression)
        switch source {
        case .array(let element):
            guard expected != .unknown, expected != element else { return source }
            return try infer(expression, expected: .array(expected))
        case .dictionary(.int, let element):
            guard expected != .unknown, expected != element else { return source }
            return try infer(expression, expected: .dictionary(.int, expected))
        case .unknown:
            return try infer(expression, expected: .array(expected))
        default: throw Self.diagnostic("sequence", "expected an array or integer-keyed function, received \(source.swiftType)")
        }
    }

    private func sequenceElementType(_ source: NativeType) throws -> NativeType {
        switch source {
        case .array(let element), .dictionary(.int, let element): return element
        default: throw Self.diagnostic("sequence", "invalid sequence representation")
        }
    }

    fileprivate static func diagnostic(_ path: String, _ actual: String) -> CompilationDiagnostic {
        .init(code: .unsupportedGeneratedValueShape, stage: .lowering,
              path: "nativeMachine.\(path)", expected: "a statically resolved native Swift value shape",
              actual: actual, nextSafeAction: "Use a concrete typed value and an operation supported by native machine generation.")
    }

    private static func unresolvedDiagnostic(_ type: NativeType, at path: String) -> CompilationDiagnostic {
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

    private mutating func actionTypes(_ action: CompiledActionExpr) throws {
        switch action {
        case .assign(let id, let expression):
            variables[id] = try Self.merge(variables[id] ?? .unknown, infer(expression, expected: variables[id] ?? .unknown))
        case .unchanged: break
        case .guard_(let expression): _ = try infer(expression, expected: .bool)
        case .and(let lhs, let rhs), .or(let lhs, let rhs): try actionTypes(lhs); try actionTypes(rhs)
        case .ifElse(let condition, let lhs, let rhs):
            _ = try infer(condition, expected: .bool); try actionTypes(lhs); try actionTypes(rhs)
        case .define(let id, let value, let body):
            bindingSources[id] = .setLiteral([value])
            bindingDomains[id] = literalValues(value)
            bindings[id] = try infer(value, expected: bindings[id] ?? .unknown); try actionTypes(body)
        case .existsAction(let id, let domain, let body):
            bindingSources[id] = domain
            bindingDomains[id] = literalDomain(domain)
            bindings[id] = try element(infer(domain, expected: .set(bindings[id] ?? .unknown))); try actionTypes(body)
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
        _ captures: [BinderID: NativeType], using resolved: NativeTypeInference
    ) -> [NativeExpressionCheckTask] {
        captures.compactMap { binder, original in
            guard let refined = resolved.bindings[binder], refined != original else { return nil }
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
        let captures: [BinderID: NativeType]
        switch operation {
        case .lambda(let lambda):
            formalParameters = lambda.parameters.map { .value($0) }
            body = lambda.body; domain = nil; captures = bindings
        case .reference(let id, _):
            captures = localCaptures[id] ?? [:]
            if let definition = plan.formalOperatorDefinitions.first(where: { $0.id == id }) {
                formalParameters = definition.parameters; body = definition.body; domain = nil
            } else if let definition = localOperators[id] {
                formalParameters = definition.parameters.map { .value($0) }
                body = definition.body; domain = definition.domain
            } else if let definition = plan.recursiveFunctions.first(where: { $0.id == id }) {
                formalParameters = definition.parameters.map { .value($0) }
                body = definition.body; domain = nil
            } else { throw Self.diagnostic("operator", "unknown operator identity \(id.ordinal)") }
        }
        guard formalParameters.count == arguments.count else { throw Self.diagnostic("operator", "argument count mismatch") }
        var callbackArguments: [OperatorID: CompiledFormalOperator] = [:]
        var identities = callbackIdentities
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
            resultContext: expected, captures: captures, callbacks: identities)
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
            return .recursive(.init(specialization: key, parameters: parameters, body: body, domain: domain,
                result: context, inference: self, callbackUses: callbackUses, callbackArguments: callbackArguments))
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

    private func isOperatorApplication(_ expression: CompiledStateExpr) -> Bool {
        switch expression {
        case .operatorApplication, .recursiveCall, .lambdaApplication,
             .functionApply(.operatorReference, _): return true
        default: return false
        }
    }

    private mutating func infer(_ expression: CompiledStateExpr, expected: NativeType = .unknown) throws -> NativeType {
        switch expression {
        case .boundValue, .letValue, .letIn, .and, .or, .not, .ifThenElse, .functionLiteral,
             .setMap, .forAll, .exists, .add, .subtract, .multiply, .divide,
             .integerDivide, .modulo, .negate, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
             .integerRange, .equal, .notEqual, .subset, .union, .intersection, .setDifference, .setLiteral:
            return try inferStructuredExpression(expression, expected: expected).type
        default: break
        }
        if isOperatorApplication(expression) {
            return try inferStructuredExpression(expression, expected: expected).type
        }
        do {
            return try inferResolved(expression, expected: expected).type
        } catch let diagnostic as CompilationDiagnostic {
            throw annotated(diagnostic, at: expression)
        }
    }

    private mutating func inferExpression(
        _ expression: CompiledStateExpr, expected: NativeType = .unknown
    ) throws -> NativeCheckedType {
        if isOperatorApplication(expression) {
            let checked = try inferStructuredExpression(expression, expected: expected)
            return checked
        }
        let checked: NativeCheckedType
        switch expression {
        case .boundValue, .letValue, .letIn, .and, .or, .not, .ifThenElse, .functionLiteral,
             .setMap, .forAll, .exists, .add, .subtract, .multiply, .divide,
             .integerDivide, .modulo, .negate, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
             .integerRange, .equal, .notEqual, .subset, .union, .intersection, .setDifference, .setLiteral:
            checked = try inferStructuredExpression(expression, expected: expected)
        default:
            do { checked = try inferResolved(expression, expected: expected) }
            catch let diagnostic as CompilationDiagnostic { throw annotated(diagnostic, at: expression) }
        }
        return checked
    }

    private func annotated(_ diagnostic: CompilationDiagnostic, at expression: CompiledStateExpr) -> CompilationDiagnostic {
        let location: String
        switch expression {
        case .boundValue(let id): location = "binder[\(id.ordinal)]"
        case .stateVariable(let id): location = "variable[\(plan.variables.first { $0.id == id }?.declaration.name ?? String(id.ordinal))]"
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
            if activeArgumentRefinements.insert(refinement).inserted {
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
           activeBindingRefinements.insert(id).inserted {
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
        if case .tuple(let hints) = expected, hints.count == expressions.count {
            let types = try zip(expressions, hints).map { try infer($0, expected: $1) }
            result = .tuple(types)
        } else {
            let hint: NativeType = if case .array(let value) = expected { value } else { .unknown }
            let types = try expressions.map { try infer($0, expected: hint) }
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
        return .init(type: checked.type, computationType: checked.computationType, operandTypes: operands)
    }

    private mutating func inferRecordLiteral(_ record: CompiledRecordExpression, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let hints: [NativeField] = if case .record(let fields) = expected { fields } else { [] }
        let fields = try record.fields.map { field -> NativeField in
            guard case .string(let name) = field.key else { throw Self.diagnostic("record", "non-string field") }
            let expectedType = hints.first { $0.name == name }?.type ?? .unknown
            return .init(name: name, type: try infer(field.value, expected: expectedType))
        }
        result = .record(fields.sorted { $0.name < $1.name })
        return try checkedType(result, expected: expected, operandTypes: fields.map(\.type))
    }

    private mutating func inferFunctionApplication(_ function: CompiledStateExpr, key: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let base = try infer(function)
        let functionType: NativeType
        if base == .unknown { functionType = try infer(function, expected: .dictionary(infer(key), expected)) }
        else { functionType = base }
        var sourceType = functionType
        let keyType: NativeType
        switch functionType {
        case .dictionary(let domain, let value):
            keyType = domain
            _ = try infer(key, expected: domain)
            result = try Self.operandContext(value, expected)
            sourceType = .dictionary(domain, result)
        case .array(let value):
            keyType = .int
            _ = try infer(key, expected: .int)
            result = try Self.operandContext(value, expected)
            sourceType = .array(result)
        case .tuple(let elements):
            keyType = .int
            _ = try infer(key, expected: .int)
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
            keyType = .string
            _ = try infer(key, expected: .string)
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
        if sourceType != functionType {
            sourceType = try infer(function, expected: sourceType)
        }
        return try checkedType(result, expected: expected, operandTypes: [sourceType, keyType])
    }

    private mutating func inferFunctionUpdate(_ function: CompiledStateExpr, key: CompiledStateExpr, value: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let keyType: NativeType
        let valueType: NativeType
        let base = try infer(function, expected: expected)
        switch base {
        case .array(let item):
            keyType = try infer(key, expected: .int)
            valueType = try infer(value, expected: item)
            result = .array(valueType)
        case .dictionary(let domain, let item):
            keyType = try infer(key, expected: domain)
            valueType = try infer(value, expected: item)
            result = .dictionary(domain, valueType)
        case .record(let fields):
            keyType = try infer(key, expected: .string)
            if case .value(.string(let name)) = key {
                valueType = try infer(value, expected: fields.first { $0.name == name }?.type ?? .unknown)
            } else {
                let replacementType = fields.first?.type ?? .unknown
                guard fields.allSatisfy({ $0.type == replacementType }) else {
                    throw Self.diagnostic("except", "dynamic record keys require homogeneous field types")
                }
                valueType = try infer(value, expected: replacementType)
            }
            result = base
        case .unknown:
            keyType = try infer(key)
            valueType = try infer(value)
            result = .dictionary(keyType, valueType)
        default: throw Self.diagnostic("except", "unsupported update shape \(base.swiftType)")
        }
        let checked = try checkedType(result, expected: expected)
        return .init(type: checked.type, computationType: checked.computationType,
            operandTypes: [checked.computationType, keyType, valueType])
    }

    private mutating func inferSequenceSelection(_ sequence: CompiledStateExpr, binder id: BinderID, predicate: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let hint: NativeType = if case .array(let item) = expected { item } else { .unknown }
        let initial = try inferSequence(sequence)
        let item = try projectionStorageType(sequenceElementType(initial), expected: hint)
        _ = try inferSequence(sequence, element: item)
        bindings[id] = item
        // Literal members can supply finite nominal evidence; an arbitrary
        // sequence initializer never proves the domain of stored values.
        switch sequence {
        case .value(.tuple(let members)): bindingDomains[id] = Set(members)
        case .tupleLiteral(let members): bindingDomains[id] = literalDomain(.setLiteral(members))
        default: bindingDomains.removeValue(forKey: id)
        }
        _ = try infer(predicate, expected: .bool)
        let selected = bindings[id] ?? item
        let source = try inferSequence(sequence, element: selected)
        result = .array(selected)
        return try checkedType(result, expected: expected, operandTypes: [source, .bool])
    }

    private mutating func inferSetFilter(_ domain: CompiledStateExpr, binder id: BinderID, predicate: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        bindingSources[id] = domain
        bindingDomains[id] = literalDomain(domain)
        let initial = try infer(domain, expected: expected == .unknown ? .set(.unknown) : expected)
        bindings[id] = try element(initial); _ = try infer(predicate, expected: .bool)
        let refined = bindings[id] ?? .unknown
        result = try infer(domain, expected: .set(refined))
        // A predicate can prove a stronger nominal representation than an
        // earlier raw context. Its collection retains that representation.
        return .init(type: result, computationType: result, operandTypes: [result, .bool])
    }

    private mutating func inferChoice(_ domain: CompiledStateExpr, binder id: BinderID, predicate body: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        bindingSources[id] = domain
        bindingDomains[id] = literalDomain(domain)
        let initial = try element(infer(domain, expected: .set(expected))); bindings[id] = initial
        _ = try infer(body, expected: .bool)
        let source = try infer(domain, expected: .set(bindings[id] ?? initial))
        result = try element(source)
        return .init(type: result, computationType: result, operandTypes: [source, .bool])
    }

    private mutating func inferFunctionSet(_ domain: CompiledStateExpr, range: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let candidate: NativeType = if case .set(let value) = expected { value } else { .unknown }
        let hint: NativeType = candidate == .unknown ? .dictionary(.unknown, .unknown) : candidate
        guard case .dictionary(let key, let value) = hint else { throw Self.diagnostic("functionSet", "expected set of dictionaries") }
        let inferredKey = try element(infer(domain, expected: .set(key)))
        let inferredValue = try element(infer(range, expected: .set(value)))
        result = .set(.dictionary(inferredKey, inferredValue))
        return try checkedType(result, expected: expected, operandTypes: [.set(inferredKey), .set(inferredValue)])
    }

    private mutating func inferFold(_ operation: CompiledFormalLambda, initial: CompiledStateExpr, sequence: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        guard operation.parameters.count == 2 else { throw Self.diagnostic("fold", "expected two lambda parameters") }
        let accumulator = try infer(initial, expected: expected)
        bindings[operation.parameters[1]] = accumulator
        let source = try inferSequence(sequence)
        bindings[operation.parameters[0]] = try sequenceElementType(source)
        result = try infer(operation.body, expected: accumulator)
        _ = try infer(initial, expected: result)
        return try checkedType(result, expected: expected, operandTypes: [result, result, source])
    }

    private mutating func inferSequenceOperation(_ expression: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        switch expression {
        case .tupleDynamicAccess(let value, let index):
            _ = try infer(index, expected: .int)
            let source = try inferSequence(value, element: expected)
            result = try sequenceElementType(source)
            return try checkedType(result, expected: expected, operandTypes: [source, .int])
        case .tupleLength(let value):
            let initial = try infer(value)
            let source: NativeType
            if case .tuple = initial { source = initial }
            else { source = try inferSequence(value) }
            return try checkedType(.int, expected: expected, operandTypes: [source])
        case .tupleHead(let value):
            let source = try inferSequence(value, element: expected)
            result = try sequenceElementType(source)
            return try checkedType(result, expected: expected, operandTypes: [source])
        case .tupleTail(let value):
            let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
            let source = try inferSequence(value, element: hint)
            result = .array(try sequenceElementType(source))
            return try checkedType(result, expected: expected, operandTypes: [source])
        case .tupleRemoving(let sequence, let index):
            let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
            let source = try inferSequence(sequence, element: hint)
            result = .array(try sequenceElementType(source))
            _ = try infer(index, expected: .int)
            return try checkedType(result, expected: expected, operandTypes: [source, .int])
        default:
            throw Self.diagnostic("sequence", "expected a sequence access, length, tail, or removal")
        }
    }

    private mutating func inferAppend(_ sequence: CompiledStateExpr, value: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
        let item = try sequenceElementType(inferSequence(sequence, element: hint))
        let appended = try infer(value, expected: item)
        let elementType = try Self.merge(item, appended)
        let source = try inferSequence(sequence, element: elementType)
        _ = try infer(value, expected: elementType)
        result = .array(elementType)
        return try checkedType(result, expected: expected, operandTypes: [source, elementType])
    }

    private mutating func inferConcatenation(_ a: CompiledStateExpr, _ b: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
        let left = try sequenceElementType(inferSequence(a, element: hint))
        let right = try sequenceElementType(inferSequence(b, element: left))
        let elementType = try Self.merge(left, right)
        let leftSource = try inferSequence(a, element: elementType)
        let rightSource = try inferSequence(b, element: elementType)
        result = .array(elementType)
        return try checkedType(result, expected: expected, operandTypes: [leftSource, rightSource])
    }

    private mutating func inferTupleAccess(_ value: CompiledStateExpr, index: Int, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let shape = try inferProjectionSource(value, index: index, expected: expected)
        if case .tuple(let elements) = shape { result = elements[index - 1] }
        else { result = try sequenceElementType(shape) }
        return try checkedType(result, expected: expected, operandTypes: [shape])
    }

    private mutating func inferRecordAccess(_ record: CompiledStateExpr, key: CompiledValue, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let source = try inferRecordProjectionSource(record, key: key, expected: expected)
        if case .string(let name) = key, case .record(let fields) = source,
           let field = fields.first(where: { $0.name == name }) { result = field.type }
        else { result = .unknown }
        return try checkedType(result, expected: expected, operandTypes: [source])
    }

    private mutating func inferDomain(_ function: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        let result: NativeType
        let source = try inferDomainSource(function, expected: expected)
        switch source {
        case .dictionary(let key, _): result = .set(key)
        case .array, .tuple: result = .set(.int)
        case .record: result = .set(.string)
        case .unknown: result = .set(.unknown)
        default: throw Self.diagnostic("domain", "unsupported domain shape")
        }
        return try checkedType(result, expected: expected, operandTypes: [source])
    }

    /// Visit operands in source order and retain ancestry for diagnostics.
    private mutating func inferStructuredExpression(_ expression: CompiledStateExpr, expected: NativeType) throws -> NativeCheckedType {
        // Tasks are appended in reverse execution order.
        var pending: [NativeExpressionCheckTask] = [.check(expression, expected: expected)]
        var results: [NativeType] = []
        var ancestors: [CompiledStateExpr] = []
        var completed: NativeCheckedType?
        var suspendedScopes: [NativeTypeInference] = []
        var checkedCalls: [NativeOperatorCall] = []
        let initialArgumentRefinements = activeArgumentRefinements
        let initialBindingRefinements = activeBindingRefinements
        do {
            while let task = pending.popLast() {
                switch task {
                case .check(let expression, let expected):
                    if case .union = expected {
                        switch expression {
                        case .functionLiteral, .setLiteral, .union, .intersection, .setDifference:
                            ancestors.append(expression)
                            if let checked = try checkUnionConstructor(expression, expected: expected) {
                                results.append(checked.type)
                                completed = checked
                                ancestors.removeLast()
                                continue
                            }
                            ancestors.removeLast()
                        default: break
                        }
                    }
                    switch expression {
                    case .operatorApplication(let id, let arguments):
                        ancestors.append(expression)
                        pending.append(.call(expression, .reference(id, arity: arguments.count), arguments, expected: expected))
                    case .recursiveCall(let id, let arguments):
                        ancestors.append(expression)
                        pending.append(.call(expression, .reference(id, arity: arguments.count), arguments.map { .value($0) }, expected: expected))
                    case .lambdaApplication(let lambda, let arguments):
                        ancestors.append(expression)
                        pending.append(.call(expression, .lambda(lambda), arguments.map { .value($0) }, expected: expected))
                    case .functionApply(.operatorReference(let id), let argument):
                        ancestors.append(expression)
                        pending.append(.call(expression, .reference(id, arity: 1), [.value(argument)], expected: expected))
                    case .setLiteral(let elements):
                        ancestors.append(expression)
                        let hint: NativeType = if case .set(let item) = expected { item } else { .unknown }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .setElements(elements[...], element: hint),
                        ])
                    case .boundValue(let id):
                        ancestors.append(expression)
                        switch try checkBoundValue(id, expected: expected) {
                        case .checked(let checked):
                            results.append(checked.type)
                            completed = checked
                            ancestors.removeLast()
                        case .argument(let source, let refinement):
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
                            pending.append(contentsOf: [
                                .finishBindingDomain(id),
                                .check(domain, expected: .set(expected)),
                            ])
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
                        pending.append(contentsOf: [
                            .finish(expected: expected), .result(result),
                            .discard, .check(rhs, expected: .int),
                            .discard, .check(lhs, expected: .int),
                        ])
                    case .negate(let operand):
                        ancestors.append(expression)
                        pending.append(contentsOf: [
                            .finish(expected: expected), .result(.int),
                            .discard, .check(operand, expected: .int),
                        ])
                    case .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .subset(let lhs, let rhs):
                        ancestors.append(expression)
                        if case .subset = expression { pending.append(.subset(expected: expected)) }
                        else { pending.append(.comparison(expected: expected)) }
                        pending.append(contentsOf: [
                            .reconcile(lhs, rhs, expected: .unknown),
                            .check(rhs, expected: .unknown),
                            .check(lhs, expected: .unknown),
                        ])
                    case .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs):
                        ancestors.append(expression)
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .setOperands(lhs, rhs, expected: expected),
                            .reconcile(lhs, rhs, expected: .unknown),
                            .check(rhs, expected: .unknown),
                            .check(lhs, expected: .unknown),
                        ])
                    case .ifThenElse(let condition, let yes, let no):
                        ancestors.append(expression)
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .reconcile(yes, no, expected: expected),
                            .check(no, expected: expected),
                            .check(yes, expected: expected),
                            .discard,
                            .check(condition, expected: .bool),
                        ])
                    case .and(let lhs, let rhs), .or(let lhs, let rhs):
                        ancestors.append(expression)
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .result(.bool),
                            .discard,
                            .check(rhs, expected: .bool),
                            .discard,
                            .check(lhs, expected: .bool),
                        ])
                    case .not(let operand):
                        ancestors.append(expression)
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .result(.bool),
                            .discard,
                            .check(operand, expected: .bool),
                        ])
                    case .letValue(let id, let value, let body):
                        ancestors.append(expression)
                        bindingSources[id] = .setLiteral([value])
                        bindingDomains[id] = literalValues(value)
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .check(body, expected: expected),
                            .bind(id),
                            .check(value, expected: bindings[id] ?? .unknown),
                        ])
                    case .letIn(let definitions, let body):
                        ancestors.append(expression)
                        for definition in definitions { localOperators[definition.id] = definition }
                        for definition in definitions {
                            let captures = capturedBindings(of: definition)
                            localCaptures[definition.id] = bindings.filter { captures.contains($0.key) }
                        }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .check(body, expected: expected),
                        ])
                    case .functionLiteral(let domain, let id, let body):
                        ancestors.append(expression)
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        let hints: (key: NativeType, value: NativeType)
                        if case .dictionary(let key, let value) = expected { hints = (key, value) }
                        else { hints = (.unknown, .unknown) }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .dictionary,
                            .check(body, expected: hints.value),
                            .bindDomain(id, retainElement: true),
                            .check(domain, expected: .set(hints.key)),
                        ])
                    case .setMap(let body, let id, let domain):
                        ancestors.append(expression)
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        let hint: NativeType = if case .set(let item) = expected { item } else { .unknown }
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .set,
                            .check(body, expected: hint),
                            .bindDomain(id, retainElement: false),
                            .check(domain, expected: .set(.unknown)),
                        ])
                    case .forAll(let domain, let id, let body), .exists(let domain, let id, let body):
                        ancestors.append(expression)
                        bindingSources[id] = domain
                        bindingDomains[id] = literalDomain(domain)
                        pending.append(contentsOf: [
                            .finish(expected: expected),
                            .result(.bool),
                            .discard,
                            .check(body, expected: .bool),
                            .bindDomain(id, retainElement: false),
                            .check(domain, expected: .set(.unknown)),
                        ])
                    default:
                        results.append(try infer(expression, expected: expected))
                    }
                case .call(let expression, let operation, let arguments, let expected):
                    pending.append(.enterCall(expression, operation, arguments, expected: expected))
                    for argument in arguments.reversed() {
                        switch argument {
                        case .value(let value): pending.append(.check(value, expected: .unknown))
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
                    guard let result = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked operator body")
                    }
                    specializationResults[operation.specialization] = try Self.operandContext(operation.context, result)
                    let scoped = self
                    activeOperators.remove(operation.specialization)
                    checkedCalls.append(.init(specialization: operation.specialization, parameters: operation.parameters,
                        body: operation.body, domain: operation.domain, result: result, inference: scoped,
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
                    let values = zip(call.arguments, call.checkedArguments).compactMap { argument, checked -> (CompiledStateExpr, NativeType)? in
                        guard case .value(let value) = argument, case .value(let type, _, _) = checked else { return nil }
                        return (value, type)
                    }
                    for (argument, parameter) in zip(values, resolved.parameters).reversed() {
                        let refined = resolved.inference.bindings[parameter] ?? .unknown
                        if argument.1 != refined {
                            pending.append(contentsOf: [.discard, .check(argument.0, expected: refined)])
                        }
                    }
                case .refineCallCaptures(let operation, let resolved):
                    var checks: [NativeExpressionCheckTask] = []
                    if case .reference(let id, _) = operation, let captures = localCaptures[id] {
                        checks.append(contentsOf: capturedValueChecks(captures, using: resolved.inference))
                    }
                    for (parameter, uses) in resolved.callbackUses {
                        guard resolved.callbackArguments[parameter] != nil,
                              let binding = resolved.inference.boundOperators[parameter],
                              binding.forwardedFrom == nil else { continue }
                        let parameters: Set<BinderID>
                        if case .lambda(let lambda) = binding.operation { parameters = Set(lambda.parameters) }
                        else { parameters = [] }
                        let captures = binding.scope.bindings.filter { !parameters.contains($0.key) }
                        for use in uses { checks.append(contentsOf: capturedValueChecks(captures, using: use.inference)) }
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
                        } else if let origin = resolved.inference.boundOperators[parameter]?.forwardedFrom {
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
                    completed = checked
                    ancestors.removeLast()
                case .finishArgument(let id, let refinement):
                    guard let refined = results.popLast(), var caller = suspendedScopes.popLast() else {
                        throw Self.diagnostic("checking", "missing suspended argument context")
                    }
                    caller.specializationResults.merge(specializationResults) { _, current in current }
                    caller.bindings[id] = refined
                    caller.activeArgumentRefinements.remove(refinement)
                    self = caller
                    results.append(refined)
                    completed = .init(type: refined, computationType: refined)
                    ancestors.removeLast()
                case .finishBindingDomain(let id):
                    guard let domain = results.popLast() else {
                        throw Self.diagnostic("checking", "missing refined binding domain")
                    }
                    let refined = try element(domain)
                    bindings[id] = refined
                    activeBindingRefinements.remove(id)
                    results.append(refined)
                    completed = .init(type: refined, computationType: refined)
                    ancestors.removeLast()
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
                case .set:
                    guard let item = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked set element")
                    }
                    results.append(.set(item))
                case .setElements(var remaining, let element):
                    if let next = remaining.popFirst() {
                        pending.append(contentsOf: [
                            .mergeSetElement(remaining, previous: element),
                            .check(next, expected: element),
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
                    pending.append(.result(context))
                    // Recheck only branches whose context changed, preserving
                    // the same left-to-right order as initial branch checking.
                    if context != expected {
                        if right != context {
                            pending.append(contentsOf: [
                                .discard,
                                .check(no, expected: context),
                            ])
                        }
                        if left != context {
                            pending.append(contentsOf: [
                                .discard,
                                .check(yes, expected: context),
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
                        .check(rhs, expected: context),
                        .discard, .check(lhs, expected: context),
                    ])
                case .comparison(let expected), .subset(let expected):
                    guard let context = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked comparison operands")
                    }
                    if case .subset = task { _ = try element(context) }
                    let checked = try checkedType(.bool, expected: expected, operandTypes: [context, context])
                    results.append(checked.type)
                    completed = checked
                    ancestors.removeLast()
                case .finish(let expected):
                    guard let result = results.popLast() else {
                        throw Self.diagnostic("checking", "missing checked expression type")
                    }
                    let checked = try checkedType(result, expected: expected)
                    results.append(checked.type)
                    completed = checked
                    ancestors.removeLast()
                case .result(let type):
                    results.append(type)
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
        let result: NativeType
        var type = expected
        for branch in [first] + rest { _ = try infer(branch.condition, expected: .bool); type = try infer(branch.value, expected: type) }
        if let otherwise { type = try infer(otherwise, expected: type) }; result = type
        return try checkedType(result, expected: expected)
    }

    private mutating func inferResolved(_ expression: CompiledStateExpr, expected: NativeType = .unknown) throws -> NativeCheckedType {
        if case .union = expected, let checked = try checkUnionConstructor(expression, expected: expected) {
            return checked
        }
        let result: NativeType
        switch expression {
        case .assertView(let value, let shape):
            let source = try infer(value)
            result = try viewType(shape)
            return try checkedType(result, expected: expected, operandTypes: [source])
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
            let item = try membershipElement(value: value, domain: domain)
            let checked = try checkedType(.bool, expected: expected)
            return .init(type: checked.type, computationType: checked.computationType, operandTypes: [item, .set(item)])
        case .cardinality(let value):
            let source = try infer(value, expected: .set(.unknown))
            return try checkedType(.int, expected: expected, operandTypes: [source])
        case .sequenceSelect(let sequence, let id, let predicate):
            return try inferSequenceSelection(sequence, binder: id, predicate: predicate, expected: expected)
        case .setFilter(let domain, let id, let predicate):
            return try inferSetFilter(domain, binder: id, predicate: predicate, expected: expected)
        case .choose(let domain, let id, let body):
            return try inferChoice(domain, binder: id, predicate: body, expected: expected)
        case .sequenceFromSet(let domain):
            let hint: NativeType = if case .array(let value) = expected { value } else { .unknown }
            let source = try infer(domain, expected: .set(hint))
            result = .array(try element(source))
            return try checkedType(result, expected: expected, operandTypes: [source])
        case .powerSet(let domain):
            let hint: NativeType = if case .set(let value) = expected { value } else { .set(.unknown) }
            let source = try infer(domain, expected: hint)
            result = .set(source)
            return try checkedType(result, expected: expected, operandTypes: [source])
        case .unionAll(let domain):
            let hint: NativeType = expected == .unknown ? .set(.unknown) : expected
            let source = try infer(domain, expected: .set(hint))
            result = try element(source)
            return try checkedType(result, expected: expected, operandTypes: [source])
        case .functionSet(let domain, let range):
            return try inferFunctionSet(domain, range: range, expected: expected)
        case .setSum(let function, let domain):
            let source = try infer(domain, expected: .set(.unknown))
            let key = try element(source)
            let operation = try infer(function, expected: .dictionary(key, .int))
            return try checkedType(.int, expected: expected, operandTypes: [operation, source])
        case .foldFunction(let operation, let initial, let sequence):
            return try inferFold(operation, initial: initial, sequence: sequence, expected: expected)
        case .tupleLiteral(let expressions): return try inferTupleLiteral(expressions, expected: expected)
        case .tupleAccess(let value, let index):
            return try inferTupleAccess(value, index: index, expected: expected)
        case .tupleDynamicAccess, .tupleLength, .tupleHead, .tupleTail, .tupleRemoving:
            return try inferSequenceOperation(expression, expected: expected)
        case .tupleAppend(let sequence, let value):
            return try inferAppend(sequence, value: value, expected: expected)
        case .tupleConcatenate(let a, let b):
            return try inferConcatenation(a, b, expected: expected)
        case .recordLiteral(let record): return try inferRecordLiteral(record, expected: expected)
        case .recordAccess(let record, _, let key):
            return try inferRecordAccess(record, key: key, expected: expected)
        case .functionApply(let function, let key): return try inferFunctionApplication(function, key: key, expected: expected)
        case .except(let function, let key, let value): return try inferFunctionUpdate(function, key: key, value: value, expected: expected)
        case .domain(let function):
            return try inferDomain(function, expected: expected)
        case .caseExpr(let first, let rest, let otherwise):
            return try inferCases(first, rest: rest, otherwise: otherwise, expected: expected)
        default: throw Self.diagnostic("expression", "expression is outside the native machine subset: \(expression.diagnosticName)")
        }
        return try checkedType(result, expected: expected)
    }
}
