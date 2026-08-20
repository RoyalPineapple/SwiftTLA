@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax
import Testing
import Foundation

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

@TLAModel
private struct FoldGeneratedModel {
    static var spec: TLASpec {
        #spec("FoldGeneratedModel") {
            Import(FunctionsModule.module)
            Algorithm("FoldGeneratedModel") {
                let values = SharedVar(initial: TupleExpr<Int>.literal(1, 2, 3))
                let total = SharedVar(initial: 0)
                Do("sum") {
                    Assign(total, to: Fold(values.expr, startingWith: 0) { element, accumulated in
                        element + accumulated
                    })
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
        #expect(_tlaAlphaEquivalent(parsedModel, runtimeModel))
    }

    @Test("typed collection operators execute in a generated model")
    func generatedMachineUsesTypedCollectionOperators() throws {
        TypedCollectionGeneratedModel._checkParserTree()

        var model = try TypedCollectionGeneratedModel.makeMachine()
        let result = try model.apply(.keepEvenSquares)

        #expect(Set(result.before.values.elements) == Set([1, 2, 3, 4]))
        #expect(Set(result.after.values.elements) == Set([4, 16]))
        #expect(try TypedCollectionGeneratedModel.spec.compile().renderedTLAModuleBundle().tla.contains("keepEvenSquares"))
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

    @Test("formal folds evaluate, emit TLC syntax, and survive parser fidelity")
    func foldFunctionIsFormalAndRoundTrips() throws {
        let values = TupleExpr<Int>.literal(1, 2, 3)
        let runtime = Fold(values, startingWith: 0) { element, accumulated in
            element + accumulated
        }
        let source = "Fold(TupleExpr<Int>.literal(1, 2, 3), startingWith: 0) { element, accumulated in element + accumulated }"
        let syntax = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
        let parsed = try #require(SpecParser.decodeStateExpr(syntax))

        #expect(try runtime.raw.evaluate(in: [:]) == .int(6))
        #expect(runtime.raw.description.contains("FoldFunction(LAMBDA"))
        #expect(_tlaAlphaEquivalent(
            canonicalTestSpec(variables: [], actions: [("fold", .guard_(runtime.raw), [])], invariants: []),
            canonicalTestSpec(variables: [], actions: [("fold", .guard_(parsed), [])], invariants: [])
        ))

        let ordered = StateExpr.foldFunction(
            FormalLambda(
                parameters: ["element", "accumulated"],
                body: .subtract(.variable("element"), .variable("accumulated"))
            ),
            initial: .int(4),
            sequence: .tupleLiteral([.int(1), .int(2)])
        )
        #expect(try ordered.evaluate(in: [:]) == .int(3))
    }

    @Test("generated machines preserve formal fold behavior")
    func generatedMachineUsesFormalFold() throws {
        FoldGeneratedModel._checkParserTree()
        var model = try FoldGeneratedModel.makeMachine()
        let result = try model.apply(.sum)

        #expect(result.after.total == 6)
        #expect(try FoldGeneratedModel.spec.compile().renderedTLAModuleBundle().tla.contains("FoldFunction(LAMBDA"))
        #expect(try FoldGeneratedModel.spec.compile().renderedTLAModuleBundle().imports.map(\.name) == ["Folds", "Functions"])
    }

    @Test("the bundled Functions module makes FoldFunction valid TLA+ source")
    func bundledFunctionsModulePassesSANY() throws {
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
        try FoldGeneratedModel.spec.compile().materializeModuleBundle(to: directory)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: java)
        process.arguments = ["-cp", jar.path, "tla2sany.SANY", "FoldGeneratedModel.tla"]
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let text = String(
            data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
        ) ?? "<non-UTF-8 SANY output>"
        #expect(process.terminationStatus == 0, "SANY rejected bundled Functions:\n\(text)")
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
        var model = try ZeroBasedSequenceGeneratedModel.makeMachine()
        let result = try model.apply(.writeFirst)
        #expect(result.after.table[0] == result.after.input[0])
        #expect(try ZeroBasedSequenceGeneratedModel.spec.compile().renderedTLAModuleBundle().tla.contains("0.."))
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
        let initialStates = try computeInitialStates(NonEmptySubsetGeneratedModel.spec)
        #expect(initialStates.count == 3)
        let representative = NonEmptySubsetGeneratedModel.spec.variables.first?.initial
        #expect(initialStates.contains { $0["selectedKeys"] == representative })
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
        #expect(try hasEven.raw.evaluate(in: [:]) == .bool(true))
        #expect(try everyPositive.raw.evaluate(in: [:]) == .bool(true))

        TypedQuantifierGeneratedModel._checkParserTree()
        var model = try TypedQuantifierGeneratedModel.makeMachine()
        let result = try model.apply(.findEven)
        #expect(result.after.result == true)
        #expect(try TypedQuantifierGeneratedModel.spec.compile().renderedTLAModuleBundle().tla.contains("\\E"))
    }
}
