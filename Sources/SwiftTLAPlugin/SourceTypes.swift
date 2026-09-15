import SwiftTLA
import SwiftSyntax
import SwiftParser
import Foundation

extension CompiledValueType {
    var selectedElement: Self? {
        switch self {
        case .set(let element), .array(let element), .dictionary(_, let element): return element
        default: return nil
        }
    }

    var enumerationType: String? {
        guard case .named(let type) = self else { return nil }
        return type
    }
}

/// One enum declaration shared by source parsing and type resolution.
package struct SourceEnum: Sendable {
    let typeName: String
    let cases: [(name: String, value: TLAValue)]
    let finiteValues: [TLAValue]
    let isFiniteDomain: Bool

    package init(typeName: String, cases: [(name: String, value: TLAValue)] = [],
                 finiteValues: [TLAValue]? = nil, isFiniteDomain: Bool = false) {
        self.typeName = typeName
        self.cases = cases
        self.finiteValues = finiteValues ?? cases.map(\.value)
        self.isFiniteDomain = isFiniteDomain
    }

    func value(named name: String) -> TLAValue? {
        cases.first { $0.name == name }?.value
    }
}

/// Swift declarations that retain source types alongside formal values.
/// This is consumed by the shared compiler inference pass, never at runtime.
package struct SourceRecordField: Sendable {
    package let sourceName: String
    package let name: String
    package let swiftType: TypeSyntax
    package init(sourceName: String, name: String, swiftType: TypeSyntax) {
        self.sourceName = sourceName; self.name = name; self.swiftType = swiftType
    }
}

package struct SourceTypeMetadata: Sendable {
    package let aliases: [String: TypeSyntax]
    package let records: [String: [SourceRecordField]]
    package let enums: [SourceEnum]
    package init(aliases: [String: TypeSyntax] = [:], records: [String: [SourceRecordField]] = [:], enums: [SourceEnum] = []) {
        self.aliases = aliases
        self.records = records
        self.enums = enums
    }
}

/// One source type owns both its execution representation and checked-view contract.
private struct ResolvedSourceType {
    let type: CompiledValueType
    let view: FormalValueShape

}

/// Resolves each source spelling and its dependencies once within an expansion stage.
final class SourceTypeResolver {
    let enums: CompiledEnums
    private var namedDomains: [String: Set<CompiledValue>] { enums.domains }
    private let metadata: SourceTypeMetadata
    private let nominalNames: [String: [String]]
    private var types: [String: ResolvedSourceType] = [:]

    init(metadata: SourceTypeMetadata = .init()) {
        enums = CompiledEnums(cases: Dictionary(uniqueKeysWithValues: metadata.enums.map { declaration in
            (declaration.typeName, declaration.cases.map { (name: $0.name, value: CompiledValue(formal: $0.value)) })
        }))
        self.metadata = metadata
        let names = Set(metadata.enums.map(\.typeName)).union(metadata.records.keys)
        nominalNames = Dictionary(grouping: names) { TokenSyntax.identifier($0).sourceIdentifierName }
    }

    func resolve(_ source: String) throws -> CompiledValueType {
        try resolveType(source).type
    }

    func formalShape(for source: String) throws -> FormalValueShape {
        try resolveType(source).view
    }

    func resolve(_ type: TypeSyntax) throws -> CompiledValueType {
        guard !type.hasError else {
            throw CompiledValueType.diagnostic("type", "invalid Swift type syntax: \(type.trimmedDescription)")
        }
        return try resolveType(type, resolving: []).type
    }

    private func resolveType(_ source: String) throws -> ResolvedSourceType {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolved = types[source] { return resolved }
        let syntax = Parser.parse(source: "typealias ResolvedType = \(source)")
        guard !syntax.hasError, syntax.statements.count == 1,
              let declaration = syntax.statements.first?.item.as(TypeAliasDeclSyntax.self) else {
            throw CompiledValueType.diagnostic("type", "invalid Swift type syntax: \(source)")
        }
        let resolved = try resolveType(declaration.initializer.value, resolving: [])
        types[source] = resolved
        return resolved
    }

    private func resolveType(_ type: TypeSyntax, resolving: Set<String>) throws -> ResolvedSourceType {
        let source = type.trimmedDescription
        if let resolved = types[source] { return resolved }
        let resolved = try resolveUncached(type, resolving: resolving)
        types[source] = resolved
        return resolved
    }

