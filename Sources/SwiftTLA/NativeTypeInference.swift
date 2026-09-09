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
    let operation: CompiledFormalOperator
    let arguments: [NativeType]
    let resultContext: NativeType
    let captures: [BinderID: NativeType]
    let callbacks: [OperatorID: NativeCallbackIdentity]
}

struct NativeCallbackIdentity: Hashable, Sendable {
    let operation: CompiledFormalOperator
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
        identity = .init(operation: operation, captures: scope.bindings, callbacks: scope.callbackIdentities)
    }

    init(forwarding binding: NativeCallbackBinding, from origin: OperatorID) {
        operation = binding.operation
        scope = binding.scope
        forwardedFrom = origin
        identity = binding.identity
    }
}

private struct NativeArgumentEvidence: Sendable {
    let expression: CompiledStateExpr
    let scope: NativeTypeInference
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

/// Derives native shapes once from the resolved formal program and source hints.
/// Empty collection holes are refined by assignments before admission completes.
struct NativeTypeInference: Sendable {
    static let maximumActiveSpecializations = 256

    private(set) var variables: [VariableID: NativeType] = [:]
    private(set) var bindings: [BinderID: NativeType] = [:]
    private(set) var collectionDomains: [VariableID: Set<CompiledValue>] = [:]
    private(set) var namedDomains: [String: Set<CompiledValue>] = [:]
    private(set) var namedRepresentations: [String: NativeType] = [:]
    private let sourceTypes: NativeSourceTypeMetadata
    private let plan: NativeMachinePlan
    private var bindingSources: [BinderID: CompiledStateExpr] = [:]
    private var argumentEvidence: [BinderID: NativeArgumentEvidence] = [:]
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
        self.plan = plan
        self.sourceTypes = sourceTypes
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
            namedRepresentations[name] = try represented.reduce(.unknown, Self.merge)
        }
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
                for binding in action.bindings {
                    let collection = action.collection.flatMap { id in plan.variables.first { $0.id == id }?.collection }
                    let hint: NativeType
                    if let variable = action.collection, let element = collection?.elementType {
                        hint = .collectionMember(variable, swiftType: "\(element).ID")
                    } else { hint = try binding.generatedSwiftType.map { try Self.declared($0, metadata: sourceTypes) } ?? .unknown }
                    let inferred = try binding.values.reduce(hint) { try Self.merge($0, literal($1, expected: hint)) }
                    bindingDomains[binding.binder] = Set(binding.values)
                    bindings[binding.binder] = try Self.merge(bindings[binding.binder] ?? .unknown, inferred)
                }
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

    private mutating func unionConstructor(_ expression: CompiledStateExpr, expected: NativeType) throws -> NativeType? {
        guard case .union(let alternatives) = expected else { return nil }
        switch expression {
        case .value, .setLiteral, .tupleLiteral, .recordLiteral, .functionLiteral: break
        default: return nil
        }
        var matches: [(NativeTypeInference, NativeType)] = []
        for alternative in alternatives {
            var candidate = self
            if let type = try? candidate.infer(expression, expected: alternative) {
                matches.append((candidate, type))
            }
        }
        guard matches.count == 1, let match = matches.first else {
            throw Self.diagnostic("union", "constructor must belong to exactly one declared union alternative")
        }
        self = match.0
        return match.1
    }

    func resolutionScope(_ expression: CompiledStateExpr, expected: NativeType?) throws -> (scope: NativeTypeInference, resultType: NativeType, computationType: NativeType) {
        var scope = self
        let result = try scope.infer(expression, expected: expected ?? .unknown)
        guard result.resolved else {
            throw Self.unresolvedDiagnostic(result, at: "resolution")
        }
        var intrinsicScope = scope
        if let constructor = try scope.unionConstructor(expression, expected: result) {
            return (scope, result, constructor)
        }
        let intrinsic = (try? intrinsicScope.infer(expression)) ?? result
        let computation = intrinsic.resolved && scope.canProjectRead(intrinsic, to: result) ? intrinsic : result
        return (scope, result, computation)
    }

