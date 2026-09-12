import Testing
import SwiftParser
import SwiftSyntax
import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Specification source authority")
struct SpecificationSourceAuthorityTests {
    @Test("Initializers retain their declared type through parentheses", arguments: [
        ("SetExpr<Record<Entry>>.literal()", "SetExpr<Record<Entry>>"),
        ("Function<Key, Record<Entry>>.literal()", "Function<Key, Record<Entry>>"),
        ("Function<Key, Bool>.mapping { _ in true }", "Function<Key, Bool>"),
        ("Pair<Int, String>.literal(1, \"one\")", "Pair<Int, String>"),
        ("ZeroBasedSequence<Int>.filled(with: 0, count: 2)", "ZeroBasedSequence<Int>"),
        ("SetExpr<Int>()", "SetExpr<Int>"),
        ("Mode.idle", "Mode"),
        ("OneOf<Int, String>.first(1)", "OneOf<Int, String>"),
        ("1", "Int")
    ])
    func initializerResultTypes(_ source: String, _ expected: String) throws {
        for depth in [0, 1, 8] {
            let parenthesized = String(repeating: "(", count: depth) + source + String(repeating: ")", count: depth)
            let expression = try #require(Parser.parse(source: parenthesized).statements.first?.item.as(ExprSyntax.self))
            #expect(ParserSession().initialValueTypeName(from: expression) == expected)
        }
    }

