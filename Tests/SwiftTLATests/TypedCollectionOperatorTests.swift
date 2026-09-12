@testable import SwiftTLAPlugin
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax
import Testing
import Foundation

private func parseExpression(_ source: String) throws -> ExprSyntax {
    try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
}

private struct DecodedLiteral: TLAValueType {
    let number: Int
    let decodingID = UUID()
    let invalid: Bool

    init(_ number: Int, invalid: Bool = false) {
        self.number = number
        self.invalid = invalid
    }

    init?(formalValue: TLAValue) {
        guard case .int(let number) = formalValue else { return nil }
        self.init(number, invalid: number < 0)
    }

    static var defaultValue: Self { Self(0) }
    var tlaValue: TLAValue { .int(number) }
    var sourceIssue: SourceModelIssue? {
        invalid ? .finiteDomainValue(type: "DecodedLiteral", value: String(number)) : nil
    }
}

private enum DecodedRecordSchema: TLARecordSchema {
    struct Fields {
        let member: DecodedLiteral
    }

    static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String? {
        field == \Fields.member ? "member" : nil
    }

    static let member = field(\Fields.member)
    static let fields = [
        TLARecordFieldDeclaration(member, default: DecodedLiteral(1, invalid: true))
    ]
}

private enum InvalidLiteralDomain: String, CaseIterable, FiniteTLAValueDomain {
    case first
    case second

    static var defaultValue: Self { .first }
    static let finiteValues = allCases
}

private enum EmptyFiniteDomain: String, FiniteTLAValueDomain {
    case placeholder

    static var defaultValue: Self { .placeholder }
    static let finiteValues: [Self] = []
}

private enum DuplicateFiniteDomain: String, FiniteTLAValueDomain {
    case first

    static var defaultValue: Self { .first }
    static let finiteValues: [Self] = [.first, .first]
}

private enum PartialFiniteDomain: String, FiniteTLAValueDomain {
    case first
    case second

    static var defaultValue: Self { .first }
    static let finiteValues: [Self] = [.first]
}

private struct InvalidLiteralFields {
    let count: Int
    let enabled: Bool
    let unlisted: Int
}

private enum InvalidLiteralSchema: TLARecordSchema {
    typealias Fields = InvalidLiteralFields

    static func fieldName<Value>(for field: KeyPath<InvalidLiteralFields, Value>) -> String? {
        let key = field as AnyKeyPath
        if key == \InvalidLiteralFields.count { return "count" }
        if key == \InvalidLiteralFields.enabled { return "enabled" }
        return nil
    }

    static let count = field(\InvalidLiteralFields.count)
    static let enabled = field(\InvalidLiteralFields.enabled)
    static let unlisted = field(\InvalidLiteralFields.unlisted)
    static let fields = [
        TLARecordFieldDeclaration(count, default: 0),
        TLARecordFieldDeclaration(enabled, default: false)
    ]
}

@TLAModel
private struct TypedCollectionGeneratedModel {
    enum Step: String, CaseIterable { case keepEvenSquares }

    static var spec: TLASpec {
        #spec("TypedCollectionGeneratedModel") { scope in
            Algorithm("TypedCollectionGeneratedModel", scoped: { algorithm in
                let values = algorithm.sharedVar("values", initial: IntRange(1, through: 4))
                Do(Step.keepEvenSquares) {
                    Assign(values, to:
                        values.expr
                            .filtering { value in value.expr % 2 == 0 }
                            .mapping { value in value.expr * value.expr }
                    )
                }
            })
        }
    }
}

@TLAModel
private struct TypedQuantifierGeneratedModel {
    enum Step: String, CaseIterable { case findEven }

    static var spec: TLASpec {
        #spec("TypedQuantifierGeneratedModel") { scope in
            Algorithm("TypedQuantifierGeneratedModel", scoped: { algorithm in
                let result = algorithm.sharedVar("result", initial: false)
                Do(Step.findEven) {
                    Assign(result, to: Exists(in: IntRange(1, through: 4)) { value in
                        value.expr % 2 == 0
                    })
                }
            })
        }
    }
}

@TLAModel
private struct NonEmptySubsetGeneratedModel {
    enum Step: String, CaseIterable { case keep }

    static var spec: TLASpec {
        #spec("NonEmptySubsetGeneratedModel") {
            Algorithm("NonEmptySubsetGeneratedModel", scoped: { scope in
                let selectedKeys = scope.sharedVar("selectedKeys", in: NonEmptySubsets(
                    of: SetExpr<Int>.literal(1, 2)
                ))
                Do(Step.keep) { Assign(selectedKeys, to: selectedKeys.expr) }
            })
        }
    }
}

@TLAModel
private struct ZeroBasedSequenceGeneratedModel {
    enum Step: String, CaseIterable { case writeFirst }

