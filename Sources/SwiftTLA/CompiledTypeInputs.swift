/// Enum declarations own both Swift case encodings and their formal domains.
package struct CompiledEnums: Sendable {
    package let cases: [String: [(name: String, value: CompiledValue)]]
    package let domains: [String: Set<CompiledValue>]

    package init(cases: [String: [(name: String, value: CompiledValue)]] = [:]) {
        self.cases = cases.mapValues { $0.sorted { $0.value < $1.value } }
        domains = cases.mapValues { Set($0.map(\.value)) }
    }
}

/// Resolved declaration types and domains shared by compiler checking scopes.
package final class CompiledTypeInputs: Sendable {
    let identity: CompilationIdentity
    let layout: CompiledLayout
    let semantics: CompiledSemantics
    let bindings: CompiledBindingTable
    package let variableTypes: [VariableID: CompiledValueType]
    package let bindingTypes: [BinderID: CompiledValueType]
    package let collectionDomains: [VariableID: Set<CompiledValue>]
    package let types: CompiledTypeContext

    package init(
        compilation: CompiledSpecification,
        types: CompiledTypeContext,
        resolveSourceType: (String) throws -> CompiledValueType
    ) throws {
        identity = compilation.identity
        layout = compilation.layout
        semantics = compilation.semantics
        bindings = compilation.bindings
        self.types = types

        var variableTypes: [VariableID: CompiledValueType] = [:]
        var collectionDomains: [VariableID: Set<CompiledValue>] = [:]
        for variable in layout.variables {
            if let collection = variable.collection, let element = collection.elementType, let value = collection.valueType {
                collectionDomains[variable.id] = Set(collection.members)
                variableTypes[variable.id] = .dictionary(
                    .collectionMember(variable.id, swiftType: "\(element).ID"), try resolveSourceType(value))
            } else {
                variableTypes[variable.id] = try variable.generatedSwiftType.map(resolveSourceType) ?? .unknown
            }
        }
        self.variableTypes = variableTypes
        self.collectionDomains = collectionDomains
        var bindingTypes: [BinderID: CompiledValueType] = [:]
        for action in semantics.behavior.actions {
            for binding in action.bindings {
                if let variable = action.collection,
                   case .dictionary(let memberType, _)? = variableTypes[variable] {
                    bindingTypes[binding.binder] = memberType
                } else {
                    bindingTypes[binding.binder] = try binding.generatedSwiftType.map(resolveSourceType) ?? .unknown
                }
            }
        }
        for definition in semantics.operators.definitions.values {
            for parameter in definition.parameters {
                if case .value(let binder, let typeName?) = parameter {
                    bindingTypes[binder] = try resolveSourceType(typeName)
                }
            }
        }
        self.bindingTypes = bindingTypes
    }
}

/// Type relationships and nominal domains, independent of expressions and compiler stages.
package struct CompiledTypeContext: Sendable {
    package let enums: CompiledEnums
    package var namedDomains: [String: Set<CompiledValue>] { enums.domains }
    package let namedRepresentations: [String: CompiledValueType]
    package let formalNames: [String: String]

    package init(enums: CompiledEnums, formalNames: [String: String]) throws {
        self.enums = enums
        self.namedRepresentations = try enums.cases.mapValues { cases in
            try cases.reduce(CompiledValueType.unknown) { result, member in
                let type: CompiledValueType
                switch member.value {
                case .integer: type = .int
                case .boolean: type = .bool
                case .string: type = .string
                case .constant: type = .modelValue
                default: type = .unknown
                }
                return try CompiledValueType.merge(result, type)
            }
        }
        self.formalNames = formalNames
    }

    package func canProjectRead(_ source: CompiledValueType, to expected: CompiledValueType) -> Bool {
        var checks: [ResolvedProjectionPair: Bool] = [:]
        return canProjectRead(source, to: expected, checks: &checks)
    }

    /// Record component results during checking so conversion planning does not walk them again.
    package func canProjectRead(
        _ source: CompiledValueType, to expected: CompiledValueType,
        checks: inout [ResolvedProjectionPair: Bool]
    ) -> Bool {
        if source == expected { return true }
        let pair = ResolvedProjectionPair(source: source, target: expected)
        if let allowed = checks[pair] { return allowed }
        let allowed = checkProjection(source, to: expected, checks: &checks)
        checks[pair] = allowed
        return allowed
    }

    private func checkProjection(
        _ source: CompiledValueType, to expected: CompiledValueType,
        checks: inout [ResolvedProjectionPair: Bool]
    ) -> Bool {
        if case .union(let sources) = source {
            return sources.map { canProjectRead($0, to: expected, checks: &checks) }.allSatisfy { $0 }
        }
        if case .union(let targets) = expected {
            return targets.filter { canProjectRead(source, to: $0, checks: &checks) }.count == 1
        }
        switch (source, expected) {
        case (.dictionary(let a, let b), .dictionary(let c, let d)):
            let key = canProjectRead(a, to: c, checks: &checks)
            let value = canProjectRead(b, to: d, checks: &checks)
            return key && value
        case (.array(let a), .array(let b)), (.set(let a), .set(let b)):
            return canProjectRead(a, to: b, checks: &checks)
        case (.tuple(let a), .tuple(let b)) where a.count == b.count:
            return zip(a, b).map { canProjectRead($0, to: $1, checks: &checks) }.allSatisfy { $0 }
        case (.record(let a), .record(let b)) where a.map(\.name) == b.map(\.name):
            return zip(a, b).map { canProjectRead($0.type, to: $1.type, checks: &checks) }.allSatisfy { $0 }
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
                case (.integer, .int), (.boolean, .bool), (.string, .string), (.constant, .modelValue): true
                default: false
                }
            }
        default: break
        }
        return false
    }

    /// Resolve structural type information using this program's nominal domains.
    package func resolve(_ shape: FormalValueShape) throws -> CompiledValueType {
        switch shape {
        case .integer: return .int
        case .boolean: return .bool
        case .string: return .string
        case .finite(let name, let values):
            let members = Set(values.map(CompiledValue.init(formal:)))
            if let key = namedDomains.keys.first(where: {
                formalNames[$0] == name && namedDomains[$0] == members
            }) { return .named(key) }
            return .finite(members.sorted())
        case .set(let item): return .set(try resolve(item))
        case .sequence(let item): return .array(try resolve(item))
        case .tuple(let items): return .tuple(try items.map(resolve))
        case .function(let key, let value): return .dictionary(try resolve(key), try resolve(value))
        case .record(let fields): return .record(try fields.map { .init(name: $0.name, type: try resolve($0.shape)) }.sorted { $0.name < $1.name })
        case .union(let first, let second): return try CompiledValueType.normalizedUnion([resolve(first), resolve(second)], namedDomains: namedDomains)
        case .unsupported(let name): throw CompiledValueType.diagnostic("view", "unsupported formal shape " + name)
        }
    }
}