    func functionApplicationSourceType(_ function: CompiledStateExpr, argument: CompiledStateExpr, expected: NativeType) throws -> NativeType {
        var scope = self
        let base = try scope.infer(function)
        let hint: NativeType
        switch base {
        case .array: hint = .array(expected)
        case .dictionary(let key, _): hint = .dictionary(key, expected)
        case .tuple(let elements):
            if case .value(.integer(let index)) = argument, index >= 1, index <= elements.count {
                var values = elements; values[index - 1] = expected; hint = .tuple(values)
            } else { hint = base }
        case .record(let fields):
            if case .value(.string(let name)) = argument {
                hint = .record(fields.map { .init(name: $0.name, type: $0.name == name ? expected : $0.type) })
            } else { hint = base }
        default: hint = base
        }
        return try scope.infer(function, expected: hint)
    }

    func type(of expression: CompiledStateExpr, expected: NativeType? = nil) throws -> NativeType {
        var inference = self
        let result = try inference.infer(expression, expected: expected ?? .unknown)
        guard result.resolved else { throw Self.unresolvedDiagnostic(result, at: "expression") }
        return result
    }

    func operandType(_ lhs: CompiledStateExpr, _ rhs: CompiledStateExpr) throws -> NativeType {
        var inference = self
        return try inference.comparisonOperands(lhs, rhs)
    }

    func membershipElementType(value: CompiledStateExpr, domain: CompiledStateExpr) throws -> NativeType {
        var inference = self
        return try inference.membershipElement(value: value, domain: domain)
    }

    private mutating func membershipElement(value: CompiledStateExpr, domain: CompiledStateExpr) throws -> NativeType {
        // Either operand may carry nominal evidence: a stored domain or a
        // selected field tested against a literal domain. Validate both under
        // that shared context without replacing stored representations.
        let domainElement = try element(infer(domain, expected: .set(.unknown)))
        let candidate = try infer(value)
        let context = try Self.operandContext(domainElement, candidate)
        _ = try infer(value, expected: context)
        return try element(infer(domain, expected: .set(context)))
    }