    static var spec: TLASpec {
        #spec("ZeroBasedSequenceGeneratedModel") {
            Algorithm("ZeroBasedSequenceGeneratedModel", scoped: { scope in
                let input = scope.sharedVar("input", in: ZeroBasedSequences(
                    of: SetExpr<Int>.literal(0, 1),
                    lengths: 1...2
                ))
                let table = scope.sharedVar("table", initial: ZeroBasedSequence<Int>.filled(
                    length: input.count * 2 + 1,
                    with: -1
                ))

                Do(Step.writeFirst) {
                    Assign(table, to: table.updating(0, to: input[0]))
                }
            })
        }
    }
}

@TLAModel
private struct ContextualCollectionModel {
    enum Key: String, CaseIterable, FiniteTLAValueDomain {
        case first = "key-first", second = "key-second"
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
    }
    enum Entry: String, CaseIterable, FiniteTLAValueDomain {
        case first = "entry-first", second = "entry-second"
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
    }
    enum Step: String, CaseIterable { case update, read }

    static var spec: TLASpec {
        #spec("ContextualCollectionModel") {
            Algorithm("ContextualCollectionModel", scoped: { scope in
                let table = scope.sharedVar("table", initial: Function<Key, Entry>.literal(
                    (Key.first, Entry.first), (Key.second, Entry.first)))
                let selected: SharedVariable<Entry> = scope.sharedVar("selected", initial: .first)
                Do(Step.update) {
                    Await(selected == .first)
                    Assign(table, to: table.updating(.first) { current in
                        If(current == .first, then: .second, else: current)
                    })
                }
                Do(Step.read) {
                    Assign(selected, to: table.updating(.second, to: .second)[.first])
                }
            })
        }
    }
}

@TLAModel
private struct FoldGeneratedModel {
    enum Step: String, CaseIterable { case sum }

    static var spec: TLASpec {
        #spec("FoldGeneratedModel") {
            Import(FunctionsModule.module)
            Algorithm("FoldGeneratedModel", scoped: { scope in
                let values = scope.sharedVar("values", initial: TupleExpr<Int>.literal(1, 2, 3))
                let total = scope.sharedVar("total", initial: 0)
                Do(Step.sum) {
                    Assign(total, to: Fold(values.expr, startingWith: 0) { element, accumulated in
                        element + accumulated
                    })
                }
            })
        }
    }
}

@Suite(.serialized) struct TypedCollectionOperatorTests {
    @Test("record construction and updates accept typed action parameters")
    func recordActionParameters() throws {
        let record = Var<Record<InvalidLiteralSchema>>("record")
        let input = ActionParameter("input", values: [1, 2])
        let specification = TLASpec("RecordActionParameters") {
            Variable(record, Record<InvalidLiteralSchema>())
            Action("construct", parameters: [input]) {
                record.becomes(Record<InvalidLiteralSchema>.literal(
                    .init(InvalidLiteralSchema.count, input), .init(InvalidLiteralSchema.enabled, false)))
            }
            Action("update", parameters: [input]) {
                record.becomes(record.updating(InvalidLiteralSchema.count, to: input))
            }
        }
        let compilation = try specification.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let token = try #require(TLAStateProjection.Token(validating: "record"))
        for action in compilation.layout.actions {
            let successors = try runtime.successors(for: action.id, from: initial)
            let records = try successors.map { successor in
                let projection = try successor.state.projection(using: compilation.layout)
                return try #require(projection.value(for: token).flatMap(Record<InvalidLiteralSchema>.init(formalValue:)))
            }
            #expect(records.count == 2)
            #expect(try Set(records.map { try #require($0.value(for: InvalidLiteralSchema.count)) }) == [1, 2])
            #expect(records.allSatisfy { $0.value(for: InvalidLiteralSchema.enabled) == false })
        }
    }

    @Test("Collection values retain typed elements without decoding them again")
    func collectionElementsDecodeOnce() throws {
        let tuple = try #require(TupleExpr<DecodedLiteral>(formalValue: .tuple([.int(1), .int(2)])))
        let tupleIDs = tuple.elements.map(\.decodingID)
        #expect(tuple.elements.map(\.decodingID) == tupleIDs)
        #expect(tuple.tlaValue == .tuple([.int(1), .int(2)]))

        let first = DecodedLiteral(1)
        let set = SetExpr(first, DecodedLiteral(1), DecodedLiteral(2))
        #expect(set.elements.count == 2)
        #expect(set.elements.contains { $0.decodingID == first.decodingID })
        let decoded = try #require(SetExpr<DecodedLiteral>(formalValue: .set([.int(1), .int(2)])))
        let setIDs = Set(decoded.elements.map(\.decodingID))
        #expect(Set(decoded.elements.map(\.decodingID)) == setIDs)
        #expect(Set([set, decoded]).count == 1)
        #expect(set.tlaValue == .set([.int(1), .int(2)]))
    }

