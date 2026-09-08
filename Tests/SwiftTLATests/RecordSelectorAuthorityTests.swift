import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA

struct RecordSelectorAuthorityTests {
    private func expression(_ source: String) throws -> ExprSyntax {
        try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
    }

    @Test("Escaped and unescaped enum references resolve the same semantic case")
    func escapedEnumReferencesResolve() throws {
        let parser = ParserSession(enumDefinitions: [
            .init(typeName: "Step", cases: TLARecord([.init("repeat", .string("repeat"))]))
        ])
        for source in ["Step.repeat", "Step.`repeat`"] {
            #expect(parser.decodeTypedFacadeValue(try expression(source), scope: .empty)
                == .value(.string("repeat")))
        }
    }

    @Test("Registered schema selectors use their declared formal field name")
    func schemaSelectorsPreserveFormalNames() throws {
        let parser = ParserSession(recordSchemas: ["OperationSchema": [
            .init(sourceName: "operation", name: "op", swiftType: "String")
        ]])
        for source in ["record[OperationSchema.operation]", "record[Model.OperationSchema.operation]"] {
            #expect(parser.decodeTypedFacadeValue(try expression(source), scope: .empty)
                == .recordAccess(.variable("record"), "op"))
        }
        #expect(parser.typedUpdateSelector(try expression("OperationSchema.operation"), scope: .empty)
            == .value(.string("op")))
    }

    @Test("Facade member expressions remain dictionary keys")
    func expressionKeysAreNotRecordSelectors() throws {
        let parser = ParserSession()
        for source in ["store[key.expr]", "store[key.raw]", "store[key.stateExpr]"] {
            #expect(parser.decodeTypedFacadeValue(try expression(source), scope: .empty)
                == .functionApply(.variable("store"), .variable("key")))
        }
        #expect(parser.typedUpdateSelector(try expression("key.expr"), scope: .empty)
            == .variable("key"))
        #expect(parser.typedFieldName(try expression("UnknownSchema.field")) == nil)
    }
}
