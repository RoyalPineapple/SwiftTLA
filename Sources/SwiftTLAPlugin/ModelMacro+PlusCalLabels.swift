import SwiftSyntax
import SwiftTLA

extension TLASpecVerifier {
    static func collectEnumPhaseMap(
        from members: MemberBlockItemListSyntax
    ) -> (phases: EnumPhaseMap, caseToType: [String: String]) {
        let infos = collectEnumVariables(from: members)
        var phases: EnumPhaseMap = [:]
        var caseToType: [String: String] = [:]
        for info in infos {
            var caseMap: [String: TLAValue] = [:]
            for (caseName, value) in info.cases {
                caseMap[caseName] = value
                caseToType[caseName] = info.typeName
            }
            phases[info.typeName] = caseMap
        }
        return (phases, caseToType)
    }

    static func collectEnumMetadata(
        from members: MemberBlockItemListSyntax
    ) -> (phases: EnumPhaseMap, caseToType: [String: String]) {
        let metadata = collectEnumPhaseMap(from: members)
        return (
            metadata.phases.merging(collectPlusCalLabelMap(from: members)) { existing, _ in existing },
            metadata.caseToType
        )
    }

    /// Retains raw `PlusCalLabel` values for the parser without treating labels
    /// as state domains or rewriting unqualified enum cases in expressions.
    static func collectPlusCalLabelMap(from members: MemberBlockItemListSyntax) -> EnumPhaseMap {
        var labels: EnumPhaseMap = [:]
        for member in members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self),
                  let inheritance = enumDecl.inheritanceClause
            else { continue }
            let inheritedNames = inheritance.inheritedTypes.compactMap {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text
            }
            guard inheritedNames.contains("PlusCalLabel"), inheritedNames.contains("String") else { continue }

            var rawValues: [String: TLAValue] = [:]
            for caseMember in enumDecl.memberBlock.members {
                guard let caseDecl = caseMember.decl.as(EnumCaseDeclSyntax.self) else { continue }
                for element in caseDecl.elements {
                    let rawValue: String
                    if let literal = element.rawValue?.value.as(StringLiteralExprSyntax.self) {
                        rawValue = literal.representedLiteralValue ?? literal.segments.description
                    } else {
                        rawValue = element.name.text
                    }
                    rawValues[element.name.text] = .string(rawValue)
                }
            }
            labels[enumDecl.name.text] = rawValues
        }
        return labels
    }
}
