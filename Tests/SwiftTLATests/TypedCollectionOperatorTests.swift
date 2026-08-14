import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax
import Testing

@TLAModel
private struct TypedCollectionGeneratedModel {
    static var spec: TLASpec {
        #spec("TypedCollectionGeneratedModel") {
            let values = SharedVar(initial: IntRange(1, through: 4))
            Action("keepEvenSquares") {
                values.becomes(
                    values.expr
                        .filtering { value in value.expr % 2 == 0 }
                        .mapping { value in value.expr * value.expr }
                )
            }
        }
    }
}

@TLAModel
private struct TypedQuantifierGeneratedModel {
    static var spec: TLASpec {
        #spec("TypedQuantifierGeneratedModel") {
            let result = SharedVar(initial: false)
            Action("findEven") {
                result.becomes(Exists(in: IntRange(1, through: 4)) { value in
                    value.expr % 2 == 0
                })
            }
        }
    }
}

@Suite(.serialized) struct TypedCollectionOperatorTests {
    @Test("typed interval, filter, map, and dynamic tuple access evaluate")
    func typedOperatorsEvaluate() throws {
        let values = IntRange(1, through: 4)
        let evenValues = values.filtering { value in value.expr % 2 == 0 }
        let squares = evenValues.mapping { value in value.expr * value.expr }
        let expanded = squares.union(SetExpr<Int>.literal(25))
        let sequence = TupleExpr<Int>.literal(3, 5, 7)

        #expect(try values.raw.evaluate(in: [:]) == TLAValue.set([.int(1), .int(2), .int(3), .int(4)]))
        #expect(try evenValues.raw.evaluate(in: [:]) == TLAValue.set([.int(2), .int(4)]))
        #expect(try squares.raw.evaluate(in: [:]) == TLAValue.set([.int(4), .int(16)]))
        #expect(try expanded.raw.evaluate(in: [:]) == TLAValue.set([.int(4), .int(16), .int(25)]))
        #expect(try sequence.at(Expr<Int>(.int(2))).raw.evaluate(in: [:]) == .int(5))
    }

    @Test("source parser preserves typed collection operators")
    func parserPreservesTypedOperators() {
        let source = "IntRange(1, through: 4).filtering { value in value.expr % 2 == 0 }.mapping { value in value.expr * value.expr }.union(SetExpr<Int>.literal(25))"
        let syntax = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
        let parsed = SpecParser.decodeStateExpr(syntax)

        let values = IntRange(1, through: 4)
        let runtime = values.filtering { value in value.expr % 2 == 0 }
            .mapping { value in value.expr * value.expr }
            .union(SetExpr<Int>.literal(25))

        guard let parsed else {
            Issue.record("The typed collection expression did not parse")
            return
        }

        let parsedModel = ParsedSpecModel(
            variables: [],
            actions: [("evaluate", .guard_(parsed), [])],
            invariants: []
        )
        let runtimeModel = ParsedSpecModel(
            variables: [],
            actions: [("evaluate", .guard_(runtime.raw), [])],
            invariants: []
        )
        #expect(_tlaAlphaEquivalent(parsedModel, runtimeModel))
    }

    @Test("typed collection operators execute in a generated model")
    func generatedMachineUsesTypedCollectionOperators() throws {
        TypedCollectionGeneratedModel._checkParserTree()

        var model = TypedCollectionGeneratedModel()
        let result = try model.apply(.keepEvenSquares)

        #expect(Set(result.before.values.elements) == Set([1, 2, 3, 4]))
        #expect(Set(result.after.values.elements) == Set([4, 16]))
        #expect(TypedCollectionGeneratedModel.spec.tlaModule.contains("keepEvenSquares"))
    }

    @Test("typed bounded quantifiers parse, evaluate, and generate")
    func typedQuantifiersSurviveThePipeline() throws {
        let hasEven = Exists(in: IntRange(1, through: 4)) { value in
            value.expr % 2 == 0
        }
        let everyPositive = ForAll(in: IntRange(1, through: 4)) { value in
            value.expr > 0
        }
        #expect(try hasEven.raw.evaluate(in: [:]) == .bool(true))
        #expect(try everyPositive.raw.evaluate(in: [:]) == .bool(true))

        TypedQuantifierGeneratedModel._checkParserTree()
        var model = TypedQuantifierGeneratedModel()
        let result = try model.apply(.findEven)
        #expect(result.after.result == true)
        #expect(TypedQuantifierGeneratedModel.spec.tlaModule.contains("\\\\E"))
    }
}
