import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct StateExprStaticCallTests {
    @Test("formal collections and choices reject every undecodable operand", arguments: [
        "StateExpr.set([1, makeValue(), 3])",
        "StateExpr.tuple([1, makeValue(), 3])",
        "StateExpr.set([makeValue()])",
        "StateExpr.singleton(makeValue())",
        "StateExpr.any(from: makeDomain(), StateExpr.set([1]))"
    ])
    func rejectsUndecodableCollectionOperands(_ source: String) throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)) == nil)
        let parsed = SpecParser.parseSpecClosure(named: "InvalidOperand", try parseSpecTestClosure("""
        {
            Invariant("SameValue") { \(source) == \(source) }
        }
        """))
        #expect(!parsed.diagnostics.isEmpty)
        #expect(throws: SourceParseDiagnostic.self) { try parsed.compile() }
    }

    @Test("empty collection literals remain valid", arguments: ["set", "tuple"])
    func emptyCollectionLiterals(_ kind: String) throws {
        let decoded = SpecParser.decodeStateExpr(try parseSpecTestExpression("StateExpr.\(kind)([])"))
        let expected: StateExpr = kind == "set" ? .setLiteral([]) : .tupleLiteral([])
        #expect(decoded == expected)
    }

    @Test func parseStaticSet() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseSpecTestExpression("StateExpr.set([1, 2, 3])"))
                == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        )
    }

    @Test func parseStaticTuple() throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression("StateExpr.tuple([1, x])")) == StateExpr.tupleLiteral([.value(.int(1)), .variable("x")]))
    }

    @Test func parseStaticRecord() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseSpecTestExpression("StateExpr.record(name: x, age: 42)"))
                == StateExpr.record(["name": .variable("x"), "age": .value(.int(42))])
        )
    }

    @Test func parseStaticIf() throws {
        let decodedExpression = SpecParser.decodeStateExpr(try parseSpecTestExpression("StateExpr.if(x == 0, then: 1, else: 2)"))
        #expect(decodedExpression == StateExpr.ifThenElse(
            StateExpr.equal(.variable("x"), .value(.int(0))),
            .value(.int(1)),
            .value(.int(2))
        ))
    }

    @Test func parseStaticFunction() throws {
        #expect(SpecParser.decodeStateExpr(
            try parseSpecTestExpression("StateExpr.functionLiteral(StateExpr.set([1, 2]), \"x\", x + 1)")
        ) == .functionLiteral(
            .setLiteral([.int(1), .int(2)]),
            "x",
            .add(.variable("x"), .int(1))
        ))
    }

    @Test func parseStaticForAll() throws {
        #expect(SpecParser.decodeStateExpr(
            try parseSpecTestExpression("StateExpr.forAll(StateExpr.set([1, 2]), \"x\", x > 0)")
        ) == .forAll(
            .setLiteral([.int(1), .int(2)]),
            "x",
            .greaterThan(.variable("x"), .int(0))
        ))
    }

    @Test func parseStaticExists() throws {
        #expect(SpecParser.decodeStateExpr(
            try parseSpecTestExpression("StateExpr.exists(StateExpr.set([1, 2]), \"x\", x > 0)")
        ) == .exists(
            .setLiteral([.int(1), .int(2)]),
            "x",
            .greaterThan(.variable("x"), .int(0))
        ))
    }

    @Test func parseStaticChoose() throws {
        #expect(SpecParser.decodeStateExpr(
            try parseSpecTestExpression("StateExpr.choose(StateExpr.set([1, 2]), \"x\", x > 0)")
        ) == .choose(
            .setLiteral([.int(1), .int(2)]),
            "x",
            .greaterThan(.variable("x"), .int(0))
        ))
    }

    @Test func parseStaticAny() throws {
        guard case .choose(
            .setLiteral([.int(1), .int(2)]),
            _,
            .value(.bool(true)),
            _
        ) = SpecParser.decodeStateExpr(
            try parseSpecTestExpression("StateExpr.any(from: StateExpr.set([1, 2]))")
        ) else {
            Issue.record("Expected a choice over the declared set")
            return
        }
    }

    @Test(arguments: ["", "Expr<Int>", "SwiftTLA.Expr<Int>", "Expr", "SwiftTLA.Expr"])
    func parseStaticFirstMatchWithFallback(_ constructor: String) throws {
        let values = ["10", "20", "99"].map { constructor.isEmpty ? $0 : "\(constructor)(\($0)).stateExpr" }
        let decodedExpression = SpecParser.decodeStateExpr(
            try parseSpecTestExpression("StateExpr.firstMatch((when: x == 0, then: \(values[0])), (when: x == 1, then: \(values[1])), fallback: \(values[2]))")
        )
        #expect(decodedExpression == StateExpr.caseExpr(
            [
                StateExpr.equal(.variable("x"), .value(.int(0))), .value(.int(10)),
                StateExpr.equal(.variable("x"), .value(.int(1))), .value(.int(20))
            ],
            .value(.int(99))
        ))
    }

    @Test(arguments: ["", "Expr<Int>", "SwiftTLA.Expr<Int>", "Expr", "SwiftTLA.Expr"])
    func parseStaticFirstMatchNoFallback(_ constructor: String) throws {
        let value = constructor.isEmpty ? "-1" : "\(constructor)(-1).stateExpr"
        let decodedExpression = SpecParser.decodeStateExpr(
            try parseSpecTestExpression("StateExpr.firstMatch((when: x < 0, then: \(value)))")
        )
        #expect(decodedExpression == StateExpr.caseExpr(
            [StateExpr.lessThan(.variable("x"), .value(.int(0))), StateExpr.value(.int(-1))],
            nil
        ))
    }
}