    @Test("Invalid modeled values fail through every constant-expression boundary")
    func invalidValuesCannotLoseTheirDiagnostics() throws {
        let invalid = DecodedLiteral(1, invalid: true)
        let expressions: [StateExpr] = [
            invalid.stateExpr,
            invalid.expr.raw,
            SetExpr(DecodedLiteral(1), invalid).stateExpr,
            SetExpr<DecodedLiteral>.literal(invalid).raw,
            TupleExpr<DecodedLiteral>.literal(invalid).raw,
            Pair(first: invalid, second: 1).stateExpr,
            Pair<DecodedLiteral, Int>.literal(invalid, 1).raw,
            ZeroBasedSequence<DecodedLiteral>.literal(invalid).raw,
            ZeroBasedSequence<DecodedLiteral>.filled(length: 1.expr, with: invalid).raw,
            PartialFunction<PartialFiniteDomain, DecodedLiteral>.literal((.first, invalid)).raw,
            Function<PartialFiniteDomain, DecodedLiteral>.literal(
                (.first, invalid), (.second, DecodedLiteral(2))
            ).raw,
            SetExpr<DecodedLiteral>().expr.removing(invalid).raw,
            Function<DuplicateFiniteDomain, Int>().stateExpr
        ]
        for expression in expressions {
            let specification = TLASpec(name: "InvalidValue", variables: [
                .init(name: "value", initialization: .expression(expression), origin: .source)
            ], actions: [], invariants: [])
            #expect(throws: CompilationDiagnostic.self) { try specification.compile() }
        }
        #expect(SetExpr<DecodedLiteral>(formalValue: .set([.int(-1)])) == nil)
        #expect(TupleExpr<DecodedLiteral>(formalValue: .tuple([.int(-1)])) == nil)
        #expect(Pair<DecodedLiteral, Int>(formalValue: .tuple([.int(-1), .int(1)])) == nil)
    }

    @Test("Function and zero-based sequence reads retain decoded values")
    func indexedValuesDecodeOnce() throws {
        let raw: TLAValue = .function([.string("first"): .int(1)])
        let total = try #require(Function<PartialFiniteDomain, DecodedLiteral>(formalValue: raw))
        let partial = try #require(PartialFunction<PartialFiniteDomain, DecodedLiteral>(formalValue: raw))
        let totalValue = try #require(total[.first])
        let partialValue = try #require(partial[.first])
        #expect(total[.first]?.decodingID == totalValue.decodingID)
        #expect(partial[.first]?.decodingID == partialValue.decodingID)
        #expect(total[.second] == nil)
        #expect(partial[.second] == nil)
        #expect(total.tlaValue == raw)
        #expect(partial.tlaValue == raw)
        let anotherTotal = try #require(Function<PartialFiniteDomain, DecodedLiteral>(formalValue: raw))
        let anotherPartial = try #require(PartialFunction<PartialFiniteDomain, DecodedLiteral>(formalValue: raw))
        #expect(Set([total, anotherTotal]).count == 1)
        #expect(Set([partial, anotherPartial]).count == 1)

        let sequenceValue: TLAValue = .function([.int(0): .int(1), .int(1): .int(2)])
        let sequence = try #require(ZeroBasedSequence<DecodedLiteral>(formalValue: sequenceValue))
        let first = try #require(sequence.element(at: 0))
        #expect(sequence.element(at: 0)?.decodingID == first.decodingID)
        #expect(sequence.element(at: 1)?.number == 2)
        #expect(sequence.element(at: -1) == nil)
        #expect(sequence.element(at: 2) == nil)
        #expect(sequence.tlaValue == sequenceValue)
        let anotherSequence = try #require(ZeroBasedSequence<DecodedLiteral>(formalValue: sequenceValue))
        #expect(Set([sequence, anotherSequence]).count == 1)
    }

    @Test("Indexed values reject invalid decoded members and malformed domains")
    func indexedValuesRejectInvalidData() {
        let invalid: TLAValue = .function([.string("first"): .int(-1)])
        #expect(Function<PartialFiniteDomain, DecodedLiteral>(formalValue: invalid) == nil)
        #expect(PartialFunction<PartialFiniteDomain, DecodedLiteral>(formalValue: invalid) == nil)
        let malformedSequences: [TLAValue] = [
            .function([.int(0): .int(-1)]),
            .function([.int(-1): .int(1)]),
            .function([.int(1): .int(1)]),
            .function([.int(0): .int(1), .int(2): .int(2)]),
            .function([.string("0"): .int(1)]),
            .function([.int(0): .bool(true)])
        ]
        for value in malformedSequences {
            #expect(ZeroBasedSequence<DecodedLiteral>(formalValue: value) == nil)
        }
        #expect(ZeroBasedSequence<DecodedLiteral>(formalValue: .function([:])) != nil)
    }

