import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct AlgorithmBuilderParsingTests {
    private var controlLabels: SourceEnum {
        parserTestEnum(
            "TestControlLabel",
            cases: .init(TestControlLabel.allCases.map { .init($0.rawValue, .string($0.rawValue)) })
        )
    }

    private var procedureNames: SourceEnum {
        parserTestEnum("ProcedureName", cases: ["work": .string("work")])
    }

    private func parseAlgorithm(
        named name: String = "Parsed",
        _ closure: ClosureExprSyntax,
        enums: [SourceEnum] = [],
        sourceTypes: SourceTypeMetadata = .init()
    ) -> TLASpec {
        SpecParser.parseSpecClosure(named: name,
            closure,
            sourceTypes: .init(aliases: sourceTypes.aliases, records: sourceTypes.records,
                enums: [controlLabels] + enums + sourceTypes.enums)
        )
    }

    private func compile(
        _ parsed: TLASpec,
        named name: String
    ) throws -> CompiledSpecification {
        var specification = parsed
        specification.name = name
        return try specification.compile()
    }

    private func loweredSource(
        _ parsed: TLASpec,
        named name: String
    ) throws -> TLASpec {
        var specification = parsed
        specification.name = name
        return try specification.loweredSourceModel()
    }

    @Test("conditional parsing rejects an undecodable supplied else branch", arguments: [
        "If(count == 0) { Skip() } else: { unsupportedStatement() }",
        "If(count == 0, else: externalBranch) { Skip() }"
    ])
    func rejectsUndecodableElseBranch(_ statement: String) throws {
        let parsed = parseAlgorithm(try parseSpecTestClosure("""
        {
            Algorithm("Conditional", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.increment) {
                    \(statement)
                }
            })
        }
        """))
        #expect(!parsed.diagnostics.isEmpty)
        #expect(throws: SourceParseDiagnostic.self) { try parsed.compile() }
    }

    @Test("Algorithm Each Do syntax lowers through the ordinary parser AST")
    func parsesBoundedAlgorithm() throws {
        let source = """
        {
            Algorithm("Counter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(Node.all) { node in
                    Do(TestControlLabel.increment) {
                        Await(count < 2)
                        Assign(count, to: count + 1)
                    }
                }
            })
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum("Node", finiteValues: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let compilation = try compile(parsed, named: "Counter")
        let specification = try loweredSource(parsed, named: "Counter")
        #expect(specification.variables.map(\.name) == ["pc", "count"])
        #expect(specification.actions.map(\.name) == ["increment", "Terminating"])
        #expect(specification.actions.first?.bindings.map(\.name) == ["process"])
        #expect(specification.actions.first?.bindings.map(\.values) == [[.string("left"), .string("right")]])
        let increment = try #require(GeneratedMachineAPI(layout: compilation.layout, actions: compilation.semantics.behavior.actions).actions.first {
            $0.swiftIdentifier == "increment"
        })
        #expect(compilation.semantics.behavior.actions.first { $0.id == increment.compiledAction }?.bindings.map(\.generatedSwiftType) == ["Node"])
    }

    @Test("parser retains unsupported procedure declarations for compiler diagnostics")
    func retainsUnsupportedProcedureDeclarationForCompilerDiagnostic() throws {
        let parsed = parseAlgorithm(try parseSpecTestClosure("""
        {
            Algorithm("ProcedureCapability") {
                Procedure(ProcedureName.work) {
                    Do(TestControlLabel.advance) { Return() }
                    WeakFairnessNext()
                }
            }
        }
        """), enums: [procedureNames])

        #expect(parsed.diagnostics.isEmpty)
        do {
            _ = try compile(parsed, named: "ProcedureCapability")
            Issue.record("Expected unsupported procedure fairness to stop compilation.")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidAlgorithmFairnessPlacement)
            #expect(diagnostic.stage == .validation)
            #expect(diagnostic.path == "algorithm.components[0].procedure.components[1]")
        } catch {
            Issue.record("Expected CompilationDiagnostic, received \(error).")
        }
    }

    @Test("Function mapping declarations retain their generated Swift type")
    func preservesFunctionMappingTypeForGeneratedSurface() throws {
        let source = """
        {
            Algorithm("Counter", scoped: { scope in
                let values = scope.sharedVar("values", initial: Function<Node, SetExpr<Int>>.mapping { _ in SetExpr<Int>() })
                Do(TestControlLabel.increment) {
                    Assign(values, to: values)
                    Stop()
                }
            })
        }
        """
        let parsed = parseAlgorithm(
            try parseSpecTestClosure(source),
            enums: [parserTestEnum("Node", finiteValues: [.string("only")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let compilation = try compile(parsed, named: "Counter")
        #expect(compilation.layout.variables.filter { $0.declaration.origin == .source }.map(\.generatedSwiftType) == ["Function<Node, SetExpr<Int>>"])
    }

    @Test("Algorithm parser carries prior shared bindings into mapping initializers")
    func parsesScopedSharedBindingInMappingInitializer() throws {
        let source = """
        {
            Algorithm("MappingScope", scoped: { scope in
                let enabled = scope.sharedVar("enabled", initial: true)
                let values = scope.sharedVar("values", initial: Function<Node, Int>.mapping { _ in
                    If(enabled == true, then: 1, else: 0)
                })
                Do(TestControlLabel.done) { Stop() }
            })
        }
        """
        let parsed = parseAlgorithm(
            try parseSpecTestClosure(source),
            enums: [parserTestEnum("Node", finiteValues: [.string("only")])]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(try loweredSource(parsed, named: "MappingScope").variables.map(\.name) == ["pc", "enabled", "values"])
    }

    @Test("Algorithm parser carries shared bindings into Each bodies")
    func parsesScopedSharedBindingInEachBody() throws {
        let source = """
        {
            Algorithm("EachScope", scoped: { scope in
                let enabled = scope.sharedVar("enabled", initial: true)
                Each(Node.all) { _ in
                    Do(TestControlLabel.advance) {
                        Await(enabled == true)
                        Stop()
                    }
                }
            })
        }
        """
        let parsed = parseAlgorithm(
            try parseSpecTestClosure(source),
            enums: [parserTestEnum("Node", finiteValues: [.string("only")])]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(try loweredSource(parsed, named: "EachScope").actions.map(\.name) == ["advance", "Terminating"])
    }

    @Test("Algorithm parser carries shared bindings into macro declarations")
    func parsesScopedSharedBindingInMacroDeclaration() throws {
        let source = """
        {
            Algorithm("MacroScope", scoped: { scope in
                let enabled = scope.sharedVar("enabled", initial: true)
                let waitUntilEnabled = Macro { (value: MacroParameter<Bool>) in
                    Await(enabled == value.expr)
                }
                Do(TestControlLabel.advance) { waitUntilEnabled(enabled) }
            })
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(try loweredSource(parsed, named: "MacroScope").actions.map(\.name) == ["advance", "Terminating"])
    }

    @Test("Algorithm parser resolves enum cases through lexical and declared type scope", arguments: ["current", "selectedNode"])
    func parsesScopedEnumCases(localName: String) throws {
        let source = """
        {
            Algorithm("EnumScope", scoped: { scope in
                let phases = scope.sharedVar("phases", initial: Function<Node, Phase>.mapping { node in
                    If(node == Node.one, then: .ready, else: .done)
                })
                Each(Worker.all, scoped: { _, scope in
                    let current: LocalVariable<Node> = scope.localVar("\(localName)", initial: .one)
                    Do(TestControlLabel.advance) {
                        Await(phases[current] == .ready)
                        Stop()
                    }
                })
            })
        }
        """
        let parsed = parseAlgorithm(
            try parseSpecTestClosure(source),
            enums: [
                parserTestEnum(
                    "Node",
                    cases: ["one": .string("n1"), "two": .string("n2")],
                    finiteValues: [.string("n1"), .string("n2")]
                ),
                parserTestEnum(
                    "Worker",
                    cases: ["one": .string("w1")],
                    finiteValues: [.string("w1")]
                ),
                parserTestEnum(
                    "Phase",
                    cases: ["ready": .string("ready"), "done": .string("done")]
                ),
                parserTestEnum(
                    "OtherPhase",
                    cases: ["ready": .string("otherReady")]
                )
            ]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        _ = try compile(parsed, named: "EnumScope")
    }

    @Test("Algorithm parser lowers tuple append inside a lexical binding")
    func parsesTupleAppendInLet() throws {
        let source = """
        {
            Algorithm("TupleAppend", scoped: { scope in
                let values = scope.sharedVar("values", initial: TupleExpr<Int>())
                Do(TestControlLabel.advance) {
                    Let(values.expr.appending(1)) { extended in
                        Assert(extended.expr.count == 1)
                    }
                    Stop()
                }
            })
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        _ = try compile(parsed, named: "TupleAppend")
    }

    @Test("Algorithm parser lowers tuple count from its bound value type")
    func parsesTupleCount() throws {
        let source = """
        {
            Extends(.sequences)
            Algorithm("TupleCount", scoped: { scope in
                let values = scope.sharedVar("values", initial: TupleExpr<Int>.literal(1, 2))
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.advance) {
                    Assign(count, to: values.count)
                    Stop()
                }
            })
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let module = try compile(parsed, named: "TupleCount").render().tlaBundle.tla
        #expect(module.contains("Len(values)"))
    }

    @Test("Algorithm parser lowers zero-based sequence count through its domain")
    func parsesZeroBasedSequenceCount() throws {
        let source = """
        {
            Algorithm("ZeroBasedCount", scoped: { scope in
                let input = scope.sharedVar("input", in: ZeroBasedSequences(
                    of: SetExpr<Int>.literal(1, 2),
                    lengths: 1...2
                ))
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.advance) {
                    Assign(count, to: input.count)
                    Stop()
                }
            })
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let module = try compile(parsed, named: "ZeroBasedCount").render().tlaBundle.tla
        #expect(module.contains("Cardinality(DOMAIN input)"))
        #expect(!module.contains("Len(input)"))
    }

    @Test("Algorithm parser preserves tuple type through With and quantifier bindings")
    func parsesBoundTupleCounts() throws {
        let source = """
        {
            Extends(.sequences)
            Algorithm("BoundTupleCount", scoped: { scope in
                let pending = scope.sharedVar(
                    "pending",
                    initial: SetExpr<TupleExpr<Int>>.literal(TupleExpr<Int>.literal(1))
                )
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.advance) {
                    With(pending) { tuple in
                        Assign(count, to: tuple.expr.count)
                    }
                    Stop()
                }
                Invariant("TupleLengths") {
                    ForAll(in: pending.expr) { tuple in
                        tuple.expr.count == 1
                    }
                }
            })
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let module = try compile(parsed, named: "BoundTupleCount").render().tlaBundle.tla
        #expect(module.components(separatedBy: "Len(").count == 3)
    }

    @Test("Algorithm parser preserves tuple-valued finite shared domains")
    func parsesTupleValuedSharedDomain() throws {
        let source = """
        {
            Extends(.sequences)
            Algorithm("TupleDomain", scoped: { scope in
                let domain = SetExpr<TupleExpr<Node>>.literal(
                    TupleExpr<Node>.literal(Node.one, Node.two),
                    TupleExpr<Node>.literal(Node.two, Node.one)
                )
                let frontier = scope.sharedVar(
                    "frontier",
                    in: SetExpr<TupleExpr<Node>>.literal(
                        TupleExpr<Node>.literal(Node.one, Node.two),
                        TupleExpr<Node>.literal(Node.two, Node.one)
                    )
                )
                Do(TestControlLabel.advance) {
                    Assert(frontier.count == 2)
                    Stop()
                }
            })
        }
        """
        let nodes = parserTestEnum(
            "Node",
            cases: .init([.init("one", .int(1)), .init("two", .int(2))])
        )
        let parsed = parseAlgorithm(try parseSpecTestClosure(source), enums: [nodes])

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let module = try compile(parsed, named: "TupleDomain").render().tlaBundle.tla
        #expect(module.contains("frontier \\in {<<1, 2>>, <<2, 1>>}"))
    }

    @Test("Specification parser binds a typed local algorithm component")
    func bindsTypedLocalAlgorithmComponent() throws {
        let source = """
        {
            let algorithm: Algorithm = Algorithm("Counter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(count, to: count + 1)
                    Stop()
                }
            })
            algorithm
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.sourceAlgorithms.count == 1)
        let compilation = try compile(parsed, named: "Counter")
        #expect(compilation.description.variables.map(\.name) == ["pc", "count"])
        #expect(compilation.description.actions.map(\.name) == ["increment", "Terminating"])
    }

    @Test("ModelCollection rejects unused arguments and closures")
    func rejectsUnconsumedModelCollectionSyntax() throws {
        let declarations = [
            "ModelCollection(devices, verificationScope: 2, initial: 0, ignored: 1)",
            "ModelCollection(devices, verificationScope: 2, verificationScope: 3, initial: 0)",
            "ModelCollection(devices, verificationScope: 2, initial: 0, initial: 1)",
            "ModelCollection(collection: devices, verificationScope: 2, initial: 0)",
            "ModelCollection(devices, initial: 0, verificationScope: 2)",
            "ModelCollection(devices, verificationScope: 2, initial: 0) { 1 }",
            "ModelCollection(devices, verificationScope: 2, initial: 0) { 1 } otherwise: { 2 }"
        ]
        for declaration in declarations {
            let closure = try parseSpecTestClosure("""
            {
                let devices = CollectionVar<Device, Int>("devices")
                ModelCollection(devices, verificationScope: 2, initial: 0)
                \(declaration)
            }
            """)
            let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
            #expect(parsed.collections.count == 1)
            #expect(parsed.variables.count == 1)
            #expect(parsed.diagnostics.count == 1, "\(declaration): \(parsed.diagnostics)")
        }
    }

    @Test("CollectionAction reports an incomplete declaration")
    func reportsIncompleteCollectionAction() throws {
        let parsed = SpecParser.parseSpecClosure(named: "Parsed",
            try parseSpecTestClosure("{ CollectionAction(\"update\") }")
        )

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "CollectionAction requires a literal name, a declared collection binding, and a builder body."
        ])
    }

    @Test("Variable reports an unsupported initializer")
    func reportsUnsupportedVariableInitializer() throws {
        let parsed = SpecParser.parseSpecClosure(named: "Parsed",
            try parseSpecTestClosure("{ let value = Var<Int>(\"value\"); Variable(value, UnsupportedValue()) }")
        )

        #expect(parsed.diagnostics.map(\.message) == [
            "Variable 'value' requires a supported initial formal value."
        ])
    }

    @Test("Algorithm parser rejects a local declaration scope")
    func rejectsLocalDeclarationScopeAtAlgorithmLevel() throws {
        let source = """
        {
            Algorithm("Counter", scoped: { scope in
                let count = scope.localVar("count", initial: 0)
                Do(TestControlLabel.increment) { Stop() }
            })
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.count == 1)
        #expect(parsed.diagnostics[0].message.contains("Unsupported Algorithm declaration"))
    }

    @Test("Algorithm parser keeps process locals inside their process")
    func rejectsProcessLocalInSiblingProcess() throws {
        let source = """
        {
            Algorithm("SiblingScopes") {
                Each(Node.all, scoped: { node, scope in
                    let local = scope.localVar("local", initial: 0)
                    Do(TestControlLabel.increment) {
                        Await(local == 0)
                        Stop()
                    }
                })
                Each(Node.all) { node in
                    Do(TestControlLabel.done) {
                        Await(local == 0)
                        Stop()
                    }
                }
            }
        }
        """

        let parsed = parseAlgorithm(
            try parseSpecTestClosure(source),
            enums: [parserTestEnum("Node", finiteValues: [.string("only")])]
        )

        #expect(parsed.sourceAlgorithms.isEmpty)
        #expect(parsed.diagnostics.count == 1)
    }

    @Test("Algorithm properties cannot read an unbound process-local name")
    func rejectsProcessLocalOutsideProcess() throws {
        let source = """
        {
            Algorithm("LocalProperty") {
                Each(Node.all, scoped: { node, scope in
                    let local = scope.localVar("local", initial: 0)
                    Do(TestControlLabel.done) { Stop() }
                })
                Invariant("LeakedLocal") { local == 0 }
            }
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source),
            enums: [parserTestEnum("Node", finiteValues: [.string("only")])])
        #expect(parsed.sourceAlgorithms.isEmpty)
        #expect(parsed.diagnostics.count == 1)
    }

    @Test("Algorithms inherit renamed state from the enclosing specification")
    func inheritsEnclosingStateBindings() throws {
        let source = """
        { scope in
            let count = scope.sharedVar("storedCount", initial: 0)
            Algorithm("Counter") {
                Do(TestControlLabel.increment) {
                    Assign(count, to: count + 1)
                    Stop()
                }
            }
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))
        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.sourceAlgorithms.count == 1)
        _ = try parsed.compile()
    }

    @Test("Specification parser binds root scoped shared declarations")
    func parsesRootScopedSharedDeclaration() throws {
        let source = """
        { scope in
            let count = scope.sharedVar("count", initial: 0)
            Invariant("Nonnegative") { count >= 0 }
        }
        """

        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.map(\.name) == ["count"])
        #expect(parsed.invariants.map(\.name) == ["Nonnegative"])
    }

    @Test("Unknown Algorithm identifiers are rejected as unregistered")
    func unknownAlgorithmIdentifierIsRejectedAsUnregistered() throws {
        let source = """
        {
            Algorithm("Unsupported") {
                UnsupportedAlgorithmConstruct()
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.actions.isEmpty)
        #expect(parsed.sourceAlgorithms.isEmpty)
        let diagnostic = try #require(parsed.diagnostics.first)
        #expect(diagnostic.code == .unsupportedLanguageConstruct)
        #expect(diagnostic.sourcePath == ["Algorithm", "UnsupportedAlgorithmConstruct"])
        #expect(diagnostic.expected == "a supported Algorithm declaration")
        #expect(diagnostic.actual == "unknown Algorithm declaration 'UnsupportedAlgorithmConstruct'")
        #expect(diagnostic.nextSafeAction == "Use a declaration supported by Algorithm.")
    }

    @Test("Unknown Algorithm statement calls retain source diagnostics at every nesting depth")
    func unknownAlgorithmStatementCallsAreRejectedAsUnregisteredInNestedBodies() throws {
        let cases = [
            (
                name: "UnknownInDo",
                body: """
                Do(TestControlLabel.advance) {
                    UnknownInDo()
                }
                """
            ),
            (
                name: "UnknownInIf",
                body: """
                Do(TestControlLabel.advance) {
                    If(true) {
                        UnknownInIf()
                    }
                }
                """
            ),
            (
                name: "UnknownInWith",
                body: """
                Do(TestControlLabel.advance) {
                    With(SetExpr<Int>.literal(1)) { value in
                        UnknownInWith()
                    }
                }
                """
            )
        ]

        for testCase in cases {
            let source = """
            {
                Algorithm("Nested") {
                    \(testCase.body)
                }
            }
            """
            let parsed = parseAlgorithm(try parseSpecTestClosure(source))

            #expect(parsed.sourceAlgorithms.isEmpty)
            let diagnostic = try #require(parsed.diagnostics.first)
            #expect(diagnostic.code == .unsupportedLanguageConstruct)
            #expect(diagnostic.sourcePath == ["Algorithm", testCase.name])
            #expect(diagnostic.sourceSpan.location != .unavailable)
            #expect(diagnostic.expected == "a supported Algorithm declaration")
            #expect(diagnostic.actual == "unknown Algorithm declaration '\(testCase.name)'")
            #expect(diagnostic.nextSafeAction == "Use a declaration supported by Algorithm.")
            #expect(!parsed.diagnostics.contains { $0.message.contains("Unsupported Algorithm declaration") })
        }
    }

    @Test("Formal expression closures stay outside Algorithm declaration parsing")
    func formalExpressionClosuresDoNotBecomeAlgorithmDeclarations() throws {
        let source = """
        {
            Algorithm("FormalClosureBoundary") { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.advance) {
                    let imported: Expr<Int> = ModuleCall("Instance", "Value", count)
                    Assign(count, to: imported)
                }
                StateConstraint(ForAll(in: SetExpr<Int>.literal(0, 1)) { value in value >= 0 })
                Invariant("Bounded") {
                    ForAll(in: SetExpr<Int>.literal(0, 1)) { value in value >= count }
                }
                FormalDefinition("SafeAt", taking: Int.self, Int.self) { ballot, limit in
                    LetRec("SA", over: IntRange(0, through: limit), taking: Int.self, { recursion, current in
                        If(current == 0, then: true, else: recursion(current.expr - 1))
                    }, in: { recursion in recursion(ballot.expr) })
                }
            }
        }
        """

        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.sourceAlgorithms.map(\.model.name) == ["FormalClosureBoundary"])
    }

    @Test("Unsupported action source does not create a placeholder action", arguments: [false, true])
    func rejectsUnsupportedActionWithoutSemanticPlaceholder(_ parameterized: Bool) throws {
        let parameters = parameterized ? #", parameters: [ActionParameter("member", values: [1, 2])]"# : ""
        let source = """
        {
            Action("unsupported"\(parameters)) {
                let value = 1
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "\(parameterized ? "Parameterized action" : "Action") 'unsupported' contains an unsupported action expression."
        ])
    }

    @Test("Unsupported top-level source is diagnosed")
    func rejectsUnsupportedTopLevelSource() throws {
        let source = """
        {
            UnsupportedDeclaration()
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.map(\.message) == [
            "Specification body contains an unsupported declaration 'UnsupportedDeclaration'."
        ])
    }

    @Test("Unsupported local source is diagnosed")
    func rejectsUnsupportedLocalSource() throws {
        let source = """
        {
            let value = 1
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Specification body contains an unsupported local declaration."
        ])
    }

    @Test("Nonliteral for-loop ranges are diagnosed")
    func rejectsNonliteralForLoopRange() throws {
        let source = """
        {
            for index in 1...limit {
                Action("step") { flag.becomes(true) }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Specification for-loop requires a literal closed integer range."
        ])
    }

    @Test("Unsupported for-loop body source is diagnosed")
    func rejectsUnsupportedForLoopBodySource() throws {
        let source = """
        {
            for index in 1...1 {
                let value = index
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Specification for-loop body contains an unsupported item."
        ])
    }

    @Test("Supplied fairness must decode instead of defaulting to none", arguments: [
        "externalFairness", "chooseFairness()", "true", ".unsupported"
    ])
    func rejectsUndecodableFairness(_ fairness: String) throws {
        for declaration in [
            "Algorithm(\"InvalidFairness\", fairness: \(fairness)) {}",
            "Algorithm(\"InvalidFairness\") { Each(Node.all, fairness: \(fairness)) { node in } }"
        ] {
            let parsed = parseAlgorithm(
                try parseSpecTestClosure("{ \(declaration) }"),
                enums: [parserTestEnum("Node", finiteValues: [.string("one")])]
            )
            #expect(parsed.diagnostics.contains { $0.message.contains("fairness must be") })
            #expect(throws: SourceParseDiagnostic.self) { try parsed.compile() }
        }
    }

    @Test("parser lowers the mechanical PlusCal statements through the shared IR")
    func parsesMechanicalPlusCalStatements() throws {
        let source = """
        {
            Algorithm("Counter") { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(Node.all, fairness: .strong) { node in
                    While(TestControlLabel.increment, count < 2) {
                        When(count >= 0)
                        With(Node.all) { choice in
                            Assert(choice == node)
                            Assign(count, to: count + 1)
                        }
                    }
                }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum("Node", finiteValues: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "Counter")
        #expect(specification.invariants.map(\.name) == ["__pcal_assert_0", "__pcal_assert_1"])
        #expect(specification.fairness == [
            .strongFairnessActionCall(.init(name: "increment", arguments: [.string("left")])),
            .strongFairnessActionCall(.init(name: "increment", arguments: [.string("right")]))
        ])
    }

    @Test("Algorithm parser decodes each temporal declaration")
    func parsesAlgorithmTemporalDeclarations() throws {
        let source = """
        {
            Algorithm("Temporal") { scope in
                let value = scope.sharedVar("value", initial: 0)
                Do(TestControlLabel.advance) {
                    Assign(value, to: value + 1)
                }
                LeadsTo("progress", value == 0, value > 0)
                Eventually("eventual", value > 0)
                Always("safe", value >= 0)
                AlwaysEventually("recurs", value > 0)
                EventuallyAlways("settles", value >= 0)
            }
        }
        """
        let parsed = parseAlgorithm(try parseSpecTestClosure(source))

        #expect(parsed.diagnostics.isEmpty)
        #expect(try loweredSource(parsed, named: "Temporal").temporalProperties.map(\.name) == [
            "progress", "eventual", "safe", "recurs", "settles"
        ])
    }

    @Test("Algorithm parser preserves process-bound formal lambda meaning in both bundles")
    func preservesProcessScopedFormalLambdaMeaning() throws {
        let source = """
        {
            Algorithm("ScopedFormalLambda") { scope in
                let counters = scope.sharedVar("counters", initial: Function<Worker, Int>.literal(
                    (.left, 0),
                    (.right, 0)
                ))
                Each(Worker.all) { worker in
                    Do(TestControlLabel.advance) {
                        Assign(counters, to: counters.updating(worker, to: Expr<Int>(
                            StateExpr.operatorApplication(
                                .lambda(FormalLambda(
                                    parameters: ["value"],
                                    body: StateExpr.variable("value") + 1
                                )),
                                [.value(counters[worker].raw)]
                            )
                        )))
                    }
                }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum(
                "Worker",
                cases: ["left": .string("left"), "right": .string("right")],
                finiteValues: [.string("left"), .string("right")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "ScopedFormalLambda")
        #expect(specification.actions.map(\.name) == ["advance", "Terminating"])
        let compilation = try specification.compile()
        let direct = try compilation.render().tlaBundle.root.tla
        let authored = try compilation.render().plusCalBundle().root.tla
        #expect(direct.contains("LET value == counters[_process] IN (value + 1)"))
        #expect(direct.contains("LAMBDA") == false)
        #expect(authored.contains("counters[self] + 1"))
        #expect(authored.contains("LAMBDA") == false)
    }

    @Test("formal operator parsing failure retains all six diagnostic fields")
    func malformedFormalLambdaRetainsSixFieldDiagnostic() throws {
        let source = """
        {
            Algorithm("MalformedFormalLambda") { scope in
                let counter = scope.sharedVar("counter", initial: 0)
                Do(TestControlLabel.advance) {
                    Assign(counter, to: Expr<Int>(StateExpr.operatorApplication(
                        .lambda(FormalLambda(parameters: [], body: .int(1))),
                        [.value(counter.expr.raw)]
                    )))
                }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)
        guard let diagnostic = parsed.diagnostics.first else {
            Issue.record("Expected a malformed formal-lambda diagnostic")
            return
        }

        #expect(diagnostic.description.contains("What failed:") == true)
        #expect(diagnostic.description.contains("Where:") == true)
        #expect(diagnostic.description.contains("Expected:") == true)
        #expect(diagnostic.description.contains("Actual:") == true)
        #expect(diagnostic.description.contains("Next safe action:") == true)
    }

    @Test("parser lowers ordered multi-source With bindings")
    func parsesThreeIndependentWithBindings() throws {
        let source = """
        {
            Algorithm("ThreeWith") { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                Do(TestControlLabel.choose) {
                    With(
                        SetExpr<Int>.literal(1, 2),
                        SetExpr<Int>.literal(10),
                        SetExpr<Int>.literal(100, 200)
                    ) { first, second, third in
                        Assign(selected, to: first.expr + second.expr + third.expr)
                    }
                }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "ThreeWith")
        let rendered = try specification.compile().render().tlaBundle.tla
        #expect(rendered.components(separatedBy: "\\E ").count == 4)
    }

    @Test("parser preserves a bounded statement macro through compilation")
    func parsesStatementMacro() throws {
        let source = """
        {
            Algorithm("MacroLock") { scope in
                let lock = scope.sharedVar("lock", initial: 1)
                let acquire = Macro { (value: MacroParameter<Int>) in
                    Await(value == 1)
                    Assign(value, to: 0)
                }
                Each(Node.all) { _ in
                    Do(TestControlLabel.acquire) { acquire(lock) }
                }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum("Node", finiteValues: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "MacroLock")
        #expect(specification.actions.map(\.name) == ["acquire", "Terminating"])
        #expect(try specification.compile().render().tlaBundle.tla.contains("lock"))
    }

    @Test("parser expands every statement macro parameter in caller scope")
    func parsesTwoParameterStatementMacro() throws {
        let source = """
        {
            Algorithm("CopyValue") { scope in
                let destination = scope.sharedVar("destination", initial: 0)
                let source = scope.sharedVar("source", initial: 7)
                let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                    Assign(target, to: value.expr)
                }
                Do(TestControlLabel.copy) { copy(destination, source) }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "CopyValue")
        let rendered = try specification.compile().render().tlaBundle.tla
        #expect(rendered.contains("destination' = source"))
        #expect(rendered.contains("__pcal_macro_parameter") == false)
    }

    @Test("parser retains formal expression macro arguments")
    func parsesExpressionStatementMacroArguments() throws {
        let source = """
        {
            Algorithm("OffsetValue") { scope in
                let destination = scope.sharedVar("destination", initial: 0)
                let source = scope.sharedVar("source", initial: 7)
                let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                    Assign(target, to: value.expr)
                }
                Do(TestControlLabel.copy) { copy(destination, source.expr + 1) }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "OffsetValue")
        #expect(try specification.compile().render().tlaBundle.tla.contains("destination' = (source + 1)"))
    }

    @Test("parser retains typed pair projections and formal calls in a statement macro")
    func parsesTypedPairStatementMacro() throws {
        let source = """
        {
            Algorithm("PairVote") {
                FormalDefinition("SafeAt", taking: Int.self, Int.self) { ballot, value in
                    ballot >= 0 && value >= 0
                }
                let vote = Macro { (pair: MacroParameter<Pair<Int, Int>>) in
                    When(
                        pair.expr.first() >= 0
                            && FormalCall(as: Bool.self, "SafeAt", pair.expr.first(), pair.expr.second())
                    )
                }
                Do(TestControlLabel.vote) { vote(Pair.literal(1, 2)) }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "PairVote")
        #expect(try specification.compile().render().tlaBundle.tla.contains(
            "SafeAt(<<1, 2>>[1], <<1, 2>>[2])"
        ))
    }

    @Test("parser rejects an expression used for a macro assignment target")
    func diagnosesExpressionMacroAssignmentTarget() throws {
        let source = """
        {
            Algorithm("InvalidMacroTarget") { scope in
                let destination = scope.sharedVar("destination", initial: 0)
                let write = Macro { (target: MacroParameter<Int>) in
                    Assign(target, to: 1)
                }
                Do(TestControlLabel.write) { write(destination.expr + 1) }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.actions.isEmpty)
        let diagnostic = parsed.diagnostics.first?.message ?? ""
        #expect(diagnostic.contains("What failed: statement macro 'write' assigns through parameter"))
        #expect(diagnostic.contains("Expected a formal variable assignment target"))
        #expect(diagnostic.contains("Next safe action"))
    }

    @Test("source model compiles procedure bindings to deterministic formal slots", arguments: ["offset", "adjustment"])
    func parsesTypedProcedureBindings(localName: String) throws {
        let source = """
        {
            Algorithm("ProcedureSource") { scope in
                let output = scope.sharedVar("output", initial: 0)
                Procedure(ProcedureName.work, parameters: Int.self, scoped: { value, scope in
                    let offset = scope.localVar("\(localName)", initial: 1)
                    Do(TestControlLabel.enter) {
                        Await(value.expr >= 0)
                        Assign(output, to: value.expr + offset.expr)
                        Return()
                    }
                })
                Do(TestControlLabel.start) { Call(ProcedureName.work, with: 7) }
                Do(TestControlLabel.finished) { Stop() }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure, enums: [procedureNames])

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "ProcedureSource")
        #expect(specification.variables.contains { $0.name == "parameter0" })
        #expect(specification.actions.contains { $0.name == "procedure.work.enter" })
    }

    @Test("statement macro arity diagnostics identify the declaration and safe repair")
    func diagnosesStatementMacroArity() throws {
        let source = """
        {
            Algorithm("BadMacroCall") { scope in
                let destination = scope.sharedVar("destination", initial: 0)
                let source = scope.sharedVar("source", initial: 7)
                let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                    Assign(target, to: value.expr)
                }
                Do(TestControlLabel.copy) { copy(destination) }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.first?.message.contains("Statement macro 'copy' expects 2 arguments but received 1.") == true)
    }

    @Test("parser expands a parameterless statement macro")
    func parsesParameterlessStatementMacro() throws {
        let source = """
        {
            Algorithm("ParameterlessMacro") { scope in
                let count = scope.sharedVar("count", initial: 0)
                let increment = Macro {
                    Assign(count, to: count + 1)
                }
                Do(TestControlLabel.increment) { increment() }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "ParameterlessMacro")
        #expect(try specification.compile().render().tlaBundle.tla.contains("count' = (count + 1)"))
    }

    @Test("parser retains a filtered formal function initial domain")
    func parsesFilteredFunctionInitialDomain() throws {
        let source = """
        {
            Algorithm("FunctionDomain") { scope in
                let successors = scope.sharedVar("successors", in: Where(
                    Functions(from: Node.all, to: Subsets(of: SetExpr<Node>.literal(.first, .second)))
                ) { successor in
                    ForAll(Node.all) { node in
                        successor[node].cardinality == 1
                    }
                })
                Do(TestControlLabel.done) { Stop() }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum(
                "Node",
                cases: ["first": .string("first"), "second": .string("second")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let compilation = try compile(parsed, named: "FunctionDomain")
        let successors = try #require(try loweredSource(parsed, named: "FunctionDomain").variables.first { $0.name == "successors" })
        let variable = try #require(compilation.layout.variables.first { $0.declaration.name == successors.name })
        #expect(variable.generatedSwiftType == "Function<Node, SetExpr<Node>>")
        guard case .memberOf = successors.initialization else {
            Issue.record("Expected successors to retain its initial domain")
            return
        }
        #expect(try compilation.render().tlaBundle.tla.contains("Cardinality"))
    }

    @Test("Algorithm parser decodes scoped function-set invariants")
    func parsesScopedFunctionSetInvariant() throws {
        let source = """
        {
            Algorithm("FunctionSetInvariant", scoped: { scope in
                let values = scope.sharedVar("values", initial: Function<Node, Int>.mapping { _ in 0 })
                let grouped = scope.sharedVar("grouped", initial: Function<Node, SetExpr<Node>>.mapping { _ in SetExpr<Node>() })
                let members = scope.sharedVar("members", initial: SetExpr<Node>())
                Do(TestControlLabel.done) { Stop() }
                Invariant("TypeOK") {
                    Functions(from: Node.all, to: SetExpr<Int>.literal(0, 1)).contains(values.expr)
                        && members.isSubset(of: SetExpr<Node>.literal(.only))
                        && Functions(
                            from: Node.all,
                            to: Subsets(of: SetExpr<Node>.literal(.only))
                        ).contains(grouped.expr)
                }
            })
        }
        """
        let parsed = parseAlgorithm(
            try parseSpecTestClosure(source),
            enums: [parserTestEnum(
                "Node",
                cases: ["only": .string("only")],
                finiteValues: [.string("only")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(try loweredSource(parsed, named: "FunctionSetInvariant").invariants.map(\.name) == ["TypeOK"])
    }

    @Test("parser retains a typed record-valued function comprehension")
    func parsesRecordFunctionComprehension() throws {
        let source = """
        {
            Algorithm("RecordFunction") { scope in
                let cars = scope.sharedVar("cars", initial: Function<Car, Record<Model.CarRecord>>.mapping { _ in
                    Record.literal(
                        .init(Model.CarRecord.floor, 4),
                        .init(Model.CarRecord.door, .closed)
                    )
                })
                Do(TestControlLabel.hold) { Assign(cars, to: cars.expr) }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [
                parserTestEnum("Door", cases: ["closed": .string("closed")]),
                parserTestEnum("Car", finiteValues: [.string("north"), .string("south")])
            ],
            sourceTypes: .init(records: ["CarRecord": [
                .init(sourceName: "floor", name: "floor", swiftType: "Int"),
                .init(sourceName: "door", name: "door", swiftType: "Door")
            ]])
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "RecordFunction")
        let carsDeclaration = try #require(specification.variables.first { $0.name == "cars" })
        guard case .expression(let initializer) = carsDeclaration.initialization,
              case .function(let cars) = try evaluateClosed(initializer) else {
            Issue.record("Expected cars to retain a formal finite function")
            return
        }
        #expect(cars.count == 2)
        #expect(cars.values.allSatisfy { value in
            guard case .record(let fields) = value else { return false }
            return fields.value(named: "floor") == .int(4)
                && fields.value(named: "door") == .string("closed")
        })
    }

    @Test("parser retains an empty typed set in a function comprehension")
    func parsesEmptySetFunctionComprehension() throws {
        let source = """
        {
            Algorithm("Votes") { scope in
                let votes = scope.sharedVar("votes", initial: Function<Acceptor, SetExpr<Int>>.mapping { _ in SetExpr() })
                Do(TestControlLabel.hold) { Assign(votes, to: votes.expr) }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum("Acceptor", finiteValues: [.string("a1"), .string("a2")])]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "Votes")
        let votesDeclaration = try #require(specification.variables.first { $0.name == "votes" })
        guard case .expression(let initializer) = votesDeclaration.initialization,
              case .function(let votes) = try evaluateClosed(initializer) else {
            Issue.record("Expected votes to retain a formal finite function")
            return
        }
        #expect(votes == [.string("a1"): .set([]), .string("a2"): .set([])])
    }

    @Test("parser retains a typed finite function literal with its bound key")
    func parsesTypedFunctionLiteral() throws {
        let source = """
        {
            Algorithm("FiniteFunction") {
                Each(Node.all) { node in
                    Do(TestControlLabel.hold) {
                        let successor = Function<Node, Node>.literal(
                            (Node.one, Node.two),
                            (Node.two, Node.one)
                        )
                        When(successor[node] == Node.two)
                    }
                }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum(
                "Node",
                cases: ["one": .int(1), "two": .int(2)]
            )]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "FiniteFunction")
        #expect(try specification.compile().render().tlaBundle.tla.contains("CASE"))
    }

    @Test("source model compiles a static formal selection")
    func parsesStaticFormalSelection() throws {
        let source = """
        {
            Algorithm("StaticChoice") { scope in
                let selected = Select(
                    from: SetExpr<Int>.literal(1, 2, 3),
                    matching: { value in value.expr % 2 == 0 }
                )
                let current: SharedVariable<Int> = scope.sharedVar("current", initial: selected)
                Do(TestControlLabel.done) { Stop() }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "StaticChoice")
        #expect(specification.variables.first { $0.name == "current" }?.initialization == .value(.int(2)))
    }

    @Test("parser expands a statement macro with the current process identifier")
    func parsesStatementMacroWithProcessIdentifier() throws {
        let source = """
        {
            Algorithm("MacroProcess") { scope in
                let marked = scope.sharedVar("marked", initial: Function<Node, Bool>.literal((Node.left, false), (Node.right, false)))
                let mark = Macro { (node: MacroParameter<Node>) in
                    Assign(marked, to: marked.updating(node, to: true))
                }
                Each(Node.all) { node in
                    Do(TestControlLabel.mark) { mark(node) }
                }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum(
                "Node",
                cases: ["left": .string("left"), "right": .string("right")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "MacroProcess")
        let action = try #require(try specification.compile().semantics.behavior.actions.first)
        #expect(action.bindings.map(\.sourceName).contains("process"))
    }

    @Test("Do, While, and Goto use their declared label raw values")
    func parsesDeclaredAlgorithmLabels() throws {
        let source = """
        {
            Algorithm("RawLabel") {
                Do(Step.start) { Goto(Step.finish) }
                While(Step.loop, true) { Goto(Step.finish) }
                Do(Step.finish) { Stop() }
            }
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure,
            sourceTypes: .init(enums: [parserTestEnum("Step", cases: [
                "start": .string("Begin"),
                "loop": .string("Repeat"),
                "finish": .string("Finish")
            ])]))

        #expect(parsed.diagnostics.isEmpty)
        let algorithm = try #require(parsed.sourceAlgorithms.first?.model)
        #expect(algorithm.sequentialSteps.map(\.label.name) == ["Begin", "Repeat", "Finish"])
        #expect(algorithm.sequentialSteps[0].statements == [.goto(.init(name: "Finish"))])
        #expect(algorithm.sequentialSteps[1].statements == [.goto(.init(name: "Finish"))])
        _ = try compile(parsed, named: "RawLabel")
    }

    @Test("Do, While, and Goto reject labels outside a registered enum")
    func rejectsUnboundAlgorithmLabels() throws {
        let invalidLabels = [
            #""label""#,
            ".advance",
            "Unknown.advance",
            "TestControlLabel.missing"
        ]
        for construct in ["Do", "While", "Goto"] {
            for label in invalidLabels {
                let statement: String
                switch construct {
                case "Do": statement = "Do(\(label)) { Stop() }"
                case "While": statement = "While(\(label), true) { Stop() }"
                default: statement = "Do(TestControlLabel.advance) { Goto(\(label)) }"
                }
                let parsed = parseAlgorithm(try parseSpecTestClosure("""
                {
                    Algorithm("InvalidLabel") {
                        \(statement)
                    }
                }
                """))

                #expect(parsed.sourceAlgorithms.isEmpty, "\(construct) accepted \(label)")
                let diagnostic = try #require(parsed.diagnostics.first)
                #expect(diagnostic.message.contains(
                    "Algorithm control label '\(label)' must be a qualified case of a registered String-backed enum."
                ))
            }
        }
    }

    @Test("Procedure and Call reject names outside a registered enum")
    func rejectsUnboundProcedureNames() throws {
        let invalidNames = [
            (#""work""#, "procedure name '\"work\"' must be a qualified enum case."),
            (".work", "procedure name '.work' must be a qualified enum case."),
            ("Unknown.work", "procedure-name enum 'Unknown' is not registered."),
            ("ProcedureName.missing", "procedure name 'missing' is not declared in registered enum 'ProcedureName'."),
            ("NumberedProcedure.work", "procedure name 'NumberedProcedure.work' must have a String raw value")
        ]
        for construct in ["Procedure", "Call"] {
            for (name, expected) in invalidNames {
                let body: String
                if construct == "Procedure" {
                    body = "Procedure(\(name)) { Do(TestControlLabel.advance) { Return() } }"
                } else {
                    body = """
                    Procedure(ProcedureName.work) { Do(TestControlLabel.advance) { Return() } }
                    Do(TestControlLabel.start) { Call(\(name)) }
                    """
                }
                let parsed = parseAlgorithm(
                    try parseSpecTestClosure("""
                    {
                        Algorithm("InvalidProcedureName") {
                            \(body)
                        }
                    }
                    """),
                    enums: [
                        procedureNames,
                        parserTestEnum("NumberedProcedure", cases: ["work": .int(1)])
                    ]
                )

                #expect(parsed.sourceAlgorithms.isEmpty, "\(construct) accepted \(name)")
                let diagnostic = try #require(parsed.diagnostics.first)
                #expect(diagnostic.message.contains("\(construct) \(expected)"))
            }
        }
    }

    @Test("parsed algorithms compile their declared process owner")
    func parsedAlgorithmCompilesDeclaredProcessOwner() throws {
        let source = """
        {
            Algorithm("Counter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(ParserNode.all) { _ in
                    Do(TestControlLabel.increment) {
                        Await(count < 2)
                        Assign(count, to: count + 1)
                    }
                }
            })
        }
        """
        let closure = try parseSpecTestClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enums: [parserTestEnum(
                "ParserNode",
                cases: ["left": .string("left"), "right": .string("right")],
                finiteValues: [.string("left"), .string("right")]
            )]
        )
        let parserSpecification = try loweredSource(parsed, named: "Counter")
        let parserCompilation = try parserSpecification.compile()
        #expect(parserCompilation.description.variables.map(\.name) == ["pc", "count"])
        #expect(parserCompilation.description.actions.map(\.name) == ["increment", "Terminating"])
        #expect(parserCompilation.description.controlLocations.first?.owner == .process(
            algorithm: "Counter",
            declarationOrder: 0,
            typeName: "ParserNode"
        ))
    }

    @Test("parsed shared initializers retain and evaluate their formal expression")
    func parsedSharedInitializerRetainsFormalExpression() throws {
        let closure = try parseSpecTestClosure("""
        { scope in
            let count: SharedVariable<Int> = scope.sharedVar("count", initial: 1 + 2)
        }
        """)
        let parsed = SpecParser.parseSpecClosure(named: "SharedInitializer", closure)
        #expect(parsed.diagnostics.isEmpty)

        let parsedVariable = try #require(try loweredSource(parsed, named: "SharedInitializer").variables.first)

        #expect(parsedVariable.initialization == .expression(.add(.value(.int(1)), .value(.int(2)))))

        let compilation = try parsed.compile()
        let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let count = try #require(TLAStateProjection.Token(validating: "count"))
        #expect(try state.projection(using: compilation.layout).value(for: count) == .int(3))
    }

    @Test("parsed and built literal initializers have one compilation identity")
    func parsedAndBuiltLiteralInitializersShareIdentity() throws {
        let closure = try parseSpecTestClosure("""
        { scope in
            let count = scope.sharedVar("count", initial: 1)
        }
        """)
        let parsed = try SpecParser.parseSpecClosure(named: "LiteralInitializer", closure).compile()
        let built = try TLASpec("LiteralInitializer") { scope in
            let _ = scope.sharedVar("count", initial: 1)
        }.compile()

        #expect(parsed.identity == built.identity)
    }

    @Test("parsed initial domains retain state dependencies")
    func parsedInitialDomainsRetainStateDependencies() throws {
        let closure = try parseSpecTestClosure("""
        { scope in
            let limit = scope.sharedVar("limit", initial: 2)
            let choice = scope.sharedVar("choice", in: Where(SetExpr<Int>.literal(1, 2, 3)) { value in
                value <= limit
            })
        }
        """)
        let parsed = SpecParser.parseSpecClosure(named: "DependentInitialDomain", closure)
        let compilation = try parsed.compile()
        let choice = try #require(compilation.layout.testVariableID(named: "choice"))
        let states = try CompiledRuntime(compilation: compilation).initialStates()

        #expect(Set(try states.map {
            try $0.value(for: choice).rendered(using: compilation.layout)
        }) == [.int(1), .int(2)])
    }

    @Test("unsupported variable initializers fail during parsing")
    func rejectsUnsupportedVariableInitializer() throws {
        let closure = try parseSpecTestClosure("""
        {
            let count = Var("count", UnsupportedInitialValue())
        }
        """)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == ["Var requires a supported initial formal value."])
    }
}
