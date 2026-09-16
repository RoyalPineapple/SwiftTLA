import SwiftParser
import SwiftSyntax
@testable import SwiftTLAPlugin
import Testing

func swiftRecordMetadata(_ declarations: String, owner: String = "Model") throws -> SourceTypeMetadata {
    let source = Parser.parse(source: "struct \(owner) { \(declarations) }")
    let model = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
    return try TLASpecVerifier.sourceTypes(in: model.memberBlock.members, enums: [])
}
