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
                finiteValues: info.finiteValues
            )
        }
        return definitions
    }
}