    private mutating func comparisonOperands(
        _ lhs: CompiledStateExpr, _ rhs: CompiledStateExpr, expected: NativeType = .unknown
    ) throws -> NativeType {
        let left = try infer(lhs, expected: expected)
        let right = try infer(rhs, expected: expected)
        let context = try Self.operandContext(left, right)
        _ = try infer(lhs, expected: context)
        _ = try infer(rhs, expected: context)
        return context
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

    func projectionSourceType(_ value: CompiledStateExpr, index: Int, expected: NativeType? = nil) throws -> NativeType {
        var inference = self
        let shape = try inference.inferProjectionSource(value, index: index, expected: expected ?? .unknown)
        guard shape.resolved else { throw Self.unresolvedDiagnostic(shape, at: "tupleAccess") }
        return shape
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

    private func projectedReadType(_ source: NativeType, expected: NativeType) throws -> NativeType {
        if canProjectRead(source, to: expected) { return expected }
        return try Self.merge(source, expected)
    }

    private func projectionStorageType(_ source: NativeType, expected: NativeType) throws -> NativeType {
        if canProjectRead(source, to: expected) { return source }
        return try Self.operandContext(source, expected)
    }

    func recordProjectionSourceType(
        _ value: CompiledStateExpr, key: CompiledValue, expected: NativeType? = nil
    ) throws -> NativeType {
        var inference = self
        let shape = try inference.inferRecordProjectionSource(value, key: key, expected: expected ?? .unknown)
        guard shape.resolved else { throw Self.unresolvedDiagnostic(shape, at: "recordAccess") }
        return shape
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

    func domainSourceType(_ expression: CompiledStateExpr, expected: NativeType) throws -> NativeType {
        var scope = self
        return try scope.inferDomainSource(expression, expected: expected)
    }

    private mutating func inferDomainSource(_ expression: CompiledStateExpr, expected: NativeType) throws -> NativeType {
        let source = try infer(expression)
        guard case .set(let element) = expected,
              case .dictionary(let key, let value) = source else { return source }
        let context = try projectionStorageType(key, expected: element)
        return try infer(expression, expected: .dictionary(context, value))
    }

    func sequenceSourceType(_ expression: CompiledStateExpr, element expected: NativeType = .unknown) throws -> NativeType {
        var inference = self
        return try inference.inferSequence(expression, element: expected)
    }

    private mutating func inferSequence(_ expression: CompiledStateExpr, element expected: NativeType = .unknown) throws -> NativeType {
        let source = try infer(expression)
        switch source {
        case .array(let element):
            return try infer(expression, expected: .array(expected == .unknown ? element : expected))
        case .dictionary(.int, let element):
            return try infer(expression, expected: .dictionary(.int, expected == .unknown ? element : expected))
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

    func operatorCall(
        _ id: OperatorID, arguments: [CompiledFormalCallArgument], expected: NativeType? = nil
    ) throws -> NativeOperatorCall {
        var inference = self
        return try inference.specializeCall(.reference(id, arity: arguments.count), arguments: arguments, expected: expected ?? .unknown)
    }

    func lambdaCall(
        _ lambda: CompiledFormalLambda, arguments: [CompiledStateExpr], expected: NativeType? = nil
    ) throws -> NativeOperatorCall {
        var inference = self
        return try inference.specializeCall(.lambda(lambda), arguments: arguments.map { .value($0) }, expected: expected ?? .unknown)
    }

    private mutating func inferCall(_ id: OperatorID, arguments: [CompiledFormalCallArgument], expected: NativeType) throws -> NativeType {
        try specializeCall(.reference(id, arity: arguments.count), arguments: arguments, expected: expected).result
    }

    private mutating func specializeCall(
        _ requestedOperation: CompiledFormalOperator, arguments: [CompiledFormalCallArgument], expected: NativeType
    ) throws -> NativeOperatorCall {
        let argumentTypes = try arguments.map { argument -> NativeType in
            if case .value(let value) = argument { return try infer(value) }
            return .unknown
        }
        let argumentDomains = arguments.map { argument -> Set<CompiledValue>? in
            if case .value(let value) = argument { return literalValues(value) }
            return nil
        }
        let evidence = arguments.map { argument -> NativeArgumentEvidence? in
            guard case .value(let value) = argument else { return nil }
            if case .boundValue(let id) = value, let existing = argumentEvidence[id] { return existing }
            return .init(expression: value, scope: self)
        }
        let callbacks = arguments.map { argument -> NativeCallbackBinding? in
            guard case .operator(let operation) = argument else { return nil }
            if case .reference(let target, _) = operation, let binding = boundOperators[target] {
                return .init(forwarding: binding, from: target)
            }
            return .init(operation: operation, scope: self)
        }
        let callbackID: OperatorID?
        if case .reference(let id, _) = requestedOperation, boundOperators[id] != nil { callbackID = id }
        else { callbackID = nil }
        let callback = callbackID.flatMap { boundOperators[$0] }
        var scope = callback?.scope ?? self
        // Recursive activity belongs to the call stack, while value/operator
        // bindings belong to the callback's lexical declaration scope.
        scope.activeOperators = activeOperators
        scope.activeArgumentRefinements = activeArgumentRefinements
        scope.specializationResults.merge(specializationResults) { _, current in current }
        let operation = callback?.operation ?? requestedOperation
        let resolved = try scope.specializeOperation(operation,
            argumentTypes: argumentTypes, argumentDomains: argumentDomains, evidence: evidence,
            callbacks: callbacks, expected: expected)
        specializationResults.merge(scope.specializationResults) { _, current in current }
        variables = scope.variables
        if let callbackID { recordCallback(callbackID, call: resolved) }
        let valueArguments = arguments.compactMap { argument -> CompiledStateExpr? in
            if case .value(let value) = argument { return value }; return nil
        }
        for (index, parameter) in resolved.parameters.enumerated() {
            _ = try infer(valueArguments[index], expected: resolved.inference.bindings[parameter] ?? .unknown)
        }
        // A closure may establish stronger finite-domain evidence for a
        // captured value. Revalidate that evidence in its declaration scope,
        // never by copying a callee's BinderID/type pair over the caller.
        for (parameter, uses) in resolved.callbackUses {
            guard resolved.callbackArguments[parameter] != nil,
                  let binding = resolved.inference.boundOperators[parameter],
                  binding.forwardedFrom == nil else { continue }
            let lambdaParameters: Set<BinderID>
            if case .lambda(let lambda) = binding.operation { lambdaParameters = Set(lambda.parameters) }
            else { lambdaParameters = [] }
            for use in uses {
                for (binder, original) in binding.scope.bindings where !lambdaParameters.contains(binder) {
                    guard bindings[binder] == original,
                          let refined = use.inference.bindings[binder], refined != original else { continue }
                    _ = try infer(.boundValue(binder), expected: refined)
                }
            }
        }
        // A forwarded callback remains a value in the caller's lexical scope.
        // Propagate only the signatures demanded by the nested call.
        for (parameter, uses) in resolved.callbackUses {
            if resolved.callbackArguments[parameter] == nil, boundOperators[parameter] != nil {
                for use in uses { recordCallback(parameter, call: use) }
            } else if let origin = resolved.inference.boundOperators[parameter]?.forwardedFrom {
                for use in uses { recordCallback(origin, call: use) }
            }
        }
        return resolved
    }

    private mutating func specializeOperation(
        _ operation: CompiledFormalOperator,
        argumentTypes: [NativeType], argumentDomains: [Set<CompiledValue>?], evidence: [NativeArgumentEvidence?],
        callbacks: [NativeCallbackBinding?], expected: NativeType
    ) throws -> NativeOperatorCall {
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
        guard formalParameters.count == argumentTypes.count else { throw Self.diagnostic("operator", "argument count mismatch") }
        var callbackArguments: [OperatorID: CompiledFormalOperator] = [:]
        var identities = callbackIdentities
        for (index, parameter) in formalParameters.enumerated() {
            switch parameter {
            case .value:
                guard callbacks[index] == nil else { throw Self.diagnostic("operator", "expected value argument") }
            case .operator(let id, let arity):
                guard let callback = callbacks[index], callback.operation.arity == arity else { throw Self.diagnostic("operator", "operator argument arity mismatch") }
                identities[id] = callback.identity
                callbackArguments[id] = callback.forwardedFrom.map { .reference($0, arity: arity) } ?? callback.operation
            }
        }
        let parameters = formalParameters.compactMap { parameter -> BinderID? in
            if case .value(let binder) = parameter { return binder }; return nil
        }
        let key = NativeOperatorSpecialization(operation: operation, arguments: argumentTypes,
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
            return .init(specialization: key, parameters: parameters, body: body, domain: domain,
                result: context, inference: self, callbackUses: callbackUses, callbackArguments: callbackArguments)
        }
        activeOperators.insert(key)
        specializationResults[key] = context
        callbackUses = [:]
        for (index, parameter) in formalParameters.enumerated() {
            switch parameter {
            case .value(let binder):
                bindings[binder] = argumentTypes[index]
                argumentEvidence[binder] = evidence[index]
                if let values = argumentDomains[index] {
                    bindingSources[binder] = .value(.set(values)); bindingDomains[binder] = values
                } else {
                    bindingSources.removeValue(forKey: binder); bindingDomains.removeValue(forKey: binder)
                }
            case .operator(let id, _): boundOperators[id] = callbacks[index]
            }
        }
        if let domain, let binder = parameters.first {
            bindings[binder] = try element(infer(domain, expected: .set(bindings[binder] ?? .unknown)))
        }
        let result = try infer(body, expected: context)
        specializationResults[key] = try Self.operandContext(context, result)
        let scoped = self
        activeOperators.remove(key)
        return .init(specialization: key, parameters: parameters, body: body, domain: domain,
            result: result, inference: scoped, callbackUses: callbackUses, callbackArguments: callbackArguments)
    }

    private mutating func infer(_ expression: CompiledStateExpr, expected: NativeType = .unknown) throws -> NativeType {
        do { return try inferResolved(expression, expected: expected) }
        catch let diagnostic as CompilationDiagnostic {
            let location: String
            switch expression {
            case .boundValue(let id): location = "binder[\(id.ordinal)]"
            case .stateVariable(let id): location = "variable[\(plan.variables.first { $0.id == id }?.declaration.name ?? String(id.ordinal))]"
            case .tupleAccess(_, let index): location = "tupleAccess[\(index)]"
            case .operatorApplication(let id, _), .recursiveCall(let id, _): location = "operator[\(id.ordinal)]"
            default: location = String(String(describing: expression).prefix { $0 != "(" })
            }
            throw CompilationDiagnostic(code: diagnostic.code, stage: diagnostic.stage,
                path: diagnostic.path + " <- " + location,
                expected: diagnostic.expected, actual: diagnostic.actual,
                nextSafeAction: diagnostic.nextSafeAction)
        }
    }

    private mutating func inferResolved(_ expression: CompiledStateExpr, expected: NativeType = .unknown) throws -> NativeType {
        if try unionConstructor(expression, expected: expected) != nil { return expected }
        let result: NativeType
        switch expression {
        case .assertView(let value, let shape):
            _ = try infer(value)
            result = try viewType(shape)
        case .value(let value): return try literal(value, expected: expected)
        case .stateVariable(let id):
            let existing = variables[id] ?? .unknown
            if canProjectRead(existing, to: expected) { result = expected }
            else { result = try Self.merge(existing, expected); variables[id] = result }
        case .boundValue(let id):
            let existing = bindings[id] ?? .unknown
            // A use-site projection does not replace the binder's chosen native
            // representation. Later raw scalar reads must not erase enum identity.
            if canProjectRead(existing, to: expected) { return expected }
            if expected != .unknown, existing != expected, let evidence = argumentEvidence[id] {
                let refinement = NativeArgumentRefinement(expression: evidence.expression, bindings: evidence.scope.bindings, expected: expected)
                if activeArgumentRefinements.insert(refinement).inserted {
                    defer { activeArgumentRefinements.remove(refinement) }
                    var caller = evidence.scope
                    caller.activeArgumentRefinements = activeArgumentRefinements
                    caller.activeOperators = activeOperators
                    caller.specializationResults.merge(specializationResults) { _, current in current }
                    let refined = try caller.infer(evidence.expression, expected: expected)
                    specializationResults.merge(caller.specializationResults) { _, current in current }
                    bindings[id] = refined
                    return refined
                }
                // Recursive construction proofs share the active obligation's
                // provisional type. Its outer invocation still validates every
                // constructor/base branch in the original lexical scope before
                // any successful call annotation can escape.
                bindings[id] = expected
                return expected
            }
            if expected != .unknown, existing != expected, let domain = bindingSources[id],
               activeBindingRefinements.insert(id).inserted {
                defer { activeBindingRefinements.remove(id) }
                let refined = try element(infer(domain, expected: .set(expected)))
                bindings[id] = refined
                return refined
            }
            if case .finite(let values) = expected, let domain = bindingDomains[id], domain.isSubset(of: Set(values)) {
                bindings[id] = expected
                return expected
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
        case .controlLocation: result = .control
        case .enabledAction: result = .bool
        case .add(let a, let b), .subtract(let a, let b), .multiply(let a, let b), .divide(let a, let b), .integerDivide(let a, let b), .modulo(let a, let b):
            _ = try infer(a, expected: .int); _ = try infer(b, expected: .int); result = .int
        case .negate(let value): _ = try infer(value, expected: .int); result = .int
        case .and(let a, let b), .or(let a, let b):
            _ = try infer(a, expected: .bool); _ = try infer(b, expected: .bool); result = .bool
        case .not(let value): _ = try infer(value, expected: .bool); result = .bool
        case .equal(let a, let b), .notEqual(let a, let b):
            _ = try comparisonOperands(a, b); result = .bool
        case .lessThan(let a, let b), .lessOrEqual(let a, let b), .greaterThan(let a, let b), .greaterOrEqual(let a, let b):
            _ = try infer(a, expected: .int); _ = try infer(b, expected: .int); result = .bool
        case .ifThenElse(let condition, let a, let b):
            _ = try infer(condition, expected: .bool)
            result = try comparisonOperands(a, b, expected: expected)
        case .setLiteral(let expressions):
            let hint: NativeType = if case .set(let value) = expected { value } else { .unknown }
            var value = hint
            for expression in expressions { value = try Self.merge(value, infer(expression, expected: value)) }
            result = .set(value)
        case .in(let value, let domain):
            _ = try membershipElement(value: value, domain: domain); result = .bool
        case .subset(let a, let b):
            let context = try comparisonOperands(a, b)
            _ = try element(context); result = .bool
        case .union(let a, let b), .intersection(let a, let b), .setDifference(let a, let b):
            let context = try Self.operandContext(comparisonOperands(a, b), expected)
            _ = try element(context)
            _ = try infer(a, expected: context); result = try infer(b, expected: context)
        case .cardinality(let value): _ = try infer(value, expected: .set(.unknown)); result = .int
        case .integerRange(let a, let b): _ = try infer(a, expected: .int); _ = try infer(b, expected: .int); result = .set(.int)
        case .sequenceSelect(let sequence, let id, let predicate):
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
            _ = try inferSequence(sequence, element: selected)
            result = .array(selected)
        case .setFilter(let domain, let id, let predicate):
            bindingSources[id] = domain
            bindingDomains[id] = literalDomain(domain)
            let initial = try infer(domain, expected: expected == .unknown ? .set(.unknown) : expected)
            bindings[id] = try element(initial); _ = try infer(predicate, expected: .bool)
            let refined = bindings[id] ?? .unknown
            result = try infer(domain, expected: .set(refined))
            // A predicate can prove a stronger nominal representation than an
            // earlier raw context. Its collection retains that representation.
            return result
        case .setMap(let body, let id, let domain):
            bindingSources[id] = domain
            bindingDomains[id] = literalDomain(domain)
            bindings[id] = try element(infer(domain, expected: .set(.unknown)))
            let hint: NativeType = if case .set(let value) = expected { value } else { .unknown }
            result = .set(try infer(body, expected: hint))
        case .forAll(let domain, let id, let body), .exists(let domain, let id, let body):
            bindingSources[id] = domain
            bindingDomains[id] = literalDomain(domain)
            bindings[id] = try element(infer(domain, expected: .set(.unknown)))
            _ = try infer(body, expected: .bool); result = .bool
        case .choose(let domain, let id, let body):
            bindingSources[id] = domain
            bindingDomains[id] = literalDomain(domain)
            let initial = try element(infer(domain, expected: .set(expected))); bindings[id] = initial
            _ = try infer(body, expected: .bool)
            result = try element(infer(domain, expected: .set(bindings[id] ?? initial)))
            return result
        case .sequenceFromSet(let domain):
            let hint: NativeType = if case .array(let value) = expected { value } else { .unknown }
            result = .array(try element(infer(domain, expected: .set(hint))))
        case .powerSet(let domain):
            let hint: NativeType = if case .set(let value) = expected { value } else { .set(.unknown) }
            result = .set(try infer(domain, expected: hint))
        case .unionAll(let domain):
            let hint: NativeType = expected == .unknown ? .set(.unknown) : expected
            result = try element(infer(domain, expected: .set(hint)))
        case .functionSet(let domain, let range):
            let candidate: NativeType = if case .set(let value) = expected { value } else { .unknown }
            let hint: NativeType = candidate == .unknown ? .dictionary(.unknown, .unknown) : candidate
            guard case .dictionary(let key, let value) = hint else { throw Self.diagnostic("functionSet", "expected set of dictionaries") }
            let inferredKey = try element(infer(domain, expected: .set(key)))
            let inferredValue = try element(infer(range, expected: .set(value)))
            result = .set(.dictionary(inferredKey, inferredValue))
        case .setSum(let function, let domain):
            let key = try element(infer(domain, expected: .set(.unknown)))
            _ = try infer(function, expected: .dictionary(key, .int)); result = .int
        case .foldFunction(let operation, let initial, let sequence):
            guard operation.parameters.count == 2 else { throw Self.diagnostic("fold", "expected two lambda parameters") }
            let accumulator = try infer(initial, expected: expected)
            bindings[operation.parameters[1]] = accumulator
            bindings[operation.parameters[0]] = try sequenceElementType(inferSequence(sequence))
            result = try infer(operation.body, expected: accumulator)
            _ = try infer(initial, expected: result)
        case .tupleLiteral(let expressions):
            if case .tuple(let hints) = expected, hints.count == expressions.count {
                var types: [NativeType] = []
                for (expression, hint) in zip(expressions, hints) { types.append(try infer(expression, expected: hint)) }
                result = .tuple(types)
            } else {
                let hint: NativeType = if case .array(let value) = expected { value } else { .unknown }
                var types: [NativeType] = []
                for expression in expressions { types.append(try infer(expression, expected: hint)) }
                if expected == .unknown, !types.isEmpty, types.allSatisfy({ $0 == .unknown }) { result = .tuple(types) }
                else if hint == .unknown, let first = types.first, types.contains(where: { $0 != first }) { result = .tuple(types) }
                else { result = .array(try types.reduce(hint, Self.merge)) }
            }
        case .tupleAccess(let value, let index):
            let shape = try inferProjectionSource(value, index: index, expected: expected)
            if case .tuple(let elements) = shape { result = try projectedReadType(elements[index - 1], expected: expected) }
            else { result = try sequenceElementType(shape) }
        case .tupleDynamicAccess(let value, let index):
            _ = try infer(index, expected: .int)
            result = try sequenceElementType(inferSequence(value, element: expected))
        case .tupleLength(let value):
            if case .tuple = try infer(value) {} else { _ = try inferSequence(value) }
            result = .int
        case .tupleHead(let value): result = try sequenceElementType(inferSequence(value, element: expected))
        case .tupleTail(let value):
            let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
            result = .array(try sequenceElementType(inferSequence(value, element: hint)))
        case .tupleRemoving(let sequence, let index):
            let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
            result = .array(try sequenceElementType(inferSequence(sequence, element: hint)))
            _ = try infer(index, expected: .int)
        case .tupleAppend(let sequence, let value):
            let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
            let item = try sequenceElementType(inferSequence(sequence, element: hint))
            let appended = try infer(value, expected: item)
            let elementType = try Self.merge(item, appended)
            _ = try inferSequence(sequence, element: elementType)
            _ = try infer(value, expected: elementType)
            result = .array(elementType)
        case .tupleConcatenate(let a, let b):
            let hint = if case .array(let element) = expected { element } else { NativeType.unknown }
            let left = try sequenceElementType(inferSequence(a, element: hint))
            let right = try sequenceElementType(inferSequence(b, element: left))
            let elementType = try Self.merge(left, right)
            _ = try inferSequence(a, element: elementType)
            _ = try inferSequence(b, element: elementType)
            result = .array(elementType)
        case .recordLiteral(let record):
            let hints: [NativeField] = if case .record(let fields) = expected { fields } else { [] }
            var fields: [NativeField] = []
            for field in record.fields {
                guard case .string(let name) = field.key else { throw Self.diagnostic("record", "non-string field") }
                fields.append(.init(name: name, type: try infer(field.value, expected: hints.first { $0.name == name }?.type ?? .unknown)))
            }
            result = .record(fields.sorted { $0.name < $1.name })
        case .recordAccess(let record, _, let key):
            let source = try inferRecordProjectionSource(record, key: key, expected: expected)
            if case .string(let name) = key, case .record(let fields) = source,
               let field = fields.first(where: { $0.name == name }) { result = try projectedReadType(field.type, expected: expected) }
            else { result = .unknown }
        case .functionLiteral(let domain, let id, let body):
            bindingSources[id] = domain
            bindingDomains[id] = literalDomain(domain)
            let hints: (NativeType, NativeType) = if case .dictionary(let key, let value) = expected { (key, value) } else { (.unknown, .unknown) }
            let key = try element(infer(domain, expected: .set(hints.0))); bindings[id] = key
            result = .dictionary(key, try infer(body, expected: hints.1))
        case .functionApply(let function, let key):
            if case .operatorReference(let id) = function { return try inferCall(id, arguments: [.value(key)], expected: expected) }
            let base = try infer(function)
            let functionType: NativeType
            if base == .unknown { functionType = try infer(function, expected: .dictionary(infer(key), expected)) }
            else { functionType = base }
            switch functionType {
            case .dictionary(let domain, let value):
                _ = try infer(key, expected: domain)
                result = try Self.operandContext(value, expected)
                _ = try infer(function, expected: .dictionary(domain, result))
            case .array(let value):
                _ = try infer(key, expected: .int)
                result = try Self.operandContext(value, expected)
                _ = try infer(function, expected: .array(result))
            case .tuple(let elements):
                _ = try infer(key, expected: .int)
                if case .value(.integer(let index)) = key, index >= 1, index <= elements.count {
                    var hints = elements
                    hints[index - 1] = try Self.operandContext(elements[index - 1], expected)
                    _ = try infer(function, expected: .tuple(hints))
                    result = hints[index - 1]
                } else if case .value(.integer) = key, expected != .unknown {
                    result = expected
                } else {
                    result = try elements.reduce(expected, Self.merge)
                    _ = try infer(function, expected: .tuple(elements.map { _ in result }))
                }
            case .record(let fields):
                _ = try infer(key, expected: .string)
                if case .value(.string(let name)) = key {
                    if let selected = fields.first(where: { $0.name == name }) {
                        result = try Self.operandContext(selected.type, expected)
                        _ = try infer(function, expected: .record(fields.map { .init(name: $0.name, type: $0.name == name ? result : $0.type) }))
                    } else { result = expected }
                } else {
                    result = try fields.map(\.type).reduce(expected, Self.merge)
                    _ = try infer(function, expected: .record(fields.map { .init(name: $0.name, type: result) }))
                }
            default: throw Self.diagnostic("function", "expected a native dictionary, sequence, or record")
            }
        case .except(let function, let key, let value):
            let base = try infer(function, expected: expected)
            switch base {
            case .array(let item): _ = try infer(key, expected: .int); result = .array(try infer(value, expected: item))
            case .dictionary(let domain, let item): _ = try infer(key, expected: domain); result = .dictionary(domain, try infer(value, expected: item))
            case .record(let fields):
                _ = try infer(key, expected: .string)
                if case .value(.string(let name)) = key {
                    _ = try infer(value, expected: fields.first { $0.name == name }?.type ?? .unknown)
                } else {
                    let replacementType = fields.first?.type ?? .unknown
                    guard fields.allSatisfy({ $0.type == replacementType }) else {
                        throw Self.diagnostic("except", "dynamic record keys require homogeneous field types")
                    }
                    _ = try infer(value, expected: replacementType)
                }
                result = base
            case .unknown: result = .dictionary(try infer(key), try infer(value))
            default: throw Self.diagnostic("except", "unsupported update shape \(base.swiftType)")
            }
        case .domain(let function):
            switch try inferDomainSource(function, expected: expected) {
            case .dictionary(let key, _): result = .set(key)
            case .array, .tuple: result = .set(.int)
            case .record: result = .set(.string)
            case .unknown: result = .set(.unknown)
            default: throw Self.diagnostic("domain", "unsupported domain shape")
            }
        case .letValue(let id, let value, let body):
            bindingSources[id] = .setLiteral([value])
            bindingDomains[id] = literalValues(value)
            bindings[id] = try infer(value, expected: bindings[id] ?? .unknown); result = try infer(body, expected: expected)
        case .operatorApplication(let id, let arguments):
            result = try inferCall(id, arguments: arguments, expected: expected)
        case .recursiveCall(let id, let arguments):
            result = try inferCall(id, arguments: arguments.map { .value($0) }, expected: expected)
        case .lambdaApplication(let lambda, let arguments):
            result = try specializeCall(.lambda(lambda), arguments: arguments.map { .value($0) }, expected: expected).result
        case .letIn(let definitions, let body):
            for definition in definitions {
                localOperators[definition.id] = definition
                localCaptures[definition.id] = bindings
            }
            result = try infer(body, expected: expected)
        case .caseExpr(let first, let rest, let otherwise):
            var type = expected
            for branch in [first] + rest { _ = try infer(branch.condition, expected: .bool); type = try infer(branch.value, expected: type) }
            if let otherwise { type = try infer(otherwise, expected: type) }; result = type
        default: throw Self.diagnostic("expression", "expression is outside the native machine subset: \(expression)")
        }
        return try projectedReadType(result, expected: expected)
    }
}