    @Test("Record field reads retain the validated Swift value")
    func recordFieldsDecodeOnce() throws {
        let raw: TLAValue = .record(["member": .int(1)])
        let record = try #require(Record<DecodedRecordSchema>(formalValue: raw))
        let value = try #require(record.value(for: DecodedRecordSchema.member))
        #expect(record.value(for: DecodedRecordSchema.member)?.decodingID == value.decodingID)
        #expect(record.sourceIssue == nil)
        #expect(record.tlaValue == raw)
        let another = try #require(Record<DecodedRecordSchema>(formalValue: raw))
        #expect(Set([record, another]).count == 1)
    }

    @Test("Records reject invalid decoded fields and preserve invalid defaults")
    func recordsRejectInvalidData() throws {
        let invalidRecords: [TLAValue] = [
            .record(["member": .int(-1)]),
            .record(["member": .bool(true)]),
            .record([:]),
            .record(["member": .int(1), "extra": .int(2)]),
            .record(TLARecord([.init("member", .int(1)), .init("member", .int(2))]))
        ]
        for raw in invalidRecords {
            #expect(Record<DecodedRecordSchema>(formalValue: raw) == nil)
        }
        let defaultRecord = Record<DecodedRecordSchema>()
        let defaultMember = try #require(defaultRecord.value(for: DecodedRecordSchema.member))
        #expect(defaultRecord.sourceIssue == defaultMember.sourceIssue)
        #expect(defaultRecord.sourceIssue != nil)
        let specification = TLASpec(name: "InvalidRecordDefault", variables: [
            .init(name: "value", initialization: .expression(defaultRecord.stateExpr), origin: .source)
        ], actions: [], invariants: [])
        #expect(throws: CompilationDiagnostic.self) { try specification.compile() }
    }

