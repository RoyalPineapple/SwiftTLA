@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax
import Testing
import Foundation

private func parseExpression(_ source: String) throws -> ExprSyntax {
    try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
}

private enum CollectionStep: String, CaseIterable {
    case keepEvenSquares
    case findEven
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

    static let fieldNames: Set<String> = ["count", "enabled"]
    static let defaultRecord: TLAValue = .record(["count": .int(0), "enabled": .bool(false)])

    static func fieldName<Value>(for field: KeyPath<InvalidLiteralFields, Value>) -> String? {
        let key = field as AnyKeyPath
        if key == \InvalidLiteralFields.count { return "count" }
        if key == \InvalidLiteralFields.enabled { return "enabled" }
        return nil
    }

    static let count = field(\InvalidLiteralFields.count)
    static let enabled = field(\InvalidLiteralFields.enabled)
    static let unlisted = field(\InvalidLiteralFields.unlisted)
}

private enum InvalidDefaultRecordSchema: TLARecordSchema {
    typealias Fields = InvalidLiteralFields

    static let fieldNames: Set<String> = ["count", "enabled"]
    static let defaultRecord: TLAValue = .record(["count": .int(0)])

    static func fieldName<Value>(for field: KeyPath<InvalidLiteralFields, Value>) -> String? {
        let key = field as AnyKeyPath
        if key == \InvalidLiteralFields.count { return "count" }
        if key == \InvalidLiteralFields.enabled { return "enabled" }
        return nil
    }
}

@TLAModel
private struct TypedCollectionGeneratedModel {
    static var spec: TLASpec {
        #spec("TypedCollectionGeneratedModel") { scope in
            Algorithm("TypedCollectionGeneratedModel", scoped: { algorithm in
                let values = algorithm.sharedVar("values", initial: IntRange(1, through: 4))
                Do(CollectionStep.keepEvenSquares) {
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
    static var spec: TLASpec {
        #spec("TypedQuantifierGeneratedModel") { scope in
            Algorithm("TypedQuantifierGeneratedModel", scoped: { algorithm in
                let result = algorithm.sharedVar("result", initial: false)
                Do(CollectionStep.findEven) {
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
    static var spec: TLASpec {
        #spec("NonEmptySubsetGeneratedModel") {
            Algorithm("NonEmptySubsetGeneratedModel", scoped: { scope in
                let selectedKeys = scope.sharedVar("selectedKeys", in: NonEmptySubsets(
                    of: SetExpr<Int>.literal(1, 2)
                ))
                Do(TestControlLabel.keep) { Assign(selectedKeys, to: selectedKeys.expr) }
            })
        }
    }
}

@TLAModel
private struct ZeroBasedSequenceGeneratedModel {
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

                Do(TestControlLabel.writeFirst) {
                    Assign(table, to: table.updating(0, to: input[0]))
                }
            })
        }
    }
}

@TLAModel
private struct FoldGeneratedModel {
    static var spec: TLASpec {
        #spec("FoldGeneratedModel") {
            Import(FunctionsModule.module)
            Algorithm("FoldGeneratedModel", scoped: { scope in
                let values = scope.sharedVar("values", initial: TupleExpr<Int>.literal(1, 2, 3))
                let total = scope.sharedVar("total", initial: 0)
                Do(TestControlLabel.sum) {
                    Assign(total, to: Fold(values.expr, startingWith: 0) { element, accumulated in
                        element + accumulated
                    })
                }
            })
        }
    }
}

@Suite(.serialized) struct TypedCollectionOperatorTests {
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
                Expr<Record<InvalidDefaultRecordSchema>>(Record()).raw,
                .invalidTypedRecordLiteral
            ),
            (
                Function<InvalidLiteralDomain, Int>.literal((.first, 0), (.first, 1)).raw,
                .invalidTypedFunctionLiteral
            ),
            (
                Select(from: SetExpr<Int>.literal(1), matching: { _ in .value(.bool(false)) }).raw,
                .invalidStaticSelection
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
        let runtime = values.filtering { value in value.expr % 2 == 0 }
            .mapping { value in value.expr * value.expr }
            .union(SetExpr<Int>.literal(25))

        guard let parsed else {
            Issue.record("The typed collection expression did not parse")
            return
        }

        let parsedModel = canonicalTestSpec(
            variables: [],
            actions: [("evaluate", .guard_(parsed), [])],
            invariants: []
        )
        let runtimeModel = canonicalTestSpec(
            variables: [],
            actions: [("evaluate", .guard_(runtime.raw), [])],
            invariants: []
        )
        #expect(try parsedModel.compile().identity == runtimeModel.compile().identity)
    }

    @Test("typed collection operators execute in a generated model")
    func generatedMachineUsesTypedCollectionOperators() throws {

        var model = try TypedCollectionGeneratedModel.makeMachine()
        let result = try model.send(.keepEvenSquares)

        #expect(Set(result.before.values.elements) == Set([1, 2, 3, 4]))
        #expect(Set(result.after.values.elements) == Set([4, 16]))
        #expect(try TypedCollectionGeneratedModel.spec.compile().renderedTLAModuleBundle().tla.contains("keepEvenSquares"))
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
        let runtime = Fold(values, startingWith: 0) { element, accumulated in
            element + accumulated
        }
        let source = "Fold(TupleExpr<Int>.literal(1, 2, 3), startingWith: 0) { element, accumulated in element + accumulated }"
        let syntax = try parseExpression(source)
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))

