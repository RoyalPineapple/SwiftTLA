import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct TypedFacadeSyntaxTests {
    @Test("typed facade grammar accepts only its declared module qualification")
    func admitsOnlyDeclaredTypedFacadeQualification() throws {
        let unqualified = try parseSpecTestExpression("SetExpr<Int>()")
        let swiftTLAQualified = try parseSpecTestExpression("SwiftTLA.SetExpr<Int>()")
        let unrelatedQualified = try parseSpecTestExpression("Other.SetExpr<Int>()")
        let unqualifiedParameter = try parseSpecTestExpression(#"Parameter("value")"#)
        let swiftTLAQualifiedParameter = try parseSpecTestExpression(#"SwiftTLA.Parameter("value")"#)
        let unrelatedQualifiedParameter = try parseSpecTestExpression(#"Other.Parameter("value")"#)
        let parameter = StateExpr.variable("value")

        #expect(SpecParser.decodeTypedFacadeValue(unqualified) == .value(.set([])))
        #expect(SpecParser.decodeTypedFacadeValue(swiftTLAQualified) == .value(.set([])))
        #expect(SpecParser.decodeTypedFacadeValue(unrelatedQualified) == nil)
        #expect(SpecParser.decodeTypedFacadeValue(unqualifiedParameter) == parameter)
        #expect(SpecParser.decodeTypedFacadeValue(swiftTLAQualifiedParameter) == parameter)
        #expect(SpecParser.decodeTypedFacadeValue(unrelatedQualifiedParameter) == nil)
    }

    @Test("qualified empty set uses its structural type")
    func parsesQualifiedEmptySet() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseSpecTestExpression("SwiftTLA.SetExpr<Int>()"))
                == .value(.set([]))
        )
    }

    @Test("formal names must be static")
    func rejectsInterpolatedFormalNames() throws {
        #expect(SpecParser.decodeTypedFacadeValue(
            try parseSpecTestExpression(#"FormalCall(as: Bool.self, "Safe\(suffix)")"#)
        ) == nil)
        #expect(SpecParser.decodeTypedFacadeValue(
            try parseSpecTestExpression(#"ModuleCall("Instance\(suffix)", "Value")"#)
        ) == nil)
        #expect(SpecParser.decodeStateExpr(
            try parseSpecTestExpression(#"At("step\(suffix)", worker)"#)
        ) == nil)
    }

    @Test("control locations require a declared label case")
    func requiresDeclaredControlLocation() throws {
        let parser = ParserSession(sourceTypes: .init(enums: [
            parserTestEnum("Label", cases: ["receive": .string("receive")])
        ]))
        let expected = StateExpr.equal(
            .functionApply(.programCounter, .variable("worker")),
            .controlLocation(.init("receive"))
        )

        #expect(parser.decodeStateExpr(
            try parseSpecTestExpression("At(Label.receive, worker)")
        ) == expected)
        for source in [
            #"At("receive", worker)"#,
            "At(.receive, worker)",
            "At(Other.receive, worker)",
            "At(Label.missing, worker)"
        ] {
            #expect(parser.decodeStateExpr(try parseSpecTestExpression(source)) == nil)
        }
    }
}