    @Test("Swift set deduplication cannot erase a modeled value's validation failure")
    func deduplicationPreservesValidationFailures() throws {
        func check<Value: TLAValueType & Hashable>(_ valid: Value, _ invalid: Value) throws {
            #expect(valid.tlaValue == invalid.tlaValue)
            #expect(valid.sourceIssue == nil)
            #expect(invalid.sourceIssue != nil)
            #expect(valid != invalid)
            for members in [Set([valid, invalid]), Set([invalid, valid])] {
                #expect(members.count == 2)
                #expect(members.filter { $0.sourceIssue != nil }.count == 1)
                let expression = StateExpr.setLiteral(members.map(\.stateExpr))
                let specification = TLASpec(name: "InvalidSetMember", variables: [
                    .init(name: "value", initialization: .expression(expression), origin: .source)
                ], actions: [], invariants: [])
                #expect(throws: CompilationDiagnostic.self) { try specification.compile() }
            }
        }
        try check(SetExpr(DecodedLiteral(1)), SetExpr(DecodedLiteral(1, invalid: true)))
        try check(Pair(first: DecodedLiteral(1), second: 2),
                  Pair(first: DecodedLiteral(1, invalid: true), second: 2))
        let rawRecord: TLAValue = .record(["member": .int(1)])
        let record = try #require(Record<DecodedRecordSchema>(formalValue: rawRecord))
        try check(record, Record<DecodedRecordSchema>())
        let function = try #require(Function<PartialFiniteDomain, Record<DecodedRecordSchema>>(
            formalValue: .function([.string("first"): rawRecord])))
        try check(function, Function<PartialFiniteDomain, Record<DecodedRecordSchema>>())
    }

    @Test("Native collection access uses contextual enum keys and values")
    func contextualCollectionAccessExecutesNatively() throws {
        var machine = try ContextualCollectionModel.makeMachine()
        _ = try machine.send(.update)
        #expect(machine.state.table[.first] == .second)
        #expect(machine.state.table[.second] == .first)
        _ = try machine.send(.read)
        #expect(machine.state.selected == .second)
    }

    @Test("Constants preserve validation failures even when unused")
    func invalidConstantsFailCompilation() throws {
        let constants = [
            Constant("invalid", DecodedLiteral(1, invalid: true)),
            Constant("invalid", Pair(first: DecodedLiteral(1, invalid: true), second: 2)),
            Constant("invalid", SetExpr(DecodedLiteral(1), DecodedLiteral(1, invalid: true)))
        ]
        for constant in constants {
            let specification = TLASpec(name: "InvalidConstant", variables: [],
                                        constants: [constant], actions: [], invariants: [])
            do {
                _ = try specification.compile()
                Issue.record("Compilation accepted an invalid constant")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "constants.invalid")
            }
        }
        let valid = TLASpec(name: "ValidConstant", variables: [],
                            constants: [Constant("valid", DecodedLiteral(1))], actions: [], invariants: [])
        _ = try valid.compile()
    }

    @Test("concrete functions and pairs preserve typed values and fail closed")
    func concreteTypedValuesFailClosed() throws {
        let function = try #require(Function<PartialFiniteDomain, Int>(formalValue: .function([
            .string("first"): .int(7)
        ])))
        #expect(function[.first] == 7)
        #expect(function[.second] == nil)
        #expect(function.tlaValue == .function([.string("first"): .int(7)]))

        let duplicateDomain = Function<DuplicateFiniteDomain, Int>()
        #expect(duplicateDomain[.first] == 0)
        #expect(duplicateDomain.sourceIssue != nil)
        #expect(Function<DuplicateFiniteDomain, Int>(formalValue: .function([
            .string("first"): .int(1)
        ])) == nil)
        #expect(Function<EmptyFiniteDomain, Int>(formalValue: .function([:])) == nil)
        #expect(Function<PartialFiniteDomain, Int>(formalValue: .function([
            .string("first"): .bool(true)
        ])) == nil)

        let pair = Pair(first: 3, second: true)
        let decoded = try #require(Pair<Int, Bool>(formalValue: .tuple([.int(3), .bool(true)])))
        #expect(decoded.first == 3)
        #expect(decoded.second)
        #expect(pair == decoded)
        #expect(Set([pair, decoded]).count == 1)
        #expect(Pair<Int, Bool>(formalValue: .tuple([.int(3)])) == nil)
        #expect(Pair<Int, Bool>(formalValue: .tuple([.bool(true), .int(3)])) == nil)
    }

    @Test("invalid typed literals and bounded sequences fail during compilation")
    func invalidTypedValuesFailDuringCompilation() throws {
        let invalidExpressions: [(StateExpr, CompilationDiagnostic.Code)] = [
            (
                Expr<Record<InvalidLiteralSchema>>(.variable("record"))[InvalidLiteralSchema.unlisted].raw,
                .invalidTypedRecordField
            ),
            (
                Record<InvalidLiteralSchema>.literal(
                    .init(InvalidLiteralSchema.count, 0),
                    .init(InvalidLiteralSchema.count, 1)
                ).raw,
                .invalidTypedRecordLiteral
            ),
            (
                Function<InvalidLiteralDomain, Int>.literal((.first, 0), (.first, 1)).raw,
                .invalidTypedFunctionLiteral
            ),
            (
                Sequences(of: Expr<SetExpr<Int>>(.variable("values")), lengths: 0...1).raw,
                .invalidSequenceElementDomain
            ),
            (
                ZeroBasedSequences(of: SetExpr<Int>.literal(1), lengths: -1...1).raw,
                .invalidSequenceLength
            ),
            (
                Function<EmptyFiniteDomain, Int>.literal((.placeholder, Expr<Int>(.value(.int(0))))).raw,
                .invalidFiniteDomain
            ),
            (
                Function<DuplicateFiniteDomain, Int>.literal((.first, 0)).raw,
                .invalidFiniteDomain
            )
        ]

        for (expression, expectedCode) in invalidExpressions {
            let specification = TLASpec(
                name: "InvalidTypedValue",
                variables: [],
                actions: [],
                invariants: [.init(name: "TypeOK", body: expression)]
            )
            do {
                _ = try specification.compile()
                Issue.record("Expected typed source validation to fail")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.code == expectedCode)
            } catch {
                Issue.record("Expected CompilationDiagnostic, got \(error)")
            }
        }

        let invalidFiniteDomainValue = TLASpec(
            name: "InvalidFiniteDomainValue",
            variables: [NamedVar(
                name: "lookup",
                initial: .function([PartialFiniteDomain.first.tlaValue: .int(0)])
            )],
            actions: [],
            invariants: [.init(
                name: "TypeOK",
                body: Expr<Function<PartialFiniteDomain, Int>>(.variable("lookup"))[.second].raw
            )]
        )
        do {
            _ = try invalidFiniteDomainValue.compile()
            Issue.record("Expected finite-domain value validation to fail")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidFiniteDomainValue)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }

    @Test("Integer ranges accept typed and literal endpoints and preserve empty ranges")
    func integerRangeEndpoints() throws {
        func range(_ lower: some TypedExpression<Int>, _ upper: some TypedExpression<Int>) -> Expr<SetExpr<Int>> {
            IntRange(lower, through: upper)
        }
        let ranges = [
            IntRange(1, through: 3),
            IntRange(Expr<Int>(1), through: 3),
            IntRange(1, through: Expr<Int>(3)),
            range(Expr<Int>(1), Expr<Int>(3))
        ]
        for expression in ranges {
            #expect(try compiledValue(expression.raw) == .set([.int(1), .int(2), .int(3)]))
        }
        #expect(try compiledValue(range(Expr<Int>(3), Expr<Int>(1)).raw) == .set([]))
    }

    @Test("typed interval, filter, map, and dynamic tuple access evaluate")
    func typedOperatorsEvaluate() throws {
        let values = IntRange(1, through: 4)
        let evenValues = values.filtering { value in value.expr % 2 == 0 }
        let squares = evenValues.mapping { value in value.expr * value.expr }
        let expanded = squares.union(SetExpr<Int>.literal(25))
        let sequence = TupleExpr<Int>.literal(3, 5, 7)

        #expect(try compiledValue(values.raw) == TLAValue.set([.int(1), .int(2), .int(3), .int(4)]))
        #expect(try compiledValue(evenValues.raw) == TLAValue.set([.int(2), .int(4)]))
        #expect(try compiledValue(squares.raw) == TLAValue.set([.int(4), .int(16)]))
        #expect(try compiledValue(expanded.raw) == TLAValue.set([.int(4), .int(16), .int(25)]))
        #expect(try compiledValue(sequence.at(Expr<Int>(.int(2))).raw) == .int(5))
    }

    @Test("source parser preserves typed collection operators")
    func parserPreservesTypedOperators() throws {
        let source = "IntRange(1, through: 4).filtering { value in value.expr % 2 == 0 }.mapping { value in value.expr * value.expr }.union(SetExpr<Int>.literal(25))"
        let syntax = try parseExpression(source)
        let parsed = SpecParser.decodeStateExpr(syntax)

        let values = IntRange(1, through: 4)
        let built = values.filtering { value in value.expr % 2 == 0 }
            .mapping { value in value.expr * value.expr }
            .union(SetExpr<Int>.literal(25))

        guard let parsed else {
            Issue.record("The typed collection expression did not parse")
            return
        }

        let parsedSpecification = canonicalTestSpec(
            variables: [],
            actions: [("evaluate", .guard_(parsed), [])],
            invariants: []
        )
        let builtSpecification = canonicalTestSpec(
            variables: [],
            actions: [("evaluate", .guard_(built.raw), [])],
            invariants: []
        )
        #expect(try parsedSpecification.compile().identity == builtSpecification.compile().identity)
    }

    @Test("typed collection operators execute in a generated machine")
    func generatedMachineUsesTypedCollectionOperators() throws {

        var machine = try TypedCollectionGeneratedModel.makeMachine()
        let transition = try machine.send(.keepEvenSquares)

        #expect(transition.before.values == [1, 2, 3, 4])
        #expect(transition.after.values == [4, 16])
        #expect(try TypedCollectionGeneratedModel.spec.compile().render().tlaBundle.tla.contains("keepEvenSquares"))
    }

    @Test("typed conditional values parse without losing their result type")
    func typedConditionalValueParses() throws {
        let source = "If(true, then: 1, else: 2)"
        let syntax = try parseExpression(source)

        #expect(
            SpecParser.decodeStateExpr(syntax)
                == .ifThenElse(.value(.bool(true)), .value(.int(1)), .value(.int(2)))
        )
    }

    @Test("formal folds evaluate, emit TLC syntax, and survive parser fidelity")
    func foldFunctionIsFormalAndRoundTrips() throws {
        let values = TupleExpr<Int>.literal(1, 2, 3)
        let built = Fold(values, startingWith: 0) { element, accumulated in
            element + accumulated
        }
        let source = "Fold(TupleExpr<Int>.literal(1, 2, 3), startingWith: 0) { element, accumulated in element + accumulated }"
        let syntax = try parseExpression(source)
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))

        #expect(try compiledValue(built.raw) == .int(6))
        #expect(try canonicalTestSpec(
            variables: [], actions: [("fold", .guard_(built.raw), [])], invariants: []
        ).compile().identity == canonicalTestSpec(
            variables: [], actions: [("fold", .guard_(parsed), [])], invariants: []
        ).compile().identity)

        let ordered = StateExpr.foldFunction(
            FormalLambda(
                parameters: ["element", "accumulated"],
                body: .subtract(.variable("element"), .variable("accumulated"))
            ),
            initial: .int(4),
            sequence: .tupleLiteral([.int(1), .int(2)])
        )
        #expect(try compiledValue(ordered) == .int(3))
    }

    @Test("generated machines preserve formal fold behavior")
    func generatedMachineUsesFormalFold() throws {
        var machine = try FoldGeneratedModel.makeMachine()
        let transition = try machine.send(.sum)
        let compilation = try FoldGeneratedModel.spec.compile()

        #expect(transition.after.total == 6)
        #expect(try compilation.render().tlaBundle.tla.contains("FoldFunction(LAMBDA"))
        #expect(try compilation.render().plusCalBundle().root.tla.contains("FoldFunction(LAMBDA"))
        #expect(try compilation.render().tlaBundle.imports.map(\.name) == ["Folds", "Functions"])
    }

    @Test("authored PlusCal folds translate into valid TLA+")
    func authoredPlusCalFoldTranslatesAndPassesSANY() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let jar = root.appendingPathComponent(".build/tla-tools/tla2tools.jar")
        let javaCandidates = [
            ProcessInfo.processInfo.environment["TLC_JAVA"],
            ProcessInfo.processInfo.environment["JAVA_HOME"].map { "\($0)/bin/java" },
            "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java",
            "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java"
        ].compactMap { $0 }
        guard let java = javaCandidates.first(where: FileManager.default.isExecutableFile(atPath:)),
              FileManager.default.fileExists(atPath: jar.path)
        else { return }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let bundle = try FoldGeneratedModel.spec.compile().render().plusCalBundle()
        for file in bundle.files {
            try file.tla.write(
                to: directory.appendingPathComponent("\(file.name).tla"),
                atomically: true,
                encoding: .utf8
            )
            if let configuration = file.cfg {
                try configuration.write(
                    to: directory.appendingPathComponent("\(file.name).cfg"),
                    atomically: true,
                    encoding: .utf8
                )
            }
        }

        func run(_ mainClass: String) throws -> (status: Int32, output: String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: java)
            process.arguments = ["-cp", jar.path, mainClass, "FoldGeneratedModel.tla"]
            process.currentDirectoryURL = directory
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            return (
                process.terminationStatus,
                String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                    ?? "<non-UTF-8 output>"
            )
        }

        let translation = try run("pcal.trans")
        #expect(translation.status == 0, "PlusCal translation failed:\n\(translation.output)")
        let sany = try run("tla2sany.SANY")
        #expect(sany.status == 0, "SANY rejected translated PlusCal:\n\(sany.output)")
    }

    @Test("the bundled KeyValueStore Util module preserves its upstream imports")
    func bundledUtilModulePassesSANY() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let jar = root.appendingPathComponent(".build/tla-tools/tla2tools.jar")
        let javaCandidates = [
            ProcessInfo.processInfo.environment["TLC_JAVA"],
            ProcessInfo.processInfo.environment["JAVA_HOME"].map { "\($0)/bin/java" },
            "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java",
            "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java"
        ].compactMap { $0 }
        guard let java = javaCandidates.first(where: FileManager.default.isExecutableFile(atPath:)),
              FileManager.default.fileExists(atPath: jar.path)
        else { return }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bundle = try KeyValueStoreUtil.module.compile().render().tlaBundle
        for file in bundle.files {
            try file.tla.write(
                to: directory.appendingPathComponent("\(file.name).tla"),
                atomically: true,
                encoding: .utf8
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: java)
        process.arguments = ["-cp", jar.path, "tla2sany.SANY", "Util.tla"]
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let text = String(
            data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ) ?? "<non-UTF-8 SANY output>"
        #expect(process.terminationStatus == 0, "SANY rejected bundled Util:\n\(text)")
        #expect(bundle.imports.map(\.name) == ["Folds", "Functions"])
    }

    @Test("bounded sequence domains and terminal predicates parse as formal expressions")
    func boundedSequencesAndFinishedParse() throws {
        let sequenceSource = "Sequences(of: SetExpr<Int>.literal(0, 1), lengths: 0...2)"
        let sequenceSyntax = try parseExpression(sequenceSource)
        let sortedSource = "SortedSequences(of: SetExpr<Int>.literal(0, 1, 2), lengths: 0...2)"
        let sortedSyntax = try parseExpression(sortedSource)
        let terminalSource = "(!Finished()) || i == f.count + 1"
        let terminalSyntax = try parseExpression(terminalSource)

        let sequences = Sequences(of: SetExpr<Int>.literal(0, 1), lengths: 0...2)
        let sortedSequences = SortedSequences(of: SetExpr<Int>.literal(0, 1, 2), lengths: 0...2)
        let parsed = try #require(SpecParser.decodeStateExpr(sequenceSyntax))
        let parsedSorted = try #require(SpecParser.decodeStateExpr(sortedSyntax))

        #expect(try compiledValue(sequences.raw) == .set([
            .tuple([]), .tuple([.int(0)]), .tuple([.int(1)]),
            .tuple([.int(0), .int(0)]), .tuple([.int(0), .int(1)]),
            .tuple([.int(1), .int(0)]), .tuple([.int(1), .int(1)])
        ]))
        #expect(parsed == sequences.raw)
        #expect(parsedSorted == sortedSequences.raw)
        #expect(try compiledValue(sortedSequences.raw) == .set([
            .tuple([]),
            .tuple([.int(0)]), .tuple([.int(1)]), .tuple([.int(2)]),
            .tuple([.int(0), .int(0)]), .tuple([.int(0), .int(1)]), .tuple([.int(0), .int(2)]),
            .tuple([.int(1), .int(1)]), .tuple([.int(1), .int(2)]), .tuple([.int(2), .int(2)])
        ]))
        #expect(SpecParser.decodeStateExpr(terminalSyntax) != nil)
    }

    @Test("zero-based sequence domains and indexed updates survive both paths")
    func zeroBasedSequencesSurviveThePipeline() throws {
        let source = "ZeroBasedSequences(of: SetExpr<Int>.literal(0, 1), lengths: 0...2)"
        let syntax = try parseExpression(source)
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))
        let sequences = ZeroBasedSequences(of: SetExpr<Int>.literal(0, 1), lengths: 0...2)

        #expect(parsed == sequences.raw)
        #expect(try compiledValue(sequences.raw) == .set([
            .function([:]),
            .function([.int(0): .int(0)]),
            .function([.int(0): .int(1)]),
            .function([.int(0): .int(0), .int(1): .int(0)]),
            .function([.int(0): .int(0), .int(1): .int(1)]),
            .function([.int(0): .int(1), .int(1): .int(0)]),
            .function([.int(0): .int(1), .int(1): .int(1)])
        ]))

        let empty = ZeroBasedSequence<Int>.literal()
        #expect(try compiledValue(empty.raw) == .function([:]))
        let emptySpec = TLASpec("EmptyZeroBasedSequence") {
            let sequence = Var<ZeroBasedSequence<Int>>("sequence")
            Variable(sequence, empty)
        }
        #expect(try emptySpec.compile().render().tlaBundle.tla.contains("[__tla_fn_0 \\in {} |-> TRUE]"))

        let input = [0: 0]
        let table = [0: -1, 1: -1, 2: -1]
        var machine = try ZeroBasedSequenceGeneratedModel.makeMachine(
            .init(input: input, table: table)
        )
        let transition = try machine.send(.writeFirst)
        let tableValue = try #require(transition.after.table[0])
        let inputValue = try #require(transition.after.input[0])
        #expect(tableValue == inputValue)
        #expect(try ZeroBasedSequenceGeneratedModel.spec.compile().render().tlaBundle.tla.contains("0.."))
    }

    @Test("non-empty subset domains parse and exclude the empty formal set")
    func nonEmptySubsetDomainsSurviveThePipeline() throws {
        let source = "NonEmptySubsets(of: SetExpr<Int>.literal(1, 2))"
        let syntax = try parseExpression(source)
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))
        let subsets = NonEmptySubsets(of: SetExpr<Int>.literal(1, 2))
        let expectedMembers: Set<TLAValue> = [
            .set([.int(1)]),
            .set([.int(2)]),
            .set([.int(1), .int(2)])
        ]

        #expect(parsed == subsets.raw)
        #expect(try compiledValue(subsets.raw) == .set(expectedMembers))

        let compilation = try NonEmptySubsetGeneratedModel.spec.compile()
        let selectedKeys = try #require(compilation.layout.testVariableID(named: "selectedKeys"))
        let initialStates = try CompiledRuntime(compilation: compilation).initialStates()
        #expect(initialStates.count == 3)
        let initialValues = try Set(initialStates.map {
            try $0.value(for: selectedKeys).rendered(using: compilation.layout)
        })
        #expect(initialValues == expectedMembers)
        #expect(try NonEmptySubsetGeneratedModel.spec.compile().render().tlaBundle.tla.contains("SUBSET"))
    }

    @Test("typed bounded quantifiers parse, evaluate, and generate")
    func typedQuantifiersSurviveThePipeline() throws {
        let hasEven = Exists(in: IntRange(1, through: 4)) { value in
            value.expr % 2 == 0
        }
        let everyPositive = ForAll(in: IntRange(1, through: 4)) { value in
            value.expr > 0
        }
        #expect(try compiledValue(hasEven.raw) == .bool(true))
        #expect(try compiledValue(everyPositive.raw) == .bool(true))

        var machine = try TypedQuantifierGeneratedModel.makeMachine()
        let transition = try machine.send(.findEven)
        #expect(transition.after.result == true)
        #expect(try TypedQuantifierGeneratedModel.spec.compile().render().tlaBundle.tla.contains("\\E"))
    }
}


private enum StringEncodedMember: String, TLAValueType {
    case first
    static var defaultValue: Self { .first }
}

private enum ModelValueEncodedMember: String, TLAValueType {
    case first
    static var defaultValue: Self { .first }
    var tlaValue: TLAValue { .constant(rawValue) }
}

extension TypedCollectionOperatorTests {
    @Test("raw enum decoding preserves its declared formal encoding")
    func enumDecodingPreservesEncoding() {
        #expect(StringEncodedMember(formalValue: .string("first")) == .first)
        #expect(StringEncodedMember(formalValue: .constant("first")) == nil)
        #expect(ModelValueEncodedMember(formalValue: .constant("first")) == .first)
        #expect(ModelValueEncodedMember(formalValue: .string("first")) == nil)
        #expect(ModelValueEncodedMember(formalValue: .constant("missing")) == nil)
        #expect(ModelValueEncodedMember(formalValue: .int(1)) == nil)
    }
}