    @Test("Subscript operations follow lexical types through renaming and shadowing")
    func subscriptsUseLexicalTypes() throws {
        let parser = ParserSession()
        let tupleScope = ParserSession.TypedFacadeScope.empty.extending(
            sourceName: "items", value: .variable("storedSequence"), shape: .array(.int))
        let functionScope = tupleScope.extending(
            sourceName: "items", value: .variable("localFunction"), shape: .dictionary(.int, .array(.int)))
        func decode(_ source: String, scope: ParserSession.TypedFacadeScope) throws -> StateExpr? {
            let expression = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
            return parser.decodeTypedFacadeValue(expression, scope: scope)
        }
        for source in ["items[1]", "items.expr[1]", "((items))[1]"] {
            #expect(try decode(source, scope: tupleScope)
                == .tupleDynamicAccess(.variable("storedSequence"), .int(1)))
            #expect(try decode(source, scope: functionScope)
                == .functionApply(.variable("localFunction"), .int(1)))
        }
        #expect(try decode("items[1][2]", scope: functionScope)
            == .tupleDynamicAccess(.functionApply(.variable("localFunction"), .int(1)), .int(2)))
    }

    @Test("Collection predicates retain shadowed collections and captured local values", arguments: ["allSatisfy", "contains"])
    func collectionPredicatesUseLexicalScope(_ operation: String) throws {
        let parser = ParserSession()
        parser.sourceScope = .empty.extending(sourceName: "items", value: .variable("outer"), shape: nil)
        let scope = parser.sourceScope
            .extending(sourceName: "items", value: .variable("inner"), shape: nil)
            .extending(sourceName: "bound", value: .variable("limit"), shape: nil)
        let source = "items.\(operation) { item in item == bound }"
        let expression = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
        let predicates = [
            parser.decodeTypedFacadeValue(expression, scope: scope),
            parser.decodeTypedFacadeValue(expression, scope: scope)
        ]
        for predicate in predicates {
            let parsed = try #require(predicate)
            let domain: StateExpr
            let binder: String
            let body: StateExpr
            switch parsed {
            case .forAll(let set, let parameter, let expression):
                #expect(operation == "allSatisfy")
                (domain, binder, body) = (set, parameter, expression)
            case .exists(let set, let parameter, let expression):
                #expect(operation == "contains")
                (domain, binder, body) = (set, parameter, expression)
            default:
                Issue.record("Expected a collection predicate")
                continue
            }
            #expect(domain == .domain(.variable("inner")))
            #expect(body == .equal(.functionApply(.variable("inner"), .variable(binder)), .variable("limit")))
        }
    }

    @Test("Initial domains retain lexical bindings, declared types, and formal variable names", arguments: [false, true])
    func initialDomainsUseDeclarationContext(_ inAlgorithm: Bool) throws {
        let declarations = #"""
            let options = SetExpr<Int>.literal(1, 2)
            let selected: SharedVariable<Int> = scope.sharedVar("stored", in: options)
        """#
        let body = inAlgorithm
            ? "Algorithm(\"ScopedDomain\", scoped: { scope in \(declarations)\n Do(Label.stay) { Skip() } })"
            : declarations + "\n SwiftTLA.Action(\"stay\") { selected.stays }"
        let model = try declaration("""
        enum Label: String, CaseIterable { case stay }
        static var spec: TLASpec {
            #spec("ScopedDomain") { scope in \(body) }
        }
        """)
        let program = try TLASpecVerifier.parseAndVerify(model).program
        let variable = try #require(program.layout.variables.first { $0.declaration.name == "stored" })
        #expect(program.variableTypes[variable.id] == .int)
        guard case .memberOf(let domain) = program.behavior.initializations.first(where: { $0.variable == variable.id })?.initialization else {
            Issue.record("Expected the declared initial domain to survive resolution")
            return
        }
        #expect(domain.resultType == .set(.int))
    }

    @Test("Tuple shape survives source bindings, state initialization, and invariant locals")
    func invariantLocalsPreserveTypes() throws {
        let model = try declaration(#"""
        static var spec: TLASpec {
            #spec("ScopedTuple") { scope in
                let initial = TupleExpr<Int>.literal(1, 2)
                let items: SharedVariable<TupleExpr<Int>> = scope.sharedVar("stored", initial: initial)
                Invariant("Length") {
                    let sequence = items.expr
                    sequence.count == 2
                }
                SwiftTLA.Action("stay") { items.stays }
            }
        }
        """#)
        let program = try TLASpecVerifier.parseAndVerify(model).program
        let invariant = try #require(program.behavior.invariants.first)
        #expect(invariant.predicate.expression.children.first?.operation == .tupleLength)
    }

    @Test("Contextual enum cases cannot resolve through another enum", arguments: [false, true])
    func enumContextOwnsShorthandLookup(_ reversed: Bool) throws {
        let declarations: [SourceEnum] = [
            .init(typeName: "First", cases: [("ready", .int(1))]),
            .init(typeName: "Second", cases: [("ready", .int(2)), ("onlySecond", .int(1))])
        ]
        let alias = try #require(Parser.parse(source: "typealias Selected = First").statements.first?.item.as(TypeAliasDeclSyntax.self))
        let parser = ParserSession(sourceTypes: .init(
            aliases: ["Selected": alias.initializer.value],
            enums: reversed ? Array(declarations.reversed()) : declarations
        ))
        func decode(_ source: String, as expectedType: String) throws -> StateExpr? {
            let expression = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
            return parser.decodeTypedFacadeValue(expression, scope: .empty, expectedEnumType: expectedType)
        }
        for expectedType in ["First", "Selected"] {
            #expect(try decode(".ready", as: expectedType) == .value(.int(1)))
            #expect(try decode("(.ready)", as: expectedType) == .value(.int(1)))
            #expect(try decode(".onlySecond", as: expectedType) == nil)
            #expect(try decode("(.onlySecond)", as: expectedType) == nil)
            #expect(try decode("Selected.ready", as: expectedType) == .value(.int(1)))
            #expect(try decode("Selected.onlySecond", as: expectedType) == nil)
        }
    }

    @Test("Enum initializers preserve explicit owners and reject ambiguous shorthand", arguments: [false, true])
    func enumInitializersRequireUniqueOwners(_ reversed: Bool) throws {
        let declarations: [SourceEnum] = [
            .init(typeName: "First", cases: [("ready", .int(1)), ("onlyFirst", .int(2))]),
            .init(typeName: "Second", cases: [("ready", .int(3)), ("onlySecond", .int(4))])
        ]
        let parser = ParserSession(sourceTypes: .init(enums: reversed ? Array(declarations.reversed()) : declarations))
        func expression(_ source: String) throws -> ExprSyntax {
            try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
        }
        #expect(parser.parseInitialExpr(try expression("First.ready")) == .int(1))
        #expect(parser.parseInitialExpr(try expression("Second.ready")) == .int(3))
        #expect(parser.parseInitialExpr(try expression(".onlyFirst")) == .int(2))
        #expect(parser.parseInitialExpr(try expression("First.onlySecond")) == nil)
        #expect(parser.parseInitialExpr(try expression("Missing.ready")) == nil)
        #expect(parser.parseInitialExpr(try expression(".ready")) == nil)
        #expect(parser.algorithmParseFailure?.contains("ambiguous") == true)
    }

    @Test("Qualified Swift and SwiftTLA inheritance preserves nominal type metadata", arguments: [
        ("Swift.Int, SwiftTLA.TLAValueType", "Int, TLAValueType"),
        ("Swift.String, Swift.CaseIterable", "String, CaseIterable"),
        ("Swift.Int, SwiftTLA.FiniteTLAValueDomain", "Int, FiniteTLAValueDomain")
    ])
    func qualifiedInheritancePreservesTypes(_ qualified: String, _ unqualified: String) throws {
        let model = try declaration("enum Key: \(qualified) { case first }")
        let plain = try declaration("enum Key: \(unqualified) { case first }")
        let qualifiedEnums = try TLASpecVerifier.collectEnumVariables(from: model.memberBlock.members)
        let plainEnums = try TLASpecVerifier.collectEnumVariables(from: plain.memberBlock.members)
        let qualifiedType = try #require(qualifiedEnums.first)
        let plainType = try #require(plainEnums.first)
        #expect(qualifiedType.cases.map(\.value) == plainType.cases.map(\.value))
        let qualifiedMetadata = try TLASpecVerifier.sourceTypes(in: model.memberBlock.members, enums: qualifiedEnums)
        let plainMetadata = try TLASpecVerifier.sourceTypes(in: plain.memberBlock.members, enums: plainEnums)
        #expect(qualifiedMetadata.enums.filter(\.isFiniteDomain).map(\.finiteValues) == plainMetadata.enums.filter(\.isFiniteDomain).map(\.finiteValues))
    }

    @Test("Unrelated module names do not establish model enum conformances", arguments: [
        "Other.Int, TLAValueType", "Int, Other.TLAValueType", "String, Other.CaseIterable"
    ])
    func unrelatedInheritanceIsNotModelMetadata(_ inheritance: String) throws {
        let model = try declaration("enum Key: \(inheritance) { case first }")
        #expect(try TLASpecVerifier.collectEnumVariables(from: model.memberBlock.members).isEmpty)
    }

    @Test("Duplicate type names are rejected before constructing nominal metadata", arguments: [
        "enum Key: String, CaseIterable { case first }; enum Key: String, CaseIterable { case second }",
        "typealias Key = Int; typealias `Key` = Bool",
        "typealias Key = Int; struct Key {}",
        "enum Key: String, CaseIterable { case first }; struct `Key` {}"
    ])
    func duplicateTypeNamesAreDiagnosed(_ source: String) throws {
        let model = try declaration(source)
        let enums = try TLASpecVerifier.collectEnumVariables(from: model.memberBlock.members)
        #expect(throws: ModelMacroError.duplicateTypeDeclaration(typeName: "Key")) {
            _ = try TLASpecVerifier.sourceTypes(in: model.memberBlock.members, enums: enums)
        }
    }

    @Test("Enum case names and raw values remain one-to-one", arguments: [
        ("String", "case first, `first`", ModelMacroError.duplicateEnumCase(typeName: "Key", caseName: "first")),
        ("String", "case first = \"same\", second = \"same\"", ModelMacroError.duplicateEnumRawValue(typeName: "Key", caseName: "second")),
        ("Int", "case first = 1, second = 1", ModelMacroError.duplicateEnumRawValue(typeName: "Key", caseName: "second"))
    ])
    func duplicateEnumCasesAreDiagnosed(_ rawType: String, _ cases: String, _ error: ModelMacroError) throws {
        let model = try declaration("enum Key: \(rawType), TLAValueType { \(cases) }")
        #expect(throws: error) {
            _ = try TLASpecVerifier.collectEnumVariables(from: model.memberBlock.members)
        }
    }

    @Test("Direct specification getters retain their inline declaration")
    func directGettersAreAdmitted() throws {
        let getters = [
            "#spec(\"Authority\") {}",
            "return #spec(\"Authority\") {}",
            "get { #spec(\"Authority\") {} }",
            "get { return TLASpec(\"Authority\") {} }",
            "TLASpec(\"Authority\", {})",
            "TLASpec(\"Authority\", scoped: { scope in })",
            "#spec(\"Authority\", scoped: { scope in })"
        ]
        for getter in getters {
            let declaration = try declaration("static var spec: TLASpec { \(getter) }")
            let source = try #require(try TLASpecVerifier.findSpec(in: declaration.memberBlock.members))
            #expect(source.name == "Authority")
        }
    }

    @Test("Runtime getter statements cannot change the compiled declaration")
    func executableGettersAreRejected() throws {
        let getters = [
            "recordAccess(); return #spec(\"Authority\") {}",
            "if dynamicFlag { return otherSpec }; return #spec(\"Authority\") {}",
            "return #spec(\"Authority\") {}; recordAccess()",
            "defer { recordAccess() }; return TLASpec(\"Authority\") {}",
            "let ignored = makeValue(); TLASpec(\"Authority\") {}",
            "get { recordAccess(); return TLASpec(\"Authority\") {} }",
            "get { TLASpec(\"Authority\") {} } set { recordAccess() }",
            "get async { TLASpec(\"Authority\") {} }",
            "dynamicFlag ? otherSpec : TLASpec(\"Authority\") {}",
            "TLASpec(\"Authority\", makeBuilder())",
            "TLASpec(\"Authority\", ignored: makeValue()) {}",
            "#spec(\"Authority\", ignored: makeValue()) {}",
            "TLASpec(\"Authority\") {} ignored: {}"
        ]
        for getter in getters {
            try expectRejection("static var spec: TLASpec { \(getter) }")
        }
    }

    @Test("Specification identity requires one static getter declaration")
    func alternateStorageIsRejected() throws {
        for members in [
            "var spec: TLASpec { TLASpec(\"Authority\") {} }",
            "static let spec = TLASpec(\"Authority\") {}",
            "static var spec: TLASpec { TLASpec(\"Authority\") {} }; static var spec: TLASpec { TLASpec(\"Other\") {} }"
        ] {
            try expectRejection(members)
        }
    }

    @Test("Finite domains preserve every admitted case and empty domain")
    func literalEnumDomainsArePreserved() throws {
        for (initializer, count) in [("[.second, Self.first]", 2), ("[]", 0), ("allCases", 2)] {
            let declaration = try declaration("""
            enum Phase: String, CaseIterable, FiniteTLAValueDomain {
                case first, second
                static let finiteValues: [Self] = \(initializer)
            }
            """)
            let enums = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
            let domain = try #require(enums.first?.finiteValues)
            #expect(domain.count == count)
        }
    }

    @Test("Dynamic or partially parsed finite domains cannot silently become all cases")
    func dynamicEnumDomainsAreRejected() throws {
        for member in [
            "static let finiteValues = makeDomain()",
            "static var finiteValues: [Self] { [.first] }",
            "static var finiteValues: [Self] = [.first]",
            "static let finiteValues = [.first, makeCase()]",
            "static let finiteValues = [Other.first]",
            "static let finiteValues = Other.allCases",
            "static let allCases: [Self] = [.first]; static let finiteValues = allCases"
        ] {
            let declaration = try declaration("""
            enum Phase: String, CaseIterable, FiniteTLAValueDomain {
                case first, second
                \(member)
            }
            """)
            #expect(throws: ModelMacroError.dynamicFiniteDomain(typeName: "Phase")) {
                _ = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
            }
        }
    }

    @Test("Explicit enum encodings preserve formal atoms and primitive raw values")
    func explicitEnumEncodingsArePreserved() throws {
        for body in [".constant(rawValue)", "return TLAValue.constant(self.rawValue)", "get { .constant(rawValue) }"] {
            let declaration = try declaration("""
            enum Key: String, CaseIterable, FiniteTLAValueDomain {
                case first = "k1", second = "k2"
                var tlaValue: TLAValue { \(body) }
                static let finiteValues: [Self] = [.second]
            }
            """)
            let info = try #require(TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members).first)
            #expect(info.cases.map(\.value) == [.constant("k1"), .constant("k2")])
            #expect(info.finiteValues == [.constant("k2")])
        }
        let strings = try declaration("""
        enum Key: String, TLAValueType {
            case first = "k1"
            var tlaValue: TLAValue { .string(rawValue) }
        }
        """)
        #expect(try TLASpecVerifier.collectEnumVariables(from: strings.memberBlock.members).first?.cases.first?.value == .string("k1"))
        let integers = try declaration("""
        enum Key: Int, TLAValueType {
            case first = 4
            var tlaValue: TLAValue { .int(rawValue) }
        }
        """)
        #expect(try TLASpecVerifier.collectEnumVariables(from: integers.memberBlock.members).first?.cases.first?.value == .int(4))
    }

    @Test("Integer enum raw values preserve signed and radix literals")
    func integerEnumLiteralSpellingsAreAdmitted() throws {
        let declaration = try declaration("""
        enum Number: Int, TLAValueType {
            case negative = -0x10, next
            case binary = 0b1010, octal = 0o17
            case minimum = -9223372036854775808
        }
        """)
        let info = try #require(TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members).first)
        #expect(info.cases.map(\.value) == [.int(-16), .int(-15), .int(10), .int(15), .int(Int.min)])
    }

    @Test("A final maximum integer enum case does not overflow macro expansion")
    func maximumIntegerEnumCasesAreAdmitted() throws {
        for cases in ["case maximum = 9223372036854775807", "case previous = 9223372036854775806, maximum"] {
            let declaration = try declaration("enum Limit: Int, TLAValueType { \(cases) }")
            let info = try #require(TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members).first)
            #expect(info.cases.last?.value == .int(Int.max))
        }
        let declaration = try declaration("enum Limit: Int, TLAValueType { case maximum = 9223372036854775807, overflow }")
        #expect(throws: ModelMacroError.invalidEnumRawValue(caseName: "overflow")) {
            _ = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
        }
    }

    @Test("Escaped enum cases retain semantic names and default raw values")
    func escapedEnumCasesPreserveIdentity() throws {
        let declaration = try declaration("""
        enum Step: String, CaseIterable {
            case `repeat`, normal
            static let finiteValues: [Self] = [Self.`repeat`]
        }
        """)
        let info = try #require(TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members).first)
        #expect(info.cases.map(\.name) == ["repeat", "normal"])
        #expect(info.cases.map(\.value) == [.string("repeat"), .string("normal")])
        #expect(info.finiteValues == [.string("repeat")])
    }

    @Test("Dynamic enum encodings cannot silently change generated semantics")
    func dynamicEnumEncodingsAreRejected() throws {
        for body in [
            "encode(rawValue)",
            "recordAccess(); return .constant(rawValue)",
            "flag ? .constant(rawValue) : .string(rawValue)",
            #".constant("different")"#,
            ".int(rawValue)",
            "get { .constant(rawValue) } set { recordAccess() }"
        ] {
            let declaration = try declaration("""
            enum Key: String, TLAValueType {
                case first
                var tlaValue: TLAValue { \(body) }
            }
            """)
            #expect(throws: ModelMacroError.unsupportedEnumEncoding(typeName: "Key")) {
                _ = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
            }
        }
    }

    @Test("Native source metadata preserves aliases and formal record field names")
    func sourceMetadataPreservesAliasesAndRecordNames() throws {
        let declaration = try declaration(#"""
        typealias Value = OneOf<Transaction, NoValue>
        struct OperationFields {
            let operation: OperationKind
            let value: Value
        }
        enum OperationSchema: SwiftTLA.TLARecordSchema {
            typealias Fields = OperationFields
            static func fieldName<Value>(for field: KeyPath<OperationFields, Value>) -> String? {
                let key = field as AnyKeyPath
                if key == \OperationFields.operation { return "op" }
                if key == \OperationFields.value { return "value" }
                return nil
            }
            static let operation = field(\OperationFields.operation)
            static let value = field(\OperationFields.value)
            static let fields = [
                TLARecordFieldDeclaration(operation, default: OperationKind.read),
                TLARecordFieldDeclaration(value, default: Value.second(.noVal))
            ]
        }
        """#)
        let metadata = try TLASpecVerifier.sourceTypes(in: declaration.memberBlock.members, enums: [])
        #expect(metadata.aliases["Value"]?.trimmedDescription == "OneOf<Transaction, NoValue>")
        #expect(metadata.records["OperationSchema"]?.map(\.name) == ["op", "value"])
        #expect(metadata.records["OperationSchema"]?.map(\.sourceName) == ["operation", "value"])
        #expect(metadata.records["OperationSchema"]?.map { $0.swiftType.trimmedDescription } == ["OperationKind", "Value"])
    }

    @Test("Dynamic schema field-name mappings are rejected")
    func sourceMetadataRejectsDynamicRecordNames() throws {
        let declaration = try declaration(#"""
        struct DynamicFields { let value: Int }
        enum Schema: TLARecordSchema {
            typealias Fields = DynamicFields
            static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String? {
                return runtimeName(field)
            }
        }
        """#)
        #expect(throws: ModelMacroError.unsupportedRecordSchema(typeName: "Schema")) {
            _ = try TLASpecVerifier.sourceTypes(in: declaration.memberBlock.members, enums: [])
        }
    }

    private func expectRejection(_ members: String) throws {
        let declaration = try declaration(members)
        #expect(throws: ModelMacroError.nonLiteralSpecification) {
            _ = try TLASpecVerifier.findSpec(in: declaration.memberBlock.members)
        }
    }

    private func declaration(_ members: String) throws -> StructDeclSyntax {
        try #require(Parser.parse(source: "struct Model { \(members) }")
            .statements.first?.item.as(StructDeclSyntax.self))
    }
}
