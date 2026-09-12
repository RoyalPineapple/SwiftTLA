import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import SwiftTLAPlugin
import Testing
@testable import SwiftTLA

@Suite struct NativeTypeDiagnosticTests {
    @Test("Explicit operator signatures reject incompatible unused arguments", arguments: ["false", "SetExpr<Int>.literal(1)"])
    func operatorSignaturesConstrainArguments(_ argument: String) throws {
        let source = ExprSyntax(stringLiteral: """
        {
            FormalDefinition("Accept", taking: Int.self) { unused in true }
            Invariant("Result") { FormalCall(as: Bool.self, "Accept", \(argument)) }
        }
        """)
        let closure = try #require(source.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "Signature", closure)
        #expect(parsed.diagnostics.isEmpty)
        let compilation = try parsed.compile()
        #expect(throws: CompilationDiagnostic.self) {
            try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        }
    }

    @Test("Operator signatures supply empty collection argument types")
    func operatorSignaturesProvideContext() throws {
        let specification = TLASpec("SignatureContext") {
            FormalDefinition("Accept", taking: SetExpr<Int>.self) { _ in true }
            Invariant("Result") {
                StateExpr.operatorApplication(.reference("Accept", arity: 1), [.value(.setLiteral([]))])
            }
        }
        let compilation = try specification.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let function = try #require(program.functions.first)
        #expect(function.parameters.map(\.type) == [.set(.int)])
    }

    @Test("Checked higher-order calls release their input and lexical checking scopes")
    func checkedProgramReleasesInputs() throws {
        let application = StateExpr.operatorApplication(.reference("Apply", arity: 2), [
            .operator(.reference("Increment", arity: 1)), .value(.int(0))
        ])
        let specification = TLASpec("CheckedCallOwnership") {
            FormalDefinition("Increment", parameters: [.value("value")],
                body: .add(.variable("value"), .int(1)))
            FormalDefinition("Apply", parameters: [.operator("operation", arity: 1), .value("argument")],
                body: .operatorApplication(.reference("operation", arity: 1), [.value(.variable("argument"))]))
            Invariant("Result") { StateExpr.equal(application, .int(1)) }
        }
        let compilation = try specification.compile()
        weak var previousInputs: CompiledTypeInputs?
        let checked = try { () throws -> CompiledProgram in
            let inputs = try SourceTypeResolver().resolve(in: compilation)
            previousInputs = inputs
            var checker = try CompiledTypeChecker(inputs: inputs)
            return try checker.checkProgram()
        }()
        withExtendedLifetime(checked) {
            #expect(previousInputs == nil)
            #expect(checked.behavior.invariants.count == 1)
        }
    }

    @Test("Variable annotations provide enum context before initialization", arguments: [
        #"let table = Var<Function<Key, Entry>>("table")"#,
        #"let table: Var<Function<Key, Entry>> = Var("table")"#
    ])
    func declarationsProvideContext(_ declaration: String) throws {
        let parser = ParserSession(sourceTypes: .init(enums: [
            .init(typeName: "Key", cases: [("first", .string("key-first"))], isFiniteDomain: true),
            .init(typeName: "Entry", cases: [("first", .string("entry-first"))], isFiniteDomain: true)
        ]))
        let source = """
        {
            \(declaration)
            Invariant("Selected") { table[.first] == .first }
            Variable(table, Function<Key, Entry>.literal((Key.first, Entry.first)))
        }
        """
        let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = parser.parseSpecClosure(named: "DeclaredContext", closure)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let invariant = try #require(parsed.invariants.first)
        #expect(invariant.body == .equal(
            .functionApply(.variable("table"), .value(.string("key-first"))),
            .value(.string("entry-first"))))
        _ = try parsed.compile()
    }

    @Test("Bindings in one declaration receive earlier variable types")
    func declarationBindingsResolveInSourceOrder() throws {
        let parser = ParserSession(sourceTypes: .init(enums: [
            .init(typeName: "Key", cases: [("first", .string("key-first"))], isFiniteDomain: true),
            .init(typeName: "Entry", cases: [("first", .string("entry-first"))], isFiniteDomain: true)
        ]))
        let source = """
        {
            let table = Var<Function<Key, Entry>>("table"),
                selected = If(true, then: table[.first], else: Entry.first)
            Variable(table, Function<Key, Entry>.literal((Key.first, Entry.first)))
            Invariant("Selected") { selected == Entry.first }
        }
        """
        let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = parser.parseSpecClosure(named: "BindingOrder", closure)
        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let invariant = try #require(parsed.invariants.first)
        #expect(invariant.body == .equal(
            .ifThenElse(.value(.bool(true)),
                .functionApply(.variable("table"), .value(.string("key-first"))),
                .value(.string("entry-first"))),
            .value(.string("entry-first"))))
        _ = try parsed.compile()
    }

    @Test("Typed collection constructors consume their supplied syntax")
    func collectionConstructorsRejectUnusedSyntax() {
        let parser = ParserSession()
        #expect(parser.decodeStateExpr(ExprSyntax("TupleExpr<Int>()")) == .value(.tuple([])))
        #expect(parser.decodeStateExpr(ExprSyntax("SetExpr<Int>(1, 2)")) == .value(.set([.int(1), .int(2)])))
        for source in [
            "TupleExpr<Int>(1)", "TupleExpr<Int>() { 1 }",
            "SetExpr<Int>(ignored: 1)", "SetExpr<Int>(1) { 2 }"
        ] {
            #expect(parser.decodeStateExpr(ExprSyntax(stringLiteral: source)) == nil, "\(source)")
        }
    }

    @Test("A declaration's enum type rejects a case from another enum")
    func declarationsRejectWrongEnumCases() throws {
        let parser = ParserSession(sourceTypes: .init(enums: [
            .init(typeName: "Key", cases: [("first", .string("key-first"))], isFiniteDomain: true),
            .init(typeName: "Entry", cases: [("second", .string("entry-second"))], isFiniteDomain: true)
        ]))
        let source = """
        {
            Algorithm("WrongInitialType", scoped: { scope in
                let key: SharedVariable<Key> = scope.sharedVar("key", initial: .second)
            })
        }
        """
        let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = parser.parseSpecClosure(named: "WrongInitialType", closure)
        #expect(!parsed.diagnostics.isEmpty)
        #expect(throws: SourceParseDiagnostic.self) { try parsed.compile() }
    }

    @Test("Collection arguments use their declared enum types when case names overlap")
    func collectionArgumentsUseDeclaredTypes() throws {
        let parser = ParserSession(sourceTypes: .init(enums: [
            .init(typeName: "Key", cases: [("first", .string("key-first"))], isFiniteDomain: true),
            .init(typeName: "Entry", cases: [("first", .string("entry-first")), ("second", .string("entry-second"))], isFiniteDomain: true)
        ]))
        let table = StateExpr.variable("table")
        let key = StateExpr.value(.string("key-first"))
        let first = StateExpr.value(.string("entry-first"))
        let second = StateExpr.value(.string("entry-second"))
        let members = StateExpr.variable("members")
        let sequence = StateExpr.variable("sequence")
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "table", to: table,
            shape: .dictionary(.named("Key"), .named("Entry")))
            .extending(binding: "members", to: members, shape: .set(.named("Entry")))
            .extending(binding: "sequence", to: sequence, shape: .array(.named("Entry")))
        let selected = StateExpr.functionApply(table, key)
        let cases: [(String, StateExpr)] = [
            ("table[.first]", selected),
            ("table.updating(.first, to: .second)", .except(table, key, second)),
            ("table.updating(.first, to: .second)[.first]", .functionApply(.except(table, key, second), key)),
            ("table.updating(.first) { current in If(current == .first, then: .second, else: current) }",
             .except(table, key, .ifThenElse(.equal(selected, first), second, selected))),
            ("table.overriding(.first, with: .second)", .partialFunctionOverriding(table, key: key, value: second)),
            ("table.overriding(.first, with: .second)[.first]",
             .functionApply(.partialFunctionOverriding(table, key: key, value: second), key)),
            ("members.contains(.first)", .in(first, members)),
            ("members.inserting(.first)", .union(members, .setLiteral([first]))),
            ("members.removing(.first)", .setDifference(members, .setLiteral([first]))),
            ("sequence.appending(.first)", .tupleAppend(sequence, first))
        ]
        for (source, expected) in cases {
            #expect(parser.decodeTypedFacadeValue(ExprSyntax(stringLiteral: source), scope: scope) == expected, "\(source)")
        }
        for source in [
            "table[.second]", "table.updating(.second, to: .first)",
            #"StateExpr.operatorApplication(.reference("Identity", arity: 1), [.value(table[.second])])"#,
            #"SwiftTLA.StateExpr.operatorApplication(.reference("Identity", arity: 1), [.value(table[.second])])"#
        ] {
            #expect(parser.decodeTypedFacadeValue(ExprSyntax(stringLiteral: source), scope: scope) == nil)
        }
    }

    @Test("Finite-domain quantifiers preserve enum context and captured completion targets")
    func quantifiersPreserveTypedScope() throws {
        let parser = ParserSession(sourceTypes: .init(enums: [
            .init(typeName: "Choice", cases: [("one", .int(1)), ("two", .int(2))], isFiniteDomain: true)
        ]))
        let source: ExprSyntax = "ForAll(Choice.all) { choice in choice.expr == .one }"
        let domain = StateExpr.setLiteral([.int(1), .int(2)])
        #expect(parser.decodeTypedFacadeValue(source, scope: .empty) == .forAll(
            domain, "choice", .equal(.variable("choice"), .int(1))))
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "other", to: .variable("target"))
        let finished: ExprSyntax = "ForAll(Choice.all) { choice in Finished(other) }"
        #expect(parser.decodeTypedFacadeValue(finished, scope: scope) == .forAll(
            domain, "choice", .equal(.functionApply(.programCounter, .variable("target")), .controlLocation(.done))))
    }

    @Test("Finite sequence domains preserve contextual enum elements", arguments: [false, true])
    func sequenceDomainsPreserveEnumElements(_ zeroBased: Bool) throws {
        let parser = ParserSession(sourceTypes: .init(enums: [
            .init(typeName: "Choice", cases: [("one", .int(1)), ("two", .int(2))], isFiniteDomain: true)
        ]))
        let constructor = zeroBased ? "ZeroBasedSequences" : "Sequences"
        let selection = zeroBased ? "sequence.expr[0]" : "sequence.expr.head()"
        let source = ExprSyntax(stringLiteral:
            "ForAll(in: \(constructor)(of: Choice.all, lengths: 1...1)) { sequence in \(selection) == .one }")
        let decoded = try #require(parser.decodeTypedFacadeValue(source, scope: .empty))
        guard case .forAll(_, let binder, let predicate) = decoded else {
            Issue.record("Expected a quantified sequence predicate")
            return
        }
        let selected: StateExpr = zeroBased
            ? .functionApply(.variable(binder), .int(0))
            : .tupleHead(.variable(binder))
        #expect(predicate == .equal(selected, .int(1)))
    }

    @Test("Set operations preserve nested element shapes", arguments: ["union", "intersection", "subtracting"])
    func setOperationsPreserveElementShapes(_ operation: String) throws {
        let parser = ParserSession()
        let shape = CompiledValueType.set(.array(.int))
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "rows", to: .variable("stored"), shape: shape)
        let source = ExprSyntax(stringLiteral: "rows.\(operation)(rows)")
        #expect(parser.typedFacadeValueType(source, scope: scope) == shape)
        let predicate = ExprSyntax(stringLiteral: "rows.\(operation)(rows).filtering { row in row.expr.count > 0 }")
        #expect(parser.decodeTypedFacadeValue(predicate, scope: scope) != nil)
    }

    @Test("Collection closures retain nested element shapes")
    func collectionClosuresPreserveElementShapes() throws {
        let parser = ParserSession()
        let rows = StateExpr.variable("storedRows")
        let row = StateExpr.variable("row")
        let predicate = StateExpr.greaterThan(.tupleLength(row), .int(0))
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "rows", to: rows, shape: .set(.array(.int)))
        let filtering: ExprSyntax = "rows.filtering { row in row.expr.count > 0 }"
        #expect(parser.decodeTypedFacadeValue(filtering, scope: scope) == .setFilter(rows, "row", predicate))
        let mapping: ExprSyntax = "rows.mapping { row in row.expr.count }"
        #expect(parser.decodeTypedFacadeValue(mapping, scope: scope) == .setMap(.tupleLength(row), "row", rows))
        let chained: ExprSyntax = "rows.mapping { row in row.expr }.filtering { row in row.expr.count > 0 }"
        #expect(parser.decodeTypedFacadeValue(chained, scope: scope) == .setFilter(.setMap(row, "row", rows), "row", predicate))
        let sequenceScope = ParserSession.TypedFacadeScope.empty.extending(binding: "rows", to: rows, shape: .array(.array(.int)))
        let selecting: ExprSyntax = "rows.selecting { row in row.expr.count > 0 }"
        #expect(parser.decodeTypedFacadeValue(selecting, scope: sequenceScope) == .sequenceSelect(rows, "row", predicate))
    }

    @Test("Nested sequence access retains the selected element shape", arguments: [
        ("matrix[1].count", StateExpr.tupleDynamicAccess(.variable("stored"), .int(1))),
        ("matrix.at(1).count", StateExpr.tupleAccess(.variable("stored"), 1)),
        ("matrix.head().count", StateExpr.tupleHead(.variable("stored")))
    ])
    func nestedSequenceAccessPreservesShape(_ source: String, _ selected: StateExpr) throws {
        let parser = ParserSession(sourceTypes: .init(aliases: ["Matrix": "TupleExpr<TupleExpr<Int>>"]))
        let type: TypeSyntax = "Matrix"
        let shape = parser.typedFacadeValueType(type)
        #expect(shape == .array(.array(.int)))
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "matrix", to: .variable("stored"), shape: shape)
        #expect(parser.decodeTypedFacadeValue(ExprSyntax(stringLiteral: source), scope: scope) == .tupleLength(selected))
    }

    @Test("Parsing and type resolution share aliased collection shapes")
    func aliasesPreserveParsingSemantics() throws {
        let parser = ParserSession(sourceTypes: .init(aliases: [
            "Board": "TupleExpr<Int>",
            "Boards": "SetExpr<Board>",
            "Table": "Function<Int, Boards>",
            "Offsets": "ZeroBasedSequence<Int>"
        ]))
        let board: TypeSyntax = "Board"
        let table: TypeSyntax = "Table"
        let offsets: TypeSyntax = "Offsets"
        #expect(parser.typedFacadeValueType(board) == .array(.int))
        #expect(parser.typedFacadeValueType(table) == .dictionary(.int, .set(.array(.int))))
        #expect(parser.typedFacadeValueType(table) == (try parser.sourceTypeResolver.resolve(table)))
        #expect(parser.typedFacadeValueType(offsets) == .dictionary(.int, .int))
        #expect(try parser.sourceTypeResolver.resolve("Table") == .dictionary(.int, .set(.array(.int))))
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "board", to: .variable("stored"),
            shape: parser.typedFacadeValueType(board))
        #expect(parser.decodeTypedFacadeValue(ExprSyntax("board.count"), scope: scope) == .tupleLength(.variable("stored")))
    }

    @Test("mutually recursive local operators share transitive lexical captures")
    func recursiveLocalCaptures() throws {
        let body = StateExpr.letValue("offset", .int(2), .letIn([
            LocalOperator("First", parameters: ["n"], body: .recursiveCall("Second", [.variable("n")])),
            LocalOperator("Second", parameters: ["n"], body: .ifThenElse(
                .equal(.variable("n"), .int(0)),
                .variable("offset"),
                .recursiveCall("First", [.subtract(.variable("n"), .int(1))])
            ))
        ], .recursiveCall("First", [.int(1)])))
        let specification = TLASpec("RecursiveCaptures") {
            FormalDefinition("Answer", parameters: [], body: body)
        }
        let compilation = try specification.compile()
        let moduleOperators = Set(compilation.semantics.operators.formalDefinitionIDs)
        let declarations = compilation.semantics.operators.definitions.values.filter { !moduleOperators.contains($0.id) }
        #expect(declarations.count == 2)
        let directCaptures = declarations.reduce(into: Set<BinderID>()) {
            $0.formUnion($1.capturedBindings)
        }
        #expect(directCaptures.count == 1)
        let recursiveOperators = Set(declarations.map(\.id))
        for declaration in declarations {
            let dependencies = try #require(compilation.semantics.operators.dependencies[declaration.id])
            #expect(dependencies.bindings == directCaptures)
            #expect(dependencies.operators == recursiveOperators)
        }
        let inputs = try SourceTypeResolver().resolve(in: compilation)
        let checker = try CompiledTypeChecker(inputs: inputs)
        let definitionID = try #require(compilation.semantics.operators.formalDefinitionIDs.first)
        let definition = try #require(compilation.semantics.operators[definitionID])
        #expect(try checker.resolutionScope(definition.body, expected: .int).resultType == .int)
    }

    @Test("Temporal predicates retain Boolean types and resolved operands", arguments: [
        TemporalExpr.always(.equal(.variable("count"), .value(.int(0)))),
        .eventually(.equal(.variable("count"), .value(.int(0)))),
        .alwaysEventually(.equal(.variable("count"), .value(.int(0)))),
        .eventuallyAlways(.equal(.variable("count"), .value(.int(0)))),
        .leadsTo(.equal(.variable("count"), .value(.int(0))), .value(.bool(true)))
    ])
    func resolvedTemporalPredicates(_ property: TemporalExpr) throws {
        let specification = TLASpec(name: "TemporalTypes", variables: [
            .init(name: "count", initial: .int(0))
        ], actions: [], invariants: [], temporalProperties: [.init(name: "Progress", expr: property)])
        let compilation = try specification.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let declaration = try #require(compilation.semantics.behavior.temporalProperties.first)
        let propertyDeclaration = try #require(program.behavior.temporalProperties.first { $0.id == declaration.id })
        let resolved = propertyDeclaration.expression
        var predicates: [CompiledExpression] = []
        _ = resolved.map { predicates.append($0.expression) }
        #expect(!predicates.isEmpty)
        for predicate in predicates {
            #expect(predicate.resultType == .bool)
        }
        let comparison = try #require(predicates.first)
        #expect(comparison.children.map(\.resultType) == [.int, .int])
        switch (property, resolved) {
        case (.always, .always), (.eventually, .eventually),
             (.alwaysEventually, .alwaysEventually), (.eventuallyAlways, .eventuallyAlways):
            #expect(predicates.count == 1)
        case (.leadsTo, .leadsTo):
            #expect(predicates.count == 2)
            #expect(predicates[1].operation == .value(.boolean(true)))
        default:
            Issue.record("Resolution changed the temporal operator")
        }
    }

    @Test("Temporal predicate type errors identify the property", arguments: [
        TemporalExpr.always(.value(.int(1))),
        .eventually(.value(.int(1))),
        .alwaysEventually(.value(.int(1))),
        .eventuallyAlways(.value(.int(1))),
        .leadsTo(.value(.int(1)), .value(.bool(true))),
        .leadsTo(.value(.bool(true)), .value(.int(1)))
    ])
    func temporalPredicateDiagnostics(_ property: TemporalExpr) throws {
        let specification = TLASpec(name: "InvalidTemporalType", variables: [], actions: [], invariants: [],
            temporalProperties: [.init(name: "Progress", expr: property)])
        let compilation = try specification.compile()
        do {
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
            Issue.record("A temporal predicate must be Boolean")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.contains("temporalProperties.Progress"))
        }
    }

    @Test("Conversion planning retains successful components of a rejected composite")
    func conversionComponentsAreRecordedTogether() throws {
        let types = try CompiledTypeContext(enums: .init(), formalNames: [:])
        let finite = CompiledValueType.finite([.integer(1)])
        let source = CompiledValueType.tuple([.set(.bool), .set(finite)])
        let target = CompiledValueType.tuple([.set(.int), .set(.int)])
        var checks: [ResolvedProjectionPair: Bool] = [:]
        #expect(!types.canProjectRead(source, to: target, checks: &checks))
        #expect(checks[.init(source: .bool, target: .int)] == false)
        #expect(checks[.init(source: finite, target: .int)] == true)
        #expect(checks[.init(source: .set(finite), target: .set(.int))] == true)
        let firstPass = checks
        #expect(!types.canProjectRead(source, to: target, checks: &checks))
        #expect(checks == firstPass)
    }

    @Test("Source type syntax preserves nested collections and module qualification")
    func sourceTypeSyntaxUsesSwiftGrammar() throws {
        let resolver = SourceTypeResolver(metadata: .init())
        #expect(try resolver.resolve("Set < [String: Array < Int >] >") == .set(.dictionary(.string, .array(.int))))
        #expect(try resolver.resolve("Swift.Array<Swift.Int>") == .array(.int))
        #expect(try resolver.resolve("SwiftTLA.SetExpr<Swift.Int>") == .set(.int))
        let type: TypeSyntax = "Set<[String: Array<Int>]>"
        let spelling = try #require(ParserSession.sourceTypeSpelling(type))
        #expect(try resolver.resolve(spelling) == .set(.dictionary(.string, .array(.int))))
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("Int?") }
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("(Int, Bool)") }
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("Set<Int") }
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("[Int: Bool: String]") }
    }

    @Test("Known type constructors reject missing and excess generic arguments", arguments: [
        "Set", "SetExpr<Int, Bool>", "Array<Int, Bool>", "Swift.Dictionary<Int>",
        "Function<Int>", "PartialFunction<Int>", "Pair<Int>", "Record<Int, Bool>",
        "OneOf<Int>", "ZeroBasedSequence<Int, Bool>", "Int<Bool>"
    ])
    func typeConstructorRequiresItsDeclaredArity(_ source: String) throws {
        let resolver = SourceTypeResolver()
        do {
            _ = try resolver.resolve(source)
            Issue.record("An invalid type constructor must not become a nominal type")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("nativeMachine.types."))
            #expect(diagnostic.actual.contains("generic arguments"))
        }
    }

    @Test("Local nominal declarations take precedence over unqualified constructors")
    func localTypeNamesTakePrecedence() throws {
        let resolver = SourceTypeResolver(metadata: .init(
            enums: [.init(typeName: "Set", cases: [(name: "one", value: .int(1))])]
        ))
        #expect(try resolver.resolve("Set") == .named("Set"))
        #expect(try resolver.resolve("Swift.Set<Int>") == .set(.int))
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("Set<Int>") }
    }

    @Test("Typed references preserve their parsed qualification and generic arguments")
    func typedReferencePreservesSourceSyntax() throws {
        let expression: ExprSyntax = "SwiftTLA.OneOf < Int, SetExpr < String > >"
        let reference = try #require(ParserSession().typedFacadeType(expression))
        #expect(reference.name == "OneOf")
        #expect(reference.renderedSourceName == expression.trimmedDescription)
        #expect(reference.terminalArgumentName(at: 1) == "SetExpr")
    }

    @Test("Escaped alias declarations resolve through source metadata")
    func escapedAliasDeclarations() throws {
        let source = Parser.parse(source: """
        struct Model {
            typealias `Count` = Int
            typealias Counts = [Count]
            typealias `repeat` = Counts
        }
        """)
        let model = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let metadata = try TLASpecVerifier.sourceTypes(in: model.memberBlock.members, enums: [])
        let resolver = SourceTypeResolver(metadata: metadata)
        #expect(try resolver.resolve("Count") == .int)
        #expect(try resolver.resolve("`Count`") == .int)
        #expect(try resolver.resolve("`repeat`") == .array(.int))
    }

    @Test("Source aliases preserve nested record field types")
    func declaredAliasesPreserveFieldTypes() throws {
        let metadata = SourceTypeMetadata(
            aliases: ["Count": "Int", "Counts": "[Count]", "Schema": "Counters"],
            records: ["Counters": [.init(sourceName: "values", name: "values", swiftType: "Counts")]]
        )
        let resolver = SourceTypeResolver(metadata: metadata)
        #expect(try resolver.resolve("Counts") == .array(.int))
        #expect(try resolver.resolve("/* selected count */ Count") == .int)
        #expect(try resolver.resolve("`Count`") == .int)
        #expect(try resolver.resolve("Array<`Count`>") == .array(.int))
        #expect(try resolver.resolve("Record<Counters>") == .record([
            .init(name: "values", type: .array(.int))
        ]))
        #expect(try resolver.resolve("Record<Schema>") == resolver.resolve("Record<Counters>"))
        #expect(try resolver.resolve(" [Count] ") == .array(.int))
        let nested = CompiledValueType.dictionary(.string, .set(.array(.int)))
        #expect(try resolver.resolve("[String: Set<Counts>]") == nested)
        #expect(try resolver.resolve("Dictionary<Swift.String, Set<Array<Count>>>") == nested)
        #expect(try resolver.formalShape(for: "Record<Schema>") == .record([
            .init(name: "values", shape: .sequence(.integer))
        ]))
    }

    @Test("Escaped nominal references retain their declared type identity")
    func escapedNominalReferences() throws {
        let resolver = SourceTypeResolver(metadata: .init(
            records: ["Fields": [.init(sourceName: "value", name: "value", swiftType: "Int")]],
            enums: [.init(typeName: "Node", cases: [(name: "one", value: .int(1))], isFiniteDomain: true)]
        ))
        #expect(try resolver.resolve("`Node`") == resolver.resolve("Node"))
        #expect(try resolver.formalShape(for: "`Node`") == resolver.formalShape(for: "Node"))
        #expect(try resolver.resolve("Record<`Fields`>") == resolver.resolve("Record<Fields>"))
        #expect(try resolver.resolve("OneOf<`Node`, Set<Int>>") == resolver.resolve("OneOf<Node, Set<Int>>"))
        let ambiguous = SourceTypeResolver(metadata: .init(enums: [.init(typeName: "Node"), .init(typeName: "`Node`")]))
        #expect(throws: CompilationDiagnostic.self) { try ambiguous.resolve("Node") }
    }

    @Test("One source resolution preserves execution types and checked-view restrictions")
    func executionTypesRetainViewContracts() throws {
        let resolver = SourceTypeResolver(metadata: .init(
            enums: [.init(typeName: "Node", cases: [(name: "one", value: .int(1))], isFiniteDomain: true)]
        ))
        let function = CompiledValueType.dictionary(.named("Node"), .bool)
        #expect(try !resolver.formalShape(for: "Function<Node, Bool>").isSupported)
        #expect(try resolver.resolve("Function<Node, Bool>") == function)
        #expect(try resolver.resolve("PartialFunction<Node, Bool>") == function)
        #expect(try resolver.formalShape(for: "PartialFunction<Node, Bool>") == .function(
            key: .finite(typeName: "Node", values: [.int(1)]), value: .boolean))
        #expect(try resolver.resolve("[Function<Node, Bool>]") == .array(function))
        #expect(try !resolver.formalShape(for: "[Function<Node, Bool>]").isSupported)
        #expect(try resolver.formalShape(for: "OneOf<Node, Set<Int>>") == .union(
            .finite(typeName: "Node", values: [.int(1)]), .set(.integer)))
    }

    @Test("Alias and record cycles are rejected without poisoning resolved types")
    func recursiveDeclarationsAreRejected() throws {
        let resolver = SourceTypeResolver(metadata: .init(
            aliases: ["Count": "Int", "First": "`Second`", "Second": "/* cycle */ First"],
            records: ["Node": [.init(sourceName: "next", name: "next", swiftType: "Record<Node>")]]
        ))
        #expect(try resolver.resolve("Count") == .int)
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("First") }
        #expect(throws: CompilationDiagnostic.self) { try resolver.resolve("Record<Node>") }
        #expect(try resolver.resolve("Count") == .int)
    }

    @Test("Initializer type errors identify the owning variable", arguments: [
        VariableInitialization.value(.bool(false)),
        .expression(.value(.bool(false))),
        .memberOf(.setLiteral([.value(.bool(false))]))
    ])
    func initializerFailureIdentifiesVariable(_ initialization: VariableInitialization) throws {
        let specification = TLASpec(name: "InvalidInitializer", variables: [
            .init(name: "count", initialization: initialization, generatedSwiftType: "Int", origin: .source)
        ], actions: [], invariants: [])
        let compilation = try specification.compile()
        do {
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
            Issue.record("A Boolean initializer must not initialize an integer variable")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("nativeMachine.variables.count.initialization → "))
            #expect(diagnostic.actual.contains("Bool"))
            #expect(diagnostic.actual.contains("Int"))
        }
    }

    @Test("Collection action parameters require complete element types before resolution")
    func collectionActionParameterRequiresElementType() throws {
        func specification(type: String?) -> TLASpec {
            TLASpec(name: "CollectionActionParameter", variables: [], actions: [
                .init(name: "choose", body: .guard_(.value(.bool(true))), bindings: [
                    .init(name: "choice", values: [.set([])], generatedSwiftType: type)
                ])
            ], invariants: [])
        }
        let untyped = try specification(type: nil).compile()
        do {
            var checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: untyped))
            _ = try checker.checkProgram()
            Issue.record("An unresolved action binder must not reach program resolution")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unresolvedGeneratedValueShape)
            #expect(diagnostic.path == "nativeMachine.bindings.choice")
        }
        let typed = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification(type: "Set<Int>").compile()))
        #expect(Array(typed.bindingTypes.values) == [.set(.int)])
    }

    @Test("Later initializers cannot supply an earlier declaration's missing type")
    func laterInitializersCannotInferEarlierDeclarations() throws {
        func specification(type: String?) -> TLASpec {
            TLASpec(name: "InitializerContext", variables: [
                .init(name: "items", initialization: .value(.set([])), generatedSwiftType: type, origin: .source),
                .init(name: "containsOne", initialization: .expression(.in(.int(1), .variable("items"))),
                    generatedSwiftType: "Bool", origin: .source)
            ], actions: [], invariants: [])
        }
        do {
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification(type: nil).compile()))
            Issue.record("The membership test must not infer the earlier collection's element type")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unresolvedGeneratedValueShape)
            #expect(diagnostic.path == "nativeMachine.variables.items")
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification(type: "Set<Int>").compile()))
        #expect(program.variableTypes[VariableID(ordinal: 0)] == .set(.int))
        #expect(program.variableTypes[VariableID(ordinal: 1)] == .bool)
    }

    @Test("Later assignments cannot supply a missing declaration type")
    func emptyInitializerRequiresLocalContext() throws {
        let action = NamedAction(name: "insert", body: .assign(.named("items"), .value(.set([.int(1)]))))
        let untyped = TLASpec(name: "MissingContext", variables: [
            .init(name: "items", initial: .set([]))
        ], actions: [action], invariants: [])
        do {
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: untyped.compile()))
            Issue.record("An action must not infer the element type of an empty initializer")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unresolvedGeneratedValueShape)
            #expect(diagnostic.nextSafeAction.contains("typed initializer"))
        }
        let typed = TLASpec(name: "KnownContext", variables: [
            .init(name: "items", initialization: .value(.set([])), generatedSwiftType: "Set<Int>", origin: .source)
        ], actions: [action], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: typed.compile()))
        #expect(program.variableTypes.values.contains(.set(.int)))
    }

    @Test("deep filter and choice predicates preserve their domains without recursive checking")
    func nestedSetPredicates() throws {
        let specification = TLASpec(name: "SetPredicates", variables: [], actions: [], invariants: [])
        let checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let domain = CompiledExpression.setLiteral([.value(.integer(1))])
        var layers: [CompiledExpression] = [.value(.boolean(true))]
        defer { while layers.popLast() != nil {} }
        for index in 0..<1_000 {
            let predicate = try #require(layers.last)
            let binder = BinderID(ordinal: index)
            let nested: CompiledExpression = index.isMultiple(of: 2)
                ? .init(operation: .equal, children: [.choose(domain, binder, predicate), .value(.integer(1))])
                : .init(operation: .equal, children: [.setFilter(domain, binder, predicate), domain])
            layers.append(nested)
        }
        let checked = try checker.resolutionScope(try #require(layers.last), expected: .bool)
        #expect(checked.resultType == .bool)
        var predicate = checked
        for _ in 0..<1_000 {
            let selection = predicate.children[0]
            #expect(selection.children[0].resultType == .set(.int))
            predicate = selection.children[1]
        }
    }

    @Test("deep set operations reuse reconciled operand types", arguments: [false, true])
    func nestedSetOperations(hasExpectedType: Bool) throws {
        let specification = TLASpec(name: "SetOperations", variables: [], actions: [], invariants: [])
        let checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let domain = CompiledExpression.setLiteral([.value(.integer(1))])
        let expression = (0..<128).reduce(domain) { nested, index in
            switch index % 3 {
            case 0: .init(operation: .union, children: [nested, domain])
            case 1: .init(operation: .intersection, children: [nested, domain])
            default: .init(operation: .setDifference, children: [nested, domain])
            }
        }
        let checked = try checker.resolutionScope(expression, expected: hasExpectedType ? .set(.int) : nil)
        var operand = checked
        for _ in 0..<128 {
            #expect(operand.resultType == .set(.int))
            #expect(operand.children.count == 2)
            #expect(operand.children[1].resultType == .set(.int))
            operand = operand.children[0]
        }
        #expect(operand.resultType == .set(.int))
    }

    @Test("deep Boolean expressions retain their Boolean type")
    func longBooleanChains() throws {
        let specification = TLASpec(name: "BooleanChains", variables: [], actions: [], invariants: [])
        let checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let expression = (0..<1_000).reduce(CompiledExpression.value(.boolean(true))) { nested, index in
            switch index % 3 {
            case 0: .init(operation: .not, children: [nested])
            case 1: .init(operation: .and, children: [nested, .value(.boolean(true))])
            default: .init(operation: .or, children: [.value(.boolean(false)), nested])
            }
        }
        #expect(try checker.resolutionScope(expression, expected: .bool).resultType == .bool)
    }

    @Test("deep conditionals preserve branch types without recursive checking")
    func deepConditionals() throws {
        let specification = TLASpec(name: "ConditionalChains", variables: [], actions: [], invariants: [])
        let checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let expression = (0..<1_000).reduce(CompiledExpression.value(.integer(1))) { nested, index in
            if index.isMultiple(of: 2) {
                .ifThenElse(.value(.boolean(true)), nested, .value(.integer(0)))
            } else {
                .ifThenElse(.value(.boolean(false)), .value(.integer(0)), nested)
            }
        }
        #expect(try checker.resolutionScope(expression, expected: .int).resultType == .int)
        let invalid = CompiledExpression.ifThenElse(.value(.boolean(true)),
            .ifThenElse(.value(.integer(1)), .value(.integer(0)), .value(.integer(2))),
            .value(.string("later")))
        do {
            _ = try checker.type(of: invalid, expected: .int)
            Issue.record("A non-Boolean condition must be rejected first")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasSuffix(" <- value <- ifThenElse <- ifThenElse"))
        }
    }

    @Test("mixed Boolean, conditional, and lexical nesting shares one checking worklist")
    func mixedExpressionNesting() throws {
        let specification = TLASpec(name: "MixedNesting", variables: [], actions: [], invariants: [])
        let checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let expression = (0..<1_000).reduce(CompiledExpression.value(.boolean(true))) { nested, index in
            switch index % 3 {
            case 0: .init(operation: .not, children: [nested])
            case 1: .ifThenElse(.value(.boolean(true)), nested, .value(.boolean(false)))
            default: .letValue(.init(ordinal: index), .value(.integer(index)), nested)
            }
        }
        #expect(try checker.resolutionScope(expression, expected: .bool).resultType == .bool)
    }

    @Test("nested quantifiers retain their domains inside collection constructors")
    func nestedQuantifierDomains() throws {
        let specification = TLASpec(name: "QuantifierNesting", variables: [], actions: [], invariants: [])
        let checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let domain = CompiledExpression.setLiteral([.value(.integer(1))])
        let predicate = (0..<1_000).reduce(CompiledExpression.value(.boolean(true))) { nested, index in
            let binder = BinderID(ordinal: index)
            return index.isMultiple(of: 2) ? .forAll(domain, binder, nested) : .exists(domain, binder, nested)
        }
        let binder = BinderID(ordinal: 1_000)
        let cases: [(CompiledExpression, CompiledValueType)] = [
            (predicate, .bool),
            (.setMap(predicate, binder, domain), .set(.bool)),
            (.functionLiteral(domain, binder, predicate), .dictionary(.int, .bool))
        ]
        for (expression, expected) in cases {
            let checked = try checker.resolutionScope(expression, expected: expected)
            #expect(checked.resultType == expected)
            var quantifier: CompiledExpression
            switch expression.operation {
            case .setMap: quantifier = checked.children[0]
            case .functionLiteral: quantifier = checked.children[1]
            default: quantifier = checked
            }
            for _ in 0..<1_000 {
                #expect(quantifier.children[0].resultType == .set(.int))
                quantifier = quantifier.children[1]
            }
        }
    }

    @Test("deep arithmetic and comparison expressions share iterative checking")
    func deepArithmeticAndComparisons() throws {
        let specification = TLASpec(name: "ScalarNesting", variables: [], actions: [], invariants: [])
        let checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let arithmetic = (0..<1_000).reduce(CompiledExpression.value(.integer(1))) { nested, index in
            index.isMultiple(of: 2) ? .init(operation: .add, children: [nested, .value(.integer(0))]) : .init(operation: .negate, children: [nested])
        }
        let comparison = (0..<1_000).reduce(CompiledExpression.value(.boolean(true))) { nested, _ in
            .init(operation: .equal, children: [nested, .value(.boolean(true))])
        }
        #expect(try checker.resolutionScope(arithmetic, expected: .int).resultType == .int)
        #expect(try checker.resolutionScope(comparison, expected: .bool).resultType == .bool)
        #expect(throws: CompilationDiagnostic.self) {
            try checker.type(of: .init(operation: .subset, children: [.value(.integer(1)), .value(.integer(2))]), expected: .bool)
        }
    }

    @Test("Boolean diagnostics retain the failing branch's ancestry and left-to-right order")
    func booleanBranchDiagnostics() throws {
        let specification = TLASpec(name: "BooleanBranches", variables: [], actions: [], invariants: [])
        let checker = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let first = CompiledExpression.init(operation: .and, children: [.init(operation: .not, children: [.value(.integer(1))]), .value(.string("later"))])
        let second = CompiledExpression.init(operation: .and, children: [.init(operation: .or, children: [.value(.boolean(true)), .value(.boolean(false))]), .init(operation: .not, children: [.value(.integer(1))])])
        for expression in [first, second] {
            do {
                _ = try checker.resolutionScope(expression, expected: .bool)
                Issue.record("A non-Boolean operand must be rejected")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasSuffix(" <- value <- not <- and"))
            }
        }
    }

    @Test("Incomplete inference identifies the missing field type without an internal expression dump")
    func missingCollectionElement() throws {
        let specification = TLASpec(name: "MissingElementType", variables: [
            .init(name: "accumulator", initialization: .expression(
                .recordLiteral(.init(["execution": .tupleLiteral([])]))), origin: .compiler)
        ], actions: [], invariants: [])
        do {
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
            Issue.record("An unresolved element type must not reach Swift emission")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unresolvedGeneratedValueShape)
            #expect(diagnostic.path == "nativeMachine.variables.accumulator")
            #expect(diagnostic.actual == "type inference could not determine value.execution.element")
            #expect(!diagnostic.description.contains("BinderID"))
        }
    }

    @Test("Expression failures report the operation without dumping nested payloads")
    func expressionFailureIdentifiesOperation() throws {
        let specification = TLASpec(name: "InvalidOperand", variables: [
            .init(name: "count", initialization: .value(.int(0)), origin: .compiler)
        ], actions: [], invariants: [])
        let inference = try CompiledTypeChecker(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let payload = String(repeating: "private-expression-payload", count: 1_000)
        let expression = CompiledExpression.init(operation: .add, children: [.value(.string(payload)), .value(.integer(1))])
        do {
            _ = try inference.resolutionScope(expression, expected: .int)
            Issue.record("String operands must not be accepted as integers")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasSuffix(" <- value <- add"))
            #expect(!diagnostic.description.contains(payload))
            #expect(!diagnostic.description.contains("CompiledExpression"))
        }
    }

}