    private func resolveUncached(_ type: TypeSyntax, resolving: Set<String>) throws -> ResolvedSourceType {
        let source = type.trimmedDescription
        if let array = type.as(ArrayTypeSyntax.self) {
            let element = try resolveType(array.element, resolving: resolving)
            return .init(type: .array(element.type), view: .sequence(element.view))
        }
        if let dictionary = type.as(DictionaryTypeSyntax.self) {
            let key = try resolveType(dictionary.key, resolving: resolving)
            let value = try resolveType(dictionary.value, resolving: resolving)
            return .init(type: .dictionary(key.type, value.type), view: .function(key: key.view, value: value.view))
        }
        let name: String
        let arguments: GenericArgumentClauseSyntax?
        if let reference = type.as(IdentifierTypeSyntax.self) {
            name = reference.name.sourceIdentifierName
            arguments = reference.genericArgumentClause
            if arguments == nil, let alias = metadata.aliases[name] {
                guard !resolving.contains(name) else {
                    throw CompiledValueType.diagnostic("aliases.\(name)", "cyclic type alias")
                }
                return try resolveType(alias, resolving: resolving.union([name]))
            }
            if nominalNames[name] != nil {
                guard arguments == nil else {
                    throw CompiledValueType.diagnostic("types.\(name)", "declared nominal type does not accept generic arguments")
                }
                return try named(source)
            }
        } else if let member = type.as(MemberTypeSyntax.self),
                  ["Swift", "SwiftTLA"].contains(member.baseType.trimmedDescription) {
            name = member.name.sourceIdentifierName
            arguments = member.genericArgumentClause
        } else if type.is(MemberTypeSyntax.self) {
            return try named(source)
        } else {
            throw CompiledValueType.diagnostic("type", "unsupported Swift type syntax: \(source)")
        }
        func resolveArguments(expecting count: Int) throws -> [ResolvedSourceType] {
            let supplied = arguments?.arguments.count ?? 0
            guard supplied == count else {
                throw CompiledValueType.diagnostic("types.\(name)",
                    "expected \(count) generic arguments, received \(supplied)")
            }
            return try arguments?.arguments.map { argument in
                guard let type = argument.argument.as(TypeSyntax.self) else {
                    throw CompiledValueType.diagnostic("types.\(name)", "generic arguments must be types")
                }
                return try resolveType(type, resolving: resolving)
            } ?? []
        }
        switch name {
        case "TLAValue":
            throw CompiledValueType.diagnostic("type", "raw TLAValue is a formal-engine value, not a generated Swift state type")
        case "Int", "Bool", "String":
            _ = try resolveArguments(expecting: 0)
            switch name {
            case "Int": return .init(type: .int, view: .integer)
            case "Bool": return .init(type: .bool, view: .boolean)
            default: return .init(type: .string, view: .string)
            }
        case "Set", "SetExpr":
            let element = try resolveArguments(expecting: 1)[0]
            return .init(type: .set(element.type), view: .set(element.view))
        case "Array", "TupleExpr":
            let element = try resolveArguments(expecting: 1)[0]
            return .init(type: .array(element.type), view: .sequence(element.view))
        case "ZeroBasedSequence":
            let element = try resolveArguments(expecting: 1)[0]
            return .init(type: .dictionary(.int, element.type), view: .unsupported(source))
        case "Function", "Dictionary", "FunctionExpr", "PartialFunction":
            let parts = try resolveArguments(expecting: 2)
            let view: FormalValueShape = name == "Function"
                ? .unsupported("total Function view")
                : .function(key: parts[0].view, value: parts[1].view)
            return .init(type: .dictionary(parts[0].type, parts[1].type), view: view)
        case "Pair":
            let parts = try resolveArguments(expecting: 2)
            return .init(type: .tuple(parts.map(\.type)), view: .tuple(parts.map(\.view)))
        case "Record", "TLARecord":
            let argument = try resolveArguments(expecting: 1)[0]
            guard case .named(let schema) = argument.type,
                  let fields = metadata.records[schema] else {
                return .init(type: .unknown, view: .unsupported(source))
            }
            let identity = "record-schema:\(schema)"
            guard !resolving.contains(identity) else {
                throw CompiledValueType.diagnostic("schemas.\(schema)", "recursive record schema requires a finite nonrecursive native field shape")
            }
            let resolvedFields = try fields.sorted { $0.name < $1.name }.map { field in
                (name: field.name, value: try resolveType(field.swiftType, resolving: resolving.union([identity])))
            }
            return .init(type: .record(resolvedFields.map { .init(name: $0.name, type: $0.value.type) }),
                view: .record(resolvedFields.map { .init(name: $0.name, shape: $0.value.view) }))
        case "OneOf":
            let parts = try resolveArguments(expecting: 2)
            return .init(type: try CompiledValueType.normalizedUnion(parts.map(\.type), namedDomains: namedDomains),
                view: .union(parts[0].view, parts[1].view))
        default:
            return try named(source)
        }
    }

    private func named(_ source: String) throws -> ResolvedSourceType {
        let identity = TokenSyntax.identifier(source).sourceIdentifierName
        let declarations = nominalNames[identity, default: []]
        guard declarations.count <= 1 else {
            throw CompiledValueType.diagnostic("types.\(identity)", "multiple declarations have the same Swift identifier")
        }
        let name = declarations.first ?? source
        let view: FormalValueShape
        if let declaration = metadata.enums.first(where: { $0.typeName == name && $0.isFiniteDomain }) {
            view = .finite(typeName: identity, values: declaration.finiteValues)
        } else {
            view = .unsupported(name)
        }
        return .init(type: .named(name), view: view)
    }
}

extension SourceTypeResolver {
    func resolve(in compilation: CompiledSpecification) throws -> CompiledTypeInputs {
        let namedDomains = self.namedDomains
        let formalNames = Dictionary(uniqueKeysWithValues: namedDomains.keys.map {
            ($0, TokenSyntax.identifier($0).sourceIdentifierName)
        })
        return try CompiledTypeInputs(compilation: compilation,
            types: CompiledTypeContext(enums: enums, formalNames: formalNames),
            resolveSourceType: resolve)
    }
}
