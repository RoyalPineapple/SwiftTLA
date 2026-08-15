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

@TLAModel
private struct NonEmptySubsetGeneratedModel {
    static var spec: TLASpec {
        #spec("NonEmptySubsetGeneratedModel") {
            Algorithm("NonEmptySubsetGeneratedModel") {
                let selectedKeys = SharedVar(in: NonEmptySubsets(
                    of: SetExpr<Int>.literal(1, 2)
                ))
                Do("keep") { Assign(selectedKeys, to: selectedKeys.expr) }
            }
        }
    }
}

@TLAModel
private struct ZeroBasedSequenceGeneratedModel {
    static var spec: TLASpec {
        #spec("ZeroBasedSequenceGeneratedModel") {
            Algorithm("ZeroBasedSequenceGeneratedModel") {
                let input = SharedVar(in: ZeroBasedSequences(
                    of: SetExpr<Int>.literal(0, 1),
                    lengths: 1...2
                ))
                let table = SharedVar(initial: ZeroBasedSequence<Int>.filled(
                    length: input.count * 2 + 1,
                    with: -1
                ))

                Do("writeFirst") {
                    Assign(table, to: table.updating(0, to: input[0]))
                }
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

    @Test("typed conditional values parse without losing their result type")
    func typedConditionalValueParses() {
        let source = "If(true, then: 1, else: 2)"
        let syntax = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!

        #expect(
            SpecParser.decodeStateExpr(syntax)
                == .ifThenElse(.value(.bool(true)), .value(.int(1)), .value(.int(2)))
        )
    }

    @Test("bounded sequence domains and terminal predicates parse as formal expressions")
    func boundedSequencesAndFinishedParse() throws {
        let sequenceSource = "Sequences(of: SetExpr<Int>.literal(0, 1), lengths: 0...2)"
        let sequenceSyntax = Parser.parse(source: sequenceSource).statements.first!.item.as(ExprSyntax.self)!
        let sortedSource = "SortedSequences(of: SetExpr<Int>.literal(0, 1, 2), lengths: 0...2)"
        let sortedSyntax = Parser.parse(source: sortedSource).statements.first!.item.as(ExprSyntax.self)!
        let terminalSource = "(!Finished()) || i == f.count + 1"
        let terminalSyntax = Parser.parse(source: terminalSource).statements.first!.item.as(ExprSyntax.self)!

        let runtime = Sequences(of: SetExpr<Int>.literal(0, 1), lengths: 0...2)
        let sortedRuntime = SortedSequences(of: SetExpr<Int>.literal(0, 1, 2), lengths: 0...2)
        let parsed = try #require(SpecParser.decodeStateExpr(sequenceSyntax))
        let parsedSorted = try #require(SpecParser.decodeStateExpr(sortedSyntax))

        #expect(try runtime.raw.evaluate(in: [:]) == .set([
            .tuple([]), .tuple([.int(0)]), .tuple([.int(1)]),
            .tuple([.int(0), .int(0)]), .tuple([.int(0), .int(1)]),
            .tuple([.int(1), .int(0)]), .tuple([.int(1), .int(1)])
        ]))
        #expect(parsed == runtime.raw)
        #expect(parsedSorted == sortedRuntime.raw)
        #expect(try sortedRuntime.raw.evaluate(in: [:]) == .set([
            .tuple([]),
            .tuple([.int(0)]), .tuple([.int(1)]), .tuple([.int(2)]),
            .tuple([.int(0), .int(0)]), .tuple([.int(0), .int(1)]), .tuple([.int(0), .int(2)]),
            .tuple([.int(1), .int(1)]), .tuple([.int(1), .int(2)]), .tuple([.int(2), .int(2)])
        ]))
        #expect(SpecParser.decodeStateExpr(terminalSyntax) != nil)
    }

    @Test("zero-based sequence domains and indexed updates survive both paths")
    func zeroBasedSequencesSurviveThePipeline() throws {
        let source = "ZeroBasedSequences(of: SetExpr<Int>.literal(0, 1), lengths: 1...2)"
        let syntax = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))
        let runtime = ZeroBasedSequences(of: SetExpr<Int>.literal(0, 1), lengths: 1...2)

        #expect(parsed == runtime.raw)
        #expect(try runtime.raw.evaluate(in: [:]) == .set([
            .function([.int(0): .int(0)]),
            .function([.int(0): .int(1)]),
            .function([.int(0): .int(0), .int(1): .int(0)]),
            .function([.int(0): .int(0), .int(1): .int(1)]),
            .function([.int(0): .int(1), .int(1): .int(0)]),
            .function([.int(0): .int(1), .int(1): .int(1)])
        ]))

        ZeroBasedSequenceGeneratedModel._checkParserTree()
        var model = ZeroBasedSequenceGeneratedModel()
        let result = try model.apply(.writeFirst)
        #expect(result.after.table[0] == result.after.input[0])
        #expect(ZeroBasedSequenceGeneratedModel.spec.tlaModule.contains("0.."))
    }

    @Test("non-empty subset domains parse and exclude the empty formal set")
    func nonEmptySubsetDomainsSurviveThePipeline() throws {
        let source = "NonEmptySubsets(of: SetExpr<Int>.literal(1, 2))"
        let syntax = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))
        let runtime = NonEmptySubsets(of: SetExpr<Int>.literal(1, 2))

        #expect(parsed == runtime.raw)
        #expect(try runtime.raw.evaluate(in: [:]) == .set([
            .set([.int(1)]),
            .set([.int(2)]),
            .set([.int(1), .int(2)])
        ]))

        NonEmptySubsetGeneratedModel._checkParserTree()
        let initialStates = computeInitialStates(NonEmptySubsetGeneratedModel.spec)
        #expect(initialStates.count == 3)
        let representative = NonEmptySubsetGeneratedModel.spec.variables.first?.initial
        #expect(initialStates.contains { $0["selectedKeys"] == representative })
        #expect(NonEmptySubsetGeneratedModel.spec.tlaModule.contains("SUBSET"))
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
        #expect(TypedQuantifierGeneratedModel.spec.tlaModule.contains("\\E"))
    }
}
