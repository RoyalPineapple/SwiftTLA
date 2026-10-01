import SwiftSyntax
import SwiftTLA

extension TLASpecVerifier {
    static func sourceTypes(
        in members: MemberBlockItemListSyntax,
        enums: [SourceEnum]
    ) throws -> SourceTypeMetadata {
        var typeNames = Set<String>()
        for member in members {
            let name: TokenSyntax?
            if let declaration = member.decl.as(TypeAliasDeclSyntax.self) { name = declaration.name }
            else if let declaration = member.decl.as(StructDeclSyntax.self) { name = declaration.name }
            else if let declaration = member.decl.as(EnumDeclSyntax.self) { name = declaration.name }
            else { name = nil }
            if let name, !typeNames.insert(name.sourceIdentifierName).inserted {
                throw ModelMacroError.duplicateTypeDeclaration(typeName: name.sourceIdentifierName)
            }
        }
        let aliases = Dictionary(uniqueKeysWithValues: members.compactMap { member -> (String, TypeSyntax)? in
            guard let alias = member.decl.as(TypeAliasDeclSyntax.self) else { return nil }
            return (alias.name.sourceIdentifierName, alias.initializer.value)
        })
        let structs = members.compactMap { $0.decl.as(StructDeclSyntax.self) }
        return SourceTypeMetadata(aliases: aliases,
            structs: Dictionary(uniqueKeysWithValues: structs.map { ($0.name.text, $0) }), enums: enums)
    }
}
