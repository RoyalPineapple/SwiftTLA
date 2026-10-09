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

package struct SourceTypeMetadata: Sendable {
    package let aliases: [String: TypeSyntax]
    package let structs: [String: StructDeclSyntax]
    package let enums: [SourceEnum]
    package init(aliases: [String: TypeSyntax] = [:],
                 structs: [String: StructDeclSyntax] = [:], enums: [SourceEnum] = []) {
        self.aliases = aliases
        self.structs = structs
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
        let names = Set(metadata.enums.map(\.typeName)).union(metadata.structs.keys)
        var nominalNames = Dictionary(grouping: names) { TokenSyntax.identifier($0).sourceIdentifierName }
        for (name, declaration) in metadata.structs {
            let qualified = Self.qualifiedName(of: declaration)
            if qualified != name { nominalNames[qualified, default: []].append(name) }
        }
        self.nominalNames = nominalNames
    }

    static func qualifiedName(of declaration: StructDeclSyntax) -> String {
        var names = [declaration.name.text]
        var ancestor = declaration.parent
        while let node = ancestor {
            if let owner = node.as(StructDeclSyntax.self) { names.append(owner.name.text) }
            else if let owner = node.as(EnumDeclSyntax.self) { names.append(owner.name.text) }
            ancestor = node.parent
        }
        return names.reversed().joined(separator: ".")
    }

    func resolve(_ source: String) throws -> CompiledValueType {
        try resolveType(source).type
    }

    func formalShape(for source: String) throws -> FormalValueShape {
        try resolveType(source).view
    }

    func resolve(_ type: TypeSyntax) throws -> CompiledValueType {
        guard !type.hasError else {
            throw located(CompiledValueType.diagnostic("type",
                "invalid Swift type syntax: \(type.trimmedDescription)"), at: type)
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
        let resolved = try resolveType(declaration.initializer.value, resolving: [], sourceLocated: false)
        types[source] = resolved
        return resolved
    }

    private func resolveType(_ type: TypeSyntax, resolving: Set<String>, sourceLocated: Bool = true) throws -> ResolvedSourceType {
        let source = type.trimmedDescription
        if let resolved = types[source] { return resolved }
        do {
            let resolved = try resolveUncached(type, resolving: resolving, sourceLocated: sourceLocated)
            types[source] = resolved
            return resolved
        } catch var diagnostic as CompilationDiagnostic {
            if sourceLocated {
                diagnostic.sourceOffset = diagnostic.sourceOffset
                    ?? type.positionAfterSkippingLeadingTrivia.utf8Offset
            }
            throw diagnostic
        }
    }

    private func resolveUncached(_ type: TypeSyntax, resolving: Set<String>, sourceLocated: Bool) throws -> ResolvedSourceType {
        let source = type.trimmedDescription
        if let array = type.as(ArrayTypeSyntax.self) {
            let element = try resolveType(array.element, resolving: resolving, sourceLocated: sourceLocated)
            return .init(type: .array(element.type), view: .sequence(element.view))
        }
        if let dictionary = type.as(DictionaryTypeSyntax.self) {
            let key = try resolveType(dictionary.key, resolving: resolving, sourceLocated: sourceLocated)
            let value = try resolveType(dictionary.value, resolving: resolving, sourceLocated: sourceLocated)
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
                    throw CompiledValueType.diagnostic("types.\(name)",
                        "declared nominal type does not accept generic arguments")
                }
                return try named(type, resolving: resolving)
            }
        } else if let member = type.as(MemberTypeSyntax.self),
                  ["Swift", "SwiftTLA"].contains(member.baseType.trimmedDescription) {
            name = member.name.sourceIdentifierName
            arguments = member.genericArgumentClause
        } else if let member = type.as(MemberTypeSyntax.self) {
            guard member.genericArgumentClause == nil else {
                throw CompiledValueType.diagnostic("types.\(member.name.sourceIdentifierName)",
                    "generic arguments require a supported type constructor")
            }
            return try named(type, resolving: resolving)
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
                    let diagnostic = CompiledValueType.diagnostic("types.\(name)",
                        "generic arguments must be types")
                    throw sourceLocated ? located(diagnostic, at: argument) : diagnostic
                }
                return try resolveType(type, resolving: resolving, sourceLocated: sourceLocated)
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
        case "Triple":
            let parts = try resolveArguments(expecting: 3)
            return .init(type: .tuple(parts.map(\.type)), view: .tuple(parts.map(\.view)))
        case "Quintuple":
            let parts = try resolveArguments(expecting: 5)
            return .init(type: .tuple(parts.map(\.type)), view: .tuple(parts.map(\.view)))
        case "OneOf":
            let parts = try resolveArguments(expecting: 2)
            return .init(type: try CompiledValueType.preservingUnion(parts[0].type, parts[1].type, namedDomains: namedDomains),
                view: .union(parts[0].view, parts[1].view))
        default:
            guard arguments == nil else {
                throw CompiledValueType.diagnostic("types.\(name)",
                    "generic arguments require a supported type constructor")
            }
            return try named(type, resolving: resolving)
        }
    }

    private func named(_ type: TypeSyntax, resolving: Set<String>) throws -> ResolvedSourceType {
        let source = type.trimmedDescription
        let identity = TokenSyntax.identifier(source).sourceIdentifierName
        let declarations = nominalNames[identity, default: []]
        guard declarations.count <= 1 else {
            throw CompiledValueType.diagnostic("types.\(identity)", "multiple declarations have the same Swift identifier")
        }
        guard let name = declarations.first else {
            throw CompiledValueType.diagnostic("types.\(identity)",
                "unregistered Swift type \(source)")
        }
        if let declaration = metadata.structs[name] {
            let identity = "struct:\(name)"
            guard !resolving.contains(identity) else {
                throw CompiledValueType.diagnostic("types.\(name)", "recursive Swift record requires a finite nonrecursive field shape")
            }
            guard declaration.genericParameterClause == nil else {
                throw located(CompiledValueType.diagnostic("types.\(name)",
                    "generic Swift records require resolved type arguments"), at: declaration.name)
            }
            var fields: [CompiledFieldType] = []
            var views: [FormalValueShape.Field] = []
            for member in declaration.memberBlock.members {
                if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                    throw located(CompiledValueType.diagnostic("types.\(name)",
                        "custom Swift record initializers require a compiled implementation"), at: initializer)
                }
                guard let variable = member.decl.as(VariableDeclSyntax.self),
                      !variable.modifiers.contains(where: { $0.name.text == "static" || $0.name.text == "class" }) else { continue }
                guard variable.attributes.isEmpty, !variable.modifiers.contains(where: { $0.name.text == "lazy" }) else {
                    throw located(CompiledValueType.diagnostic("types.\(name)",
                        "model record fields cannot use property wrappers, attributes, or lazy storage"), at: variable)
                }
                for binding in variable.bindings {
                    guard let field = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                          let annotation = binding.typeAnnotation?.type,
                          binding.accessorBlock == nil else {
                        throw located(CompiledValueType.diagnostic("types.\(name)",
                            "model record fields must be stored properties with explicit Swift types"), at: binding.pattern)
                    }
                    guard !fields.contains(where: { $0.name == field }) else {
                        throw located(CompiledValueType.diagnostic("types.\(name).\(field)",
                            "duplicate Swift record field"), at: binding.pattern)
                    }
                    let value: ResolvedSourceType
                    do {
                        value = try resolveType(annotation, resolving: resolving.union([identity]))
                    } catch var diagnostic as CompilationDiagnostic {
                        diagnostic.sourceOffset = diagnostic.sourceOffset
                            ?? binding.pattern.positionAfterSkippingLeadingTrivia.utf8Offset
                        throw diagnostic
                    }
                    var pending = [value.type]
                    while let component = pending.popLast() {
                        if case .named(let typeName) = component, enums.cases[typeName] == nil {
                            throw located(CompiledValueType.diagnostic("types.\(name).\(field)",
                                "unresolved Swift field type \(typeName)"), at: binding.pattern)
                        }
                        guard component != .unknown else {
                            throw located(CompiledValueType.unresolvedDiagnostic(component,
                                at: "types.\(name).\(field)"), at: binding.pattern)
                        }
                        pending.append(contentsOf: component.components)
                    }
                    fields.append(.init(name: field, type: value.type))
                    views.append(.init(name: field, shape: value.view))
                }
            }
            return .init(type: .nominalRecord(Self.qualifiedName(of: declaration), fields), view: .record(views))
        }
        let view: FormalValueShape
        if let declaration = metadata.enums.first(where: { $0.typeName == name && $0.isFiniteDomain }) {
            view = .finite(typeName: identity, values: declaration.finiteValues)
        } else {
            view = .unsupported(name)
        }
        return .init(type: .named(name), view: view)
    }

    private func located(_ diagnostic: CompilationDiagnostic, at source: some SyntaxProtocol) -> CompilationDiagnostic {
        var diagnostic = diagnostic
        diagnostic.sourceOffset = source.positionAfterSkippingLeadingTrivia.utf8Offset
        return diagnostic
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
