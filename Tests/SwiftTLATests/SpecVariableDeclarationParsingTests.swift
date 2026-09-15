import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct SpecVariableDeclarationParsingTests {
    @Test("Malformed variable declarations cannot replace an existing initializer", arguments: [
        "Variable(computed: value) { 1; unsupported() }",
        "Variable(computed: value) { 1 }",
        "Variable(value, 1, 2)",
        "Variable(value, 1) { unsupported() }",
        "Variable(from: \"value\", 0...1, unexpected)",
        "Variable(value, in: unsupported())",
        "Variable(from: \"value\", unsupported())",
        "Variable(\"value\", bogus: 1)"
    ])
    func malformedVariablesPreservePriorDeclaration(_ declaration: String) throws {
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", try parseSpecTestClosure(
            "{ let value = Var(\"value\", 7); \(declaration) }"))
        #expect(!parsed.diagnostics.isEmpty)
        #expect(parsed.variables.count == 1)
        #expect(parsed.variables.first?.initialization == .value(.int(7)))
        #expect(throws: SourceParseDiagnostic.self) { try parsed.compile() }
    }

    @Test("Raw collection initializers cannot discard supplied contents", arguments: [
        "TLAValue.set([.int(1)])",
        "TLAValue.tuple([.int(1)])",
        "TLAValue.record([\"field\": .int(1)])",
        "TLAValue.function([.int(1): .int(2)])",
        "TLAValue.set(externalMembers)",
        "TLAValue.tuple(makeMembers())",
        "TLAValue.record(externalFields)",
        "TLAValue.function(externalEntries)",
        "TLAValue.set()",
        "TLAValue.tuple([], unexpected)",
        "TLAValue.record([])",
        "TLAValue.function([:]) { unsupported() }",
        #""value \(external)""#
    ])
    func rejectsUndecodableInitialValues(_ initializer: String) throws {
        for declaration in [
            "let value = Var(\"value\", \(initializer))",
            "let value = Var<Int>(\"value\"); Variable(value, \(initializer))"
        ] {
            let parsed = SpecParser.parseSpecClosure(named: "Parsed", try parseSpecTestClosure("{ \(declaration) }"))
            #expect(!parsed.diagnostics.isEmpty)
            #expect(throws: SourceParseDiagnostic.self) { try parsed.compile() }
        }
    }

    @Test("Explicit empty raw collections preserve their declared kind", arguments: [
        ("TLAValue.set([])", TLAValue.set([])),
        ("TLAValue.tuple([])", TLAValue.tuple([])),
        ("TLAValue.record([:])", TLAValue.record([:])),
        ("TLAValue.function([:])", TLAValue.function([:]))
    ])
    func emptyRawCollectionInitializers(_ initializer: String, _ expected: TLAValue) throws {
        for declaration in [
            "let value = Var(\"value\", \(initializer))",
            "let value = Var<Int>(\"value\"); Variable(value, \(initializer))"
        ] {
            let parsed = SpecParser.parseSpecClosure(named: "Parsed", try parseSpecTestClosure("{ \(declaration) }"))
            #expect(parsed.diagnostics.isEmpty)
            #expect(parsed.variables.first?.initialization == .value(expected))
        }
    }

    @Test func plainVarDeclarationIsParsedWithoutGenericSpecialization() throws {
        let source = """
        {
            let counter = Var("counter", 0)
            Variable(counter, in: 0...1)
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.count == 1)
        guard parsed.variables.count == 1 else { return }
        #expect(parsed.variables[0].name == "counter")
        #expect(parsed.variables[0].initialization == .memberOf(.integerRange(.int(0), .int(1))))
        #expect(parsed.variables[0].generatedSwiftType == "Int")
    }

    @Test func oneArgumentVariableReferencesPreserveBindingMetadataAndOrder() throws {
        let source = """
        {
            let queued = Var("queued", TLAValue.set([]))
            Variable(queued)
            let phase = Var("phase", 0)
            Variable(phase)
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.count == 2)
        #expect(parsed.variables[0].name == "queued")
        #expect(parsed.variables[0].initialization == .value(.set([])))
        #expect(parsed.variables[0].generatedSwiftType == "TLAValue")
        #expect(parsed.variables[1].name == "phase")
        #expect(parsed.variables[1].initialization == .value(.int(0)))
        #expect(parsed.variables[1].generatedSwiftType == "Int")
    }

    @Test("an explicit declaration initializer replaces the unresolved Var initializer")
    func explicitVariableInitializerReplacesUnresolvedInitializer() throws {
        let unresolved = SpecParser.parseSpecClosure(named: "UnresolvedInitializer", try parseSpecTestClosure("""
        {
            let values = Var<SetExpr<Int>>("values")
            Variable(values)
        }
        """))
        let resolved = SpecParser.parseSpecClosure(named: "ResolvedInitializer", try parseSpecTestClosure("""
        {
            let values = Var<SetExpr<Int>>("values")
            Variable(values, SetExpr<Int>())
        }
        """))

        do {
            _ = try unresolved.compile()
            Issue.record("Expected compilation to reject the unresolved initializer")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .missingVariableInitializer)
        }
        let compilation = try resolved.compile()
        #expect(compilation.description.variables.map(\.name) == ["values"])
    }

    @Test("generic variable types retain their structural Swift spelling")
    func retainsQualifiedGenericVariableType() throws {
        let source = """
        {
            let successors = Var<SwiftTLA.Function<Model.Node, SwiftTLA.SetExpr<Swift.Int>>>("successors", TLAValue.function([:]))
        }
        """
        let closure = try parseSpecTestClosure(source)

        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.map(\.generatedSwiftType) == ["SwiftTLA.Function<Model.Node, SwiftTLA.SetExpr<Swift.Int>>"])
    }

    @Test("top-level variable declarations retain their Swift type")
    func retainsAnnotatedVariableType() throws {
        let source = """
        { scope in
            let mode: SharedVariable<CameraMode> = scope.sharedVar("mode", initial: CameraMode.idle)
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure, sourceTypes: .init(enums: [cameraModeDefinition]))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.map(\.generatedSwiftType) == ["CameraMode"])
    }

    @Test("top-level temporal declarations bind typed variables")
    func bindsTopLevelTemporalDeclarations() throws {
        let source = """
        {
            let count = Var<Int>("count", 0)
            Variable(count)
            LeadsTo("progress", count == 0, count > 0)
            Eventually("eventual", count > 0)
            Always("safe", count >= 0)
            AlwaysEventually("recurs", count > 0)
            EventuallyAlways("settles", count >= 0)
        }
        """

        let parsed = SpecParser.parseSpecClosure(named: "Parsed", try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.temporalProperties.map(\.name) == ["progress", "eventual", "safe", "recurs", "settles"])
    }

    @Test func finiteVariableDomainsCompareAsFormalSets() throws {
        func specification(_ values: [StateExpr]) -> TLASpec {
            TLASpec(
                name: "CanonicalTestSpec",
                variables: [.init(
                    name: "counter",
                    initialization: .memberOf(.setLiteral(values)),
                    generatedSwiftType: "Int",
                    origin: .source
                )],
                actions: [],
                invariants: []
            )
        }
        let parsed = specification([.int(0), .int(1)])
        let built = specification([.int(1), .int(0)])

        #expect(try parsed.compile().identity == built.compile().identity)
    }

    @Test func formalOperatorDefinitionsAffectCompilationIdentity() throws {
        let parserTree = canonicalTestSpec(
            variables: [],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                FormalOperatorDefinition(
                    name: "increment",
                    parameters: [.value("value")],
                    body: .add(.variable("value"), .int(1))
                )
            ]
        )
        let builderTree = canonicalTestSpec(
            variables: [],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                FormalOperatorDefinition(
                    name: "increment",
                    parameters: [.value("value")],
                    body: .add(.variable("value"), .int(2))
                )
            ]
        )

        #expect(try parserTree.compile().identity != builderTree.compile().identity)
    }

    @Test func formalDefinitionParameterNamesShareCompilationIdentity() throws {
        let parserTree = canonicalTestSpec(
            variables: [],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                FormalOperatorDefinition(
                    name: "apply",
                    parameters: [.operator("transform", arity: 1), .value("input")],
                    body: .operatorApplication(
                        .reference("transform", arity: 1),
                        [.value(.variable("input"))]
                    )
                )
            ]
        )
        let builderTree = canonicalTestSpec(
            variables: [],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                FormalOperatorDefinition(
                    name: "apply",
                    parameters: [.operator("operation", arity: 1), .value("value")],
                    body: .operatorApplication(
                        .reference("operation", arity: 1),
                        [.value(.variable("value"))]
                    )
                )
            ]
        )

        #expect(try parserTree.compile().identity == builderTree.compile().identity)
    }

    @Test func formalDefinitionIsParsedIntoTheSourceModel() throws {
        let source = """
        {
            FormalDefinition(
                "increment",
                parameters: [.value("value")],
                body: value + 1
            )
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "increment",
                parameters: [.value("value")],
                body: .add(.variable("value"), .int(1))
            )
        ])
    }

    @Test func formalDefinitionRetainsTypedFiniteFunctionBodies() throws {
        let source = """
        {
            FormalDefinition(
                "InitialState",
                parameters: [],
                body: Function<Key, Int>.mapping { _ in 0 }.raw
            )
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure,
            sourceTypes: .init(enums: [parserTestEnum("Key", finiteValues: [.string("k1"), .string("k2")])]))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let definition = try #require(parsed.formalOperatorDefinitions.first)
        #expect(definition.name == "InitialState")
        #expect(definition.parameters.isEmpty)
        guard case .functionLiteral(let domain, _, let body) = definition.body else {
            Issue.record("Expected a finite function body")
            return
        }
        #expect(domain == .setLiteral([.value(.string("k1")), .value(.string("k2"))]))
        #expect(body == .int(0))
    }

    @Test func parsesHigherOrderOperatorArgumentsIntoTheSourceModel() throws {
        let source = """
        {
            FormalDefinition(
                "applyTwice",
                parameters: [.operator("operation", arity: 1), .value("initial")],
                body: StateExpr.operatorApplication(
                    .reference("operation", arity: 1),
                    [
                        .value(StateExpr.operatorApplication(
                            .reference("operation", arity: 1),
                            [.value(StateExpr.variable("initial"))]
                        ))
                    ]
                )
            )
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "applyTwice",
                parameters: [.operator("operation", arity: 1), .value("initial")],
                body: .operatorApplication(
                    .reference("operation", arity: 1),
                    [.value(.operatorApplication(
                        .reference("operation", arity: 1),
                        [.value(.variable("initial"))]
                    ))]
                )
            )
        ])
    }

    @Test func algorithmTypedFormalDefinitionParsesWithClosureBinders() throws {
        let source = """
        {
            Algorithm("Formal", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                FormalDefinition("same", taking: Int.self, Int.self) { ballot, value in
                    ballot == value
                }
                Do(TestControlLabel.stop) {
                    Assert(count == 0)
                    Stop()
                }
            })
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Formal", closure,
            sourceTypes: .init(enums: [parserTestEnum(
                "TestControlLabel", cases: ["stop": .string("stop")]
            )]))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.sourceAlgorithms.first?.model.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "same",
                parameters: [.value("value0", typeName: "Int"), .value("value1", typeName: "Int")],
                body: .equal(.variable("value0"), .variable("value1"))
            )
        ])
        let built = Algorithm("Formal", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            FormalDefinition("same", taking: Int.self, Int.self) { left, right in left == right }
            Do(TestControlLabel.stop) {
                Assert(count == 0)
                Stop()
            }
        })
        let parsedCompilation = try parsed.compile()
        let builderCompilation = try TLASpec("Formal") { built }.compile()
        #expect(parsedCompilation.identity == builderCompilation.identity)
    }

    @Test func typedFormalDefinitionParsesClosureBindersAndLocalRecursion() throws {
        let source = """
        {
            FormalDefinition("SafeAt", taking: Int.self, Int.self) { ballot, limit in
                LetRec("SA", over: IntRange(0, through: limit), taking: Int.self, { recursion, current in
                    If(current == 0, then: true, else: recursion(current.expr - 1))
                }, in: { recursion in recursion(ballot.expr) })
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        guard let definition = parsed.formalOperatorDefinitions.first else {
            Issue.record("Expected one typed formal definition.")
            return
        }
        #expect(definition.parameters == [.value("value0", typeName: "Int"), .value("value1", typeName: "Int")])
        guard case .letIn(let operators, let body) = definition.body else {
            Issue.record("Expected the typed formal body to retain its local recursive LET.")
            return
        }
        #expect(operators.map(\.name) == ["SA"])
        #expect(operators[0].parameters == ["current"])
        #expect(body == .recursiveCall("SA", [.variable("value0")]))
        #expect(try TLASpec(
            name: "TypedFormalRendering",
            variables: [],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [definition]
        ).compile().render().tlaBundle.tla.contains("SA["))
    }

    @Test func typedFormalDefinitionParsesPairLiterals() throws {
        let source = """
        {
            FormalDefinition("PairAt", taking: Int.self, Int.self) { ballot, value in
                Pair.literal(ballot.expr, value.expr) == Pair.literal(0, 1)
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.formalOperatorDefinitions.first?.body == .equal(
            .tupleLiteral([.variable("value0"), .variable("value1")]),
            .value(.tuple([.int(0), .int(1)]))
        ))
    }

    @Test func formalOperatorLambdaAndArgumentKindsRoundTripThroughTheParser() throws {
        let expression = try parseSpecTestExpression("""
        StateExpr.operatorApplication(
            .reference("apply", arity: 2),
            [
                .operator(.lambda(FormalLambda(
                    parameters: ["value"],
                    body: StateExpr.variable("value")
                ))),
                .value(3)
            ]
        )
        """)

        #expect(SpecParser.decodeStateExpr(expression) == .operatorApplication(
            .reference("apply", arity: 2),
            [
                .operator(.lambda(FormalLambda(
                    parameters: ["value"],
                    body: .variable("value")
                ))),
                .value(.int(3))
            ]
        ))
    }

    @Test func explicitlyTypedBinaryFormalCallPreservesItsArguments() throws {
        let built: Expr<Bool> = FormalCall(as: Bool.self, "SafeAt", 3, 5)
        let parsed = SpecParser.decodeTypedFacadeValue(
            try parseSpecTestExpression("FormalCall(as: Bool.self, \"SafeAt\", 3, 5)")
        )

        #expect(parsed == built.stateExpr)
        #expect(built.stateExpr == .operatorApplication(
            .reference("SafeAt", arity: 2), [.value(3), .value(5)]
        ))
    }

    @Test("typed facade closure binders preserve lexical shadowing")
    func typedFacadeBindersPreserveLexicalShadowing() throws {
        let parsed = try #require(SpecParser.decodeTypedFacadeValue(
            try parseSpecTestExpression("""
            ForAll(in: IntRange(1, through: 2)) { outer in
                Exists(in: IntRange(1, through: 2)) { inner in
                    outer.expr + inner.expr > 0
                }
            }
            """)
        ))

        #expect(parsed == .forAll(
            .integerRange(.int(1), .int(2)),
            "outer",
            .exists(
                .integerRange(.int(1), .int(2)),
                "inner",
                .greaterThan(.add(.variable("outer"), .variable("inner")), .int(0))
            )
        ))
    }

    @Test func localOperatorParameterNamesAreAlphaEquivalent() throws {
        let parserTree = canonicalTestSpec(
            variables: [("counter", .value(.int(0)))],
            actions: [(
                "advance",
                .guard_(.letIn([
                    LocalOperator(
                        "Twice",
                        parameters: ["input"],
                        body: .add(.variable("input"), .variable("input"))
                    )
                ], .operatorApplication(
                    .reference("Twice", arity: 1),
                    [.value(.variable("counter"))]
                ))),
                []
            )],
            invariants: []
        )
        let builderTree = canonicalTestSpec(
            variables: [("counter", .value(.int(0)))],
            actions: [(
                "advance",
                .guard_(.letIn([
                    LocalOperator(
                        "Twice",
                        parameters: ["value"],
                        body: .add(.variable("value"), .variable("value"))
                    )
                ], .operatorApplication(
                    .reference("Twice", arity: 1),
                    [.value(.variable("counter"))]
                ))),
                []
            )],
            invariants: []
        )

        #expect(try parserTree.compile().identity == builderTree.compile().identity)
    }

    @Test func parserDiagnosticRetainsSourceSpanAndNoCommitStatus() throws {
        let source = """
        {
            Variable(missing)
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        guard let diagnostic = parsed.diagnostics.first else {
            Issue.record("Expected a diagnostic for the unbound variable declaration")
            return
        }
        #expect(diagnostic.source == "Variable(missing)")
        #expect(diagnostic.expected == "a supported SwiftTLA declaration or expression")
        #expect(diagnostic.actual == "Variable(missing)")
        #expect(diagnostic.sourceSpan.utf8Length == "Variable(missing)".utf8.count)
        #expect(diagnostic.description.contains("Where:") == true)
        #expect(diagnostic.description.contains("Next safe action:") == true)
    }

    @Test func oneArgumentVariableRejectsUnboundReference() throws {
        let source = """
        {
            Variable(missing)
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == ["Variable 'missing' is not bound by a prior Var declaration"])
    }

    @Test func variableReferenceRejectsMalformedDeclaration() throws {
        let source = """
        {
            let phase = Var("phase", 0)
            Variable(phase, bogus: 1)
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.map(\.message) == ["Malformed Variable declaration"])
    }
}