        #expect(try compiledValue(runtime.raw) == .int(6))
        #expect(runtime.raw.description.contains("FoldFunction(LAMBDA"))
        #expect(try canonicalTestSpec(
            variables: [], actions: [("fold", .guard_(runtime.raw), [])], invariants: []
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
        var model = try FoldGeneratedModel.makeMachine()
        let result = try model.send(.sum)
        let compilation = try FoldGeneratedModel.spec.compile()

        #expect(result.after.total == 6)
        #expect(compilation.renderedTLAModuleBundle().tla.contains("FoldFunction(LAMBDA"))
        #expect(try compilation.renderedPlusCalBundle().root.tla.contains("FoldFunction(LAMBDA"))
        #expect(compilation.renderedTLAModuleBundle().imports.map(\.name) == ["Folds", "Functions"])
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
        let bundle = try FoldGeneratedModel.spec.compile().renderedPlusCalBundle()
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
        try KeyValueStoreUtil.module.compile().materializeModuleBundle(to: directory)

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
        #expect(try KeyValueStoreUtil.module.compile().renderedTLAModuleBundle().imports.map(\.name) == ["Folds", "Functions"])
    }

    @Test("bounded sequence domains and terminal predicates parse as formal expressions")
    func boundedSequencesAndFinishedParse() throws {
        let sequenceSource = "Sequences(of: SetExpr<Int>.literal(0, 1), lengths: 0...2)"
        let sequenceSyntax = try parseExpression(sequenceSource)
        let sortedSource = "SortedSequences(of: SetExpr<Int>.literal(0, 1, 2), lengths: 0...2)"
        let sortedSyntax = try parseExpression(sortedSource)
        let terminalSource = "(!Finished()) || i == f.count + 1"
        let terminalSyntax = try parseExpression(terminalSource)

        let runtime = Sequences(of: SetExpr<Int>.literal(0, 1), lengths: 0...2)
        let sortedRuntime = SortedSequences(of: SetExpr<Int>.literal(0, 1, 2), lengths: 0...2)
        let parsed = try #require(SpecParser.decodeStateExpr(sequenceSyntax))
        let parsedSorted = try #require(SpecParser.decodeStateExpr(sortedSyntax))

        #expect(try compiledValue(runtime.raw) == .set([
            .tuple([]), .tuple([.int(0)]), .tuple([.int(1)]),
            .tuple([.int(0), .int(0)]), .tuple([.int(0), .int(1)]),
            .tuple([.int(1), .int(0)]), .tuple([.int(1), .int(1)])
        ]))
        #expect(parsed == runtime.raw)
        #expect(parsedSorted == sortedRuntime.raw)
        #expect(try compiledValue(sortedRuntime.raw) == .set([
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
        let syntax = try parseExpression(source)
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))
        let runtime = ZeroBasedSequences(of: SetExpr<Int>.literal(0, 1), lengths: 1...2)

        #expect(parsed == runtime.raw)
        #expect(try compiledValue(runtime.raw) == .set([
            .function([.int(0): .int(0)]),
            .function([.int(0): .int(1)]),
            .function([.int(0): .int(0), .int(1): .int(0)]),
            .function([.int(0): .int(0), .int(1): .int(1)]),
            .function([.int(0): .int(1), .int(1): .int(0)]),
            .function([.int(0): .int(1), .int(1): .int(1)])
        ]))

        let input = try #require(ZeroBasedSequence<Int>(formalValue: .function([
            .int(0): .int(0)
        ])))
        let table = try #require(ZeroBasedSequence<Int>(formalValue: .function([
            .int(0): .int(-1),
            .int(1): .int(-1),
            .int(2): .int(-1)
        ])))
        var model = try ZeroBasedSequenceGeneratedModel.makeMachine(
            .init(input: input, table: table)
        )
        let result = try model.send(.writeFirst)
        let tableValue = try #require(result.after.table.element(at: 0))
        let inputValue = try #require(result.after.input.element(at: 0))
        #expect(tableValue == inputValue)
        #expect(try ZeroBasedSequenceGeneratedModel.spec.compile().renderedTLAModuleBundle().tla.contains("0.."))
    }

    @Test("non-empty subset domains parse and exclude the empty formal set")
    func nonEmptySubsetDomainsSurviveThePipeline() throws {
        let source = "NonEmptySubsets(of: SetExpr<Int>.literal(1, 2))"
        let syntax = try parseExpression(source)
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))
        let runtime = NonEmptySubsets(of: SetExpr<Int>.literal(1, 2))
        let expectedMembers: Set<TLAValue> = [
            .set([.int(1)]),
            .set([.int(2)]),
            .set([.int(1), .int(2)])
        ]

        #expect(parsed == runtime.raw)
        #expect(try compiledValue(runtime.raw) == .set(expectedMembers))

        let compilation = try NonEmptySubsetGeneratedModel.spec.compile()
        let selectedKeys = try #require(compilation.layout.variableID(named: "selectedKeys"))
        let initialStates = try CompiledRuntime(compilation: compilation).initialStates()
        #expect(initialStates.count == 3)
        let initialValues = try Set(initialStates.map {
            try $0.value(for: selectedKeys).rendered(using: compilation.layout)
        })
        #expect(initialValues == expectedMembers)
        #expect(try NonEmptySubsetGeneratedModel.spec.compile().renderedTLAModuleBundle().tla.contains("SUBSET"))
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

        var model = try TypedQuantifierGeneratedModel.makeMachine()
        let result = try model.send(.findEven)
        #expect(result.after.result == true)
        #expect(try TypedQuantifierGeneratedModel.spec.compile().renderedTLAModuleBundle().tla.contains("\\E"))
    }
}
