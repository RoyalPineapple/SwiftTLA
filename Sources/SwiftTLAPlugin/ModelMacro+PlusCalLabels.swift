import SwiftSyntax
import SwiftTLA

extension TLASpecVerifier {
    static func collectEnumMetadata(
        from members: MemberBlockItemListSyntax
    ) -> [ParserEnumDefinition] {
        let infos = collectEnumVariables(from: members)
        let definitions = infos.map { info in
            ParserEnumDefinition(
                typeName: info.typeName,
                cases: TLARecord(info.cases.map { .init($0.name, $0.value) }),
                formalDomain: info.formalDomain
            )
        }
        return definitions + collectPlusCalLabelMap(from: members)
    }

    static func collectPlusCalLabelMap(from members: MemberBlockItemListSyntax) -> [ParserEnumDefinition] {
        var labels: [ParserEnumDefinition] = []
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self),
                  let inheritance = enumDecl.inheritanceClause
            else { continue }
            let inheritedNames = inheritance.inheritedTypes.compactMap {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text
            }
            guard inheritedNames.contains("PlusCalLabel"), inheritedNames.contains("String") else { continue }

            var rawValues: [TLARecord.Field] = []
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for element in caseDecl.elements {
                    let rawValue: String
                    if let literal = element.rawValue?.value.as(StringLiteralExprSyntax.self) {
                        rawValue = literal.representedLiteralValue ?? element.name.text
                    } else {
                        rawValue = element.name.text
                    }
                    rawValues.append(.init(element.name.text, .string(rawValue)))
                }
            }
            labels.append(.init(typeName: enumDecl.name.text, cases: TLARecord(rawValues)))
        }
        return labels
    }
}
