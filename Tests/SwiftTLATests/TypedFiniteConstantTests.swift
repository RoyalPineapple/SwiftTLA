import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLAMacros
import Testing

@TLAModel
private struct TypedFiniteConstantGeneratedModel {
    static var spec: TLASpec {
        #spec("TypedFiniteConstantGeneratedModel") {
            Constant("Value", SetExpr<Int>(1, 2))
            let count = Var<Int>("count")
            Variable(count, 0)
        }
    }
}

@TLAModel
private struct VoteProofShapedConstantGeneratedModel {
    enum Value: String, FiniteTLAValueDomain {
        case v1, v2
        static let finiteValues: [Self] = [.v1, .v2]
    }

    enum Acceptor: String, FiniteTLAValueDomain {
        case a1, a2, a3
        static let finiteValues: [Self] = [.a1, .a2, .a3]
    }

    static var spec: TLASpec {
        #spec("VoteProofShapedConstantGeneratedModel") {
            Constant("Value", SetExpr<Value>(Value.v1, .v2))
            Constant("Acceptor", SetExpr<Acceptor>(.a1, Acceptor.a2, .a3))
            Constant("Quorum", SetExpr<SetExpr<Acceptor>>(
                SetExpr<Acceptor>(.a1, Acceptor.a2),
                SetExpr<Acceptor>(.a2, .a3)
            ))
            let count = Var<Int>("count")
            Variable(count, 0)
        }
    }
}

struct TypedFiniteConstantTests {
    @Test func builderRetainsAndExportsAClosedTypedFiniteSet() {
        let spec = TLASpec("TypedFiniteConstant") {
            Constant("Value", SetExpr<Int>(1, 2))
            let count = Var<Int>("count")
            Variable(count, 0)
        }

        #expect(spec.constants == ["Value": .set([.int(1), .int(2)])])
        #expect(spec.tlaModule.contains("ASSUME Value = {1, 2}"))
    }

    @Test func parserRetainsTheSameTypedFiniteSet() {
        let closure = Parser.parse(source: """
        {
            Constant("Value", SetExpr<Int>(1, 2))
            let count = Var<Int>("count")
            Variable(count, 0)
        }
        """).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.constants == ["Value": .set([.int(1), .int(2)])])
    }

    @Test func generatedModelRetainsTheTypedFiniteSet() {
        #expect(TypedFiniteConstantGeneratedModel.spec.constants == ["Value": .set([.int(1), .int(2)])])
        #expect(TypedFiniteConstantGeneratedModel.spec.tlaModule.contains("ASSUME Value = {1, 2}"))
    }

    @Test func generatedModelRetainsVoteProofShapedFiniteEnumConstants() {
        #expect(VoteProofShapedConstantGeneratedModel.spec.constants == [
            "Value": .set([.string("v1"), .string("v2")]),
            "Acceptor": .set([.string("a1"), .string("a2"), .string("a3")]),
            "Quorum": .set([
                .set([.string("a1"), .string("a2")]),
                .set([.string("a2"), .string("a3")])
            ])
        ])
        #expect(VoteProofShapedConstantGeneratedModel.spec.tlaModule.contains("ASSUME Value = {\"v1\", \"v2\"}"))
        #expect(VoteProofShapedConstantGeneratedModel.spec.tlaModule.contains("ASSUME Quorum = {{\"a1\", \"a2\"}, {\"a2\", \"a3\"}}"))
    }

    @Test func parserDiagnosesDynamicConstantValues() {
        let closure = Parser.parse(source: """
        {
            let values = Var<SetExpr<Int>>("values")
            Variable(values, SetExpr<Int>())
            Constant("Value", values)
        }
        """).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        guard let diagnostic = parsed.diagnostics.first else {
            Issue.record("Expected a dynamic constant diagnostic")
            return
        }
        #expect(diagnostic.message == "Constant 'Value' must be static; dynamic formal expressions are not constant values.")
        #expect(diagnostic.expected == "a literal value or SetExpr<Element>(...) with static members")
        #expect(diagnostic.changeStatus == .noFormalModelWasBuilt)
    }
}
