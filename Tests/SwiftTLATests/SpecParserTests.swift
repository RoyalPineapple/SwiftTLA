import Testing
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

// Proves SpecParser's compact decoder produces the same AST as the runtime
// builder for every expression form in the DSL. Each test parses a source
// string and compares the result to the equivalent value built through
// Swift's type system (operator overloads and method calls).

// MARK: - Helpers

private func parseExpression(_ source: String) throws -> ExprSyntax {
    try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
}

private func parseClosure(_ source: String) throws -> ClosureExprSyntax {
    try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
}

private func parserEnum(
    _ typeName: String,
    cases: TLARecord = .init([]),
    finiteValues: [TLAValue]? = nil
) -> ParserEnumDefinition {
    .init(typeName: typeName, cases: cases, finiteValues: finiteValues)
}

@Suite(.serialized) struct StructuralActionReferenceParsingTests {
    @Test("action declarations carry fairness and enabled references")
    func actionDeclarationsCarryReferences() throws {
        let parsed = SpecParser.parseSpecClosure(try parseClosure("""
        {
            let count = Var<Int>("count", initial: 0)
            Variable(count)
            let advance = Action("advance") { count.becomes(count + 1) }
            advance
            WeakFairness(advance)
            StrongFairness(advance)
            Invariant("AdvanceEnabled") { StateExpr.enabled(advance) }
        }
        """))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions.map(\.name) == ["advance"])
        #expect(parsed.fairness == [.weakFairness("advance"), .strongFairness("advance")])
        #expect(parsed.invariants.first?.body == .enabledAction("advance"))
        _ = try parsed.compile(specificationName: "StructuralActionReferences")
    }

    @Test("fairness rejects an undeclared action reference")
    func fairnessRejectsUndeclaredActionReference() throws {
        let parsed = SpecParser.parseSpecClosure(try parseClosure("""
        {
            WeakFairness(missing)
        }
        """))

        #expect(parsed.diagnostics.map(\.message) == [
            "Fairness action reference 'missing' is not bound by a local Action declaration."
        ])
    }
}

@Suite(.serialized) struct AlgorithmBuilderParsingTests {
    private var controlLabels: ParserEnumDefinition {
        parserEnum(
            "TestControlLabel",
            cases: .init(TestControlLabel.allCases.map { .init($0.rawValue, .string($0.rawValue)) })
        )
    }

    private var procedureNames: ParserEnumDefinition {
        parserEnum("ProcedureName", cases: ["work": .string("work")])
    }

    private func parseAlgorithm(
        _ closure: ClosureExprSyntax,
        enumDefinitions: [ParserEnumDefinition] = []
    ) -> ParsedSpecComponents {
        SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [controlLabels] + enumDefinitions
        )
    }

    private func compile(
        _ parsed: ParsedSpecComponents,
        named name: String
    ) throws -> CompiledSpecification {
        try parsed.compile(specificationName: name)
    }

    private func loweredSource(
        _ parsed: ParsedSpecComponents,
        named name: String
    ) throws -> TLASpec {
        try parsed.sourceModel(specificationName: name).loweredSourceModel()
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum("Node", finiteValues: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let compilation = try compile(parsed, named: "Counter")
        let specification = try loweredSource(parsed, named: "Counter")
        #expect(specification.variables.map(\.name) == ["pc", "count"])
        #expect(specification.actions.map(\.name) == ["increment", "Terminating"])
        #expect(specification.actions.first?.bindings.map(\.name) == ["process"])
        #expect(specification.actions.first?.bindings.map(\.values) == [[.string("left"), .string("right")]])
        let increment = try #require(compilation.machineSurfacePlan.actions.first {
            $0.swiftIdentifier == "increment"
        })
        #expect(increment.bindings.map(\.swiftType) == ["Node"])
    }

    @Test("parser retains unsupported procedure declarations for compiler diagnostics")
    func retainsUnsupportedProcedureDeclarationForCompilerDiagnostic() throws {
        let parsed = parseAlgorithm(try parseClosure("""
        {
            Algorithm("ProcedureCapability") {
                Procedure(ProcedureName.work) {
                    Do(TestControlLabel.advance) { Return() }
                    WeakFairnessNext()
                }
            }
        }
        """), enumDefinitions: [procedureNames])

        #expect(parsed.diagnostics.isEmpty)
        do {
            _ = try compile(parsed, named: "ProcedureCapability")
            Issue.record("Expected unsupported procedure fairness to stop compilation.")
        } catch let diagnostic as LanguageCapabilityDiagnostic {
            #expect(diagnostic.construct.construct == .genericFairness)
            #expect(diagnostic.operation == .compilation)
            #expect(diagnostic.sourcePath == ["algorithm", "components[0]", "procedure", "components[1]"])
        } catch {
            Issue.record("Expected LanguageCapabilityDiagnostic, received \(error).")
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
            try parseClosure(source),
            enumDefinitions: [parserEnum("Node", finiteValues: [.string("only")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let compilation = try compile(parsed, named: "Counter")
        #expect(compilation.machineSurfacePlan.variables.map(\.swiftType) == ["Function<Node, SetExpr<Int>>"])
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
            try parseClosure(source),
            enumDefinitions: [parserEnum("Node", finiteValues: [.string("only")])]
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
            try parseClosure(source),
            enumDefinitions: [parserEnum("Node", finiteValues: [.string("only")])]
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
        let parsed = parseAlgorithm(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(try loweredSource(parsed, named: "MacroScope").actions.map(\.name) == ["advance", "Terminating"])
    }

    @Test("Algorithm parser resolves enum cases through lexical and declared type scope")
    func parsesScopedEnumCases() throws {
        let source = """
        {
            Algorithm("EnumScope", scoped: { scope in
                let phases = scope.sharedVar("phases", initial: Function<Node, Phase>.mapping { node in
                    If(node == Node.one, then: .ready, else: .done)
                })
                Each(Worker.all, scoped: { _, scope in
                    let current: LocalVariable<Node> = scope.localVar("current", initial: .one)
                    Do(TestControlLabel.advance) {
                        Await(phases[current] == .ready)
                        Stop()
                    }
                })
            })
        }
        """
        let parsed = parseAlgorithm(
            try parseClosure(source),
            enumDefinitions: [
                parserEnum(
                    "Node",
                    cases: ["one": .string("n1"), "two": .string("n2")],
                    finiteValues: [.string("n1"), .string("n2")]
                ),
                parserEnum(
                    "Worker",
                    cases: ["one": .string("w1")],
                    finiteValues: [.string("w1")]
                ),
                parserEnum(
                    "Phase",
                    cases: ["ready": .string("ready"), "done": .string("done")]
                ),
                parserEnum(
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
        let parsed = parseAlgorithm(try parseClosure(source))

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
        let parsed = parseAlgorithm(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let module = try compile(parsed, named: "TupleCount").renderedTLAModuleBundle().tla
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
        let parsed = parseAlgorithm(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let module = try compile(parsed, named: "ZeroBasedCount").renderedTLAModuleBundle().tla
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
        let parsed = parseAlgorithm(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let module = try compile(parsed, named: "BoundTupleCount").renderedTLAModuleBundle().tla
        #expect(module.components(separatedBy: "Len(").count == 3)
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
        let parsed = parseAlgorithm(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.sourceAlgorithms.count == 1)
        let compilation = try compile(parsed, named: "Counter")
        #expect(compilation.description.variables.map(\.name) == ["pc", "count"])
        #expect(compilation.description.actions.map(\.name) == ["increment", "Terminating"])
    }

    @Test("CollectionAction reports an incomplete declaration")
    func reportsIncompleteCollectionAction() throws {
        let parsed = SpecParser.parseSpecClosure(
            try parseClosure("{ CollectionAction(\"update\") }")
        )

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "CollectionAction requires a literal name, a declared collection binding, and a builder body."
        ])
    }

    @Test("Variable reports an unsupported initializer")
    func reportsUnsupportedVariableInitializer() throws {
        let parsed = SpecParser.parseSpecClosure(
            try parseClosure("{ let value = Var<Int>(\"value\"); Variable(value, UnsupportedValue()) }")
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
        let parsed = parseAlgorithm(try parseClosure(source))

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
            try parseClosure(source),
            enumDefinitions: [parserEnum("Node", finiteValues: [.string("only")])]
        )

        #expect(parsed.sourceAlgorithms.isEmpty)
        #expect(parsed.diagnostics.count == 1)
    }

    @Test("Specification parser binds root scoped shared declarations")
    func parsesRootScopedSharedDeclaration() throws {
        let source = """
        { scope in
            let count = scope.sharedVar("count", initial: 0)
            Invariant("Nonnegative") { count >= 0 }
        }
        """

        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.actions.isEmpty)
        #expect(parsed.sourceAlgorithms.isEmpty)
        let diagnostic = try #require(parsed.diagnostics.first?.capabilityDiagnostic)
        #expect(diagnostic.code == .unsupportedConstruct)
        #expect(diagnostic.construct == .unregistered(sourceName: "UnsupportedAlgorithmConstruct"))
        #expect(diagnostic.operation == .sourceDecoding)
        #expect(diagnostic.sourcePath == ["Algorithm", "UnsupportedAlgorithmConstruct"])
        #expect(diagnostic.expected == "a registered Algorithm declaration with supported source decoding")
        #expect(diagnostic.actual == "unregistered Algorithm declaration 'UnsupportedAlgorithmConstruct'")
        #expect(diagnostic.nextSafeAction == "Use an admitted Algorithm declaration.")
    }

    @Test("Unknown Algorithm statement calls retain capability diagnostics at every nesting depth")
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
            let parsed = parseAlgorithm(try parseClosure(source))

            #expect(parsed.sourceAlgorithms.isEmpty)
            let diagnostic = try #require(parsed.diagnostics.first?.capabilityDiagnostic)
            #expect(diagnostic.code == .unsupportedConstruct)
            #expect(diagnostic.construct == .unregistered(sourceName: testCase.name))
            #expect(diagnostic.operation == .sourceDecoding)
            #expect(diagnostic.sourcePath == ["Algorithm", testCase.name])
            #expect(diagnostic.sourceSpan.location != .unavailable)
            #expect(diagnostic.expected == "a registered Algorithm declaration with supported source decoding")
            #expect(diagnostic.actual == "unregistered Algorithm declaration '\(testCase.name)'")
            #expect(diagnostic.nextSafeAction == "Use an admitted Algorithm declaration.")
            #expect(!parsed.diagnostics.contains { $0.message.contains("Unsupported Algorithm declaration") })
        }
    }

    @Test("Formal expression closures stay outside Algorithm capability admission")
    func formalExpressionClosuresDoNotBecomeAlgorithmDeclarations() throws {
        let source = """
        {
            Algorithm("FormalClosureBoundary") { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.advance) {
                    let imported: Expr<Int> = ModuleCall("Instance", "Value", count)
                    Assign(count, to: imported)
                }
                StateConstraint(All(in: SetExpr<Int>.literal(0, 1)) { value in value >= 0 })
                Invariant("Bounded") {
                    All(in: SetExpr<Int>.literal(0, 1)) { value in value >= count }
                }
                FormalDefinition("SafeAt", taking: Int.self, Int.self) { ballot, limit in
                    LetRec("SA", over: IntRange(0, through: limit), taking: Int.self, { recursion, current in
                        If(current == 0, then: true, else: recursion(current.expr - 1))
                    }, in: { recursion in recursion(ballot.expr) })
                }
            }
        }
        """

        let parsed = parseAlgorithm(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.sourceAlgorithms.map(\.model.name) == ["FormalClosureBoundary"])
    }

    @Test("Unsupported action source does not create a placeholder action")
    func rejectsUnsupportedActionWithoutSemanticPlaceholder() throws {
        let source = """
        {
            Action("unsupported") {
                let value = 1
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Action 'unsupported' contains an unsupported action expression."
        ])
    }

    @Test("Unsupported top-level source is diagnosed")
    func rejectsUnsupportedTopLevelSource() throws {
        let source = """
        {
            UnsupportedDeclaration()
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Specification for-loop body contains an unsupported item."
        ])
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum("Node", finiteValues: [.string("left"), .string("right")])]
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
        let parsed = parseAlgorithm(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty)
        #expect(try loweredSource(parsed, named: "Temporal").temporalProperties.map(\.name) == [
            "progress", "eventual", "safe", "recurs", "settles"
        ])
    }

    @Test("Algorithm parser preserves a process-bound formal lambda application")
    func parsesProcessScopedFormalLambdaApplication() throws {
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum(
                "Worker",
                cases: ["left": .string("left"), "right": .string("right")],
                finiteValues: [.string("left"), .string("right")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "ScopedFormalLambda")
        #expect(specification.actions.map(\.name) == ["advance", "Terminating"])
        #expect(try specification.compile().renderedTLAModuleBundle().tla.contains("LAMBDA"))
        let rendered = try specification.compile().renderedPlusCalBundle().root.tla
        #expect(rendered.contains("counters[self] + 1"))
        #expect(rendered.contains("LAMBDA") == false)
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
        let closure = try parseClosure(source)
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "ThreeWith")
        let rendered = try specification.compile().renderedTLAModuleBundle().tla
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum("Node", finiteValues: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "MacroLock")
        #expect(specification.actions.map(\.name) == ["acquire", "Terminating"])
        #expect(try specification.compile().renderedTLAModuleBundle().tla.contains("lock"))
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "CopyValue")
        let rendered = try specification.compile().renderedTLAModuleBundle().tla
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "OffsetValue")
        #expect(try specification.compile().renderedTLAModuleBundle().tla.contains("destination' = (source + 1)"))
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "PairVote")
        #expect(try specification.compile().renderedTLAModuleBundle().tla.contains(
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.actions.isEmpty)
        let diagnostic = parsed.diagnostics.first?.message ?? ""
        #expect(diagnostic.contains("What failed: statement macro 'write' assigns through parameter"))
        #expect(diagnostic.contains("Expected a formal variable assignment target"))
        #expect(diagnostic.contains("Next safe action"))
    }

    @Test("source model compiles procedure bindings to deterministic formal slots")
    func parsesTypedProcedureBindings() throws {
        let source = """
        {
            Algorithm("ProcedureSource") { scope in
                let output = scope.sharedVar("output", initial: 0)
                Procedure(ProcedureName.work, parameters: Int.self, scoped: { value, scope in
                    let offset = scope.localVar("offset", initial: 1)
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(closure, enumDefinitions: [procedureNames])

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
        let closure = try parseClosure(source)
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "ParameterlessMacro")
        #expect(try specification.compile().renderedTLAModuleBundle().tla.contains("count' = (count + 1)"))
    }

    @Test("parser retains a filtered formal function initial domain")
    func parsesFilteredFunctionInitialDomain() throws {
        let source = """
        {
            Algorithm("FunctionDomain") { scope in
                let successors = scope.sharedVar("successors", in: Where(
                    Functions(from: Node.all, to: Subsets(of: SetExpr<Node>.literal(.first, .second)))
                ) { successor in
                    All(Node.all) { node in
                        successor[node].cardinality == 1
                    }
                })
                Do(TestControlLabel.done) { Stop() }
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum(
                "Node",
                cases: ["first": .string("first"), "second": .string("second")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let compilation = try compile(parsed, named: "FunctionDomain")
        let successors = try #require(try loweredSource(parsed, named: "FunctionDomain").variables.first { $0.name == "successors" })
        let surface = try #require(compilation.machineSurfacePlan.variables.first { $0.formalName == successors.name })
        #expect(surface.swiftType == "Function<Node, SetExpr<Node>>")
        guard case .memberOf = successors.initialization else {
            Issue.record("Expected successors to retain its initial domain")
            return
        }
        #expect(compilation.renderedTLAModuleBundle().tla.contains("Cardinality"))
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
            try parseClosure(source),
            enumDefinitions: [parserEnum(
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [
                parserEnum("Door", cases: ["closed": .string("closed")]),
                parserEnum("Car", finiteValues: [.string("north"), .string("south")])
            ]
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum("Acceptor", finiteValues: [.string("a1"), .string("a2")])]
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum(
                "Node",
                cases: ["one": .int(1), "two": .int(2)]
            )]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try loweredSource(parsed, named: "FiniteFunction")
        #expect(try specification.compile().renderedTLAModuleBundle().tla.contains("CASE"))
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
        let closure = try parseClosure(source)
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum(
                "Node",
                cases: ["left": .string("left"), "right": .string("right")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try loweredSource(parsed, named: "MacroProcess")
        let action = try #require(try specification.compile().semantics.actions.first)
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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Step", cases: [
                "start": .string("Begin"),
                "loop": .string("Repeat"),
                "finish": .string("Finish")
            ])]
        )

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
                let parsed = parseAlgorithm(try parseClosure("""
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
                    try parseClosure("""
                    {
                        Algorithm("InvalidProcedureName") {
                            \(body)
                        }
                    }
                    """),
                    enumDefinitions: [
                        procedureNames,
                        parserEnum("NumberedProcedure", cases: ["work": .int(1)])
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
        let closure = try parseClosure(source)
        let parsed = parseAlgorithm(
            closure,
            enumDefinitions: [parserEnum(
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
        let closure = try parseClosure("""
        { scope in
            let count: SharedVariable<Int> = scope.sharedVar("count", initial: 1 + 2)
        }
        """)
        let parsed = SpecParser.parseSpecClosure(closure)
        #expect(parsed.diagnostics.isEmpty)

        let parsedVariable = try #require(try loweredSource(parsed, named: "SharedInitializer").variables.first)

        #expect(parsedVariable.initialization == .expression(.add(.value(.int(1)), .value(.int(2)))))

        let compilation = try parsed.compile(specificationName: "SharedInitializer")
        let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let count = try #require(TLAStateProjection.Token(validating: "count"))
        #expect(try state.projection(using: compilation.layout).value(for: count) == .int(3))
    }

    @Test("parsed and built literal initializers have one compilation identity")
    func parsedAndBuiltLiteralInitializersShareIdentity() throws {
        let closure = try parseClosure("""
        { scope in
            let count = scope.sharedVar("count", initial: 1)
        }
        """)
        let parsed = try SpecParser.parseSpecClosure(closure).compile(
            specificationName: "LiteralInitializer"
        )
        let built = try TLASpec("LiteralInitializer") { scope in
            let _ = scope.sharedVar("count", initial: 1)
        }.compile()

        #expect(parsed.identity == built.identity)
    }

    @Test("parsed initial domains retain state dependencies")
    func parsedInitialDomainsRetainStateDependencies() throws {
        let closure = try parseClosure("""
        { scope in
            let limit = scope.sharedVar("limit", initial: 2)
            let choice = scope.sharedVar("choice", in: Where(SetExpr<Int>.literal(1, 2, 3)) { value in
                value <= limit
            })
        }
        """)
        let parsed = SpecParser.parseSpecClosure(closure)
        let compilation = try parsed.compile(specificationName: "DependentInitialDomain")
        let choice = try #require(compilation.layout.variableID(named: "choice"))
        let states = try CompiledRuntime(compilation: compilation).initialStates()

        #expect(Set(try states.map {
            try $0.value(for: choice).rendered(using: compilation.layout)
        }) == [.int(1), .int(2)])
    }

    @Test("unsupported variable initializers fail during parsing")
    func rejectsUnsupportedVariableInitializer() throws {
        let closure = try parseClosure("""
        {
            let count = Var("count", UnsupportedInitialValue())
        }
        """)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == ["Var requires a supported initial formal value."])
    }
}

private enum ParserNode: String, FiniteTLAValueDomain {
    case left
    case right

    static var defaultValue: Self { .left }
    static let finiteValues: [ParserNode] = [.left, .right]

    var tlaValue: TLAValue { .string(rawValue) }
}

// MARK: - StateExpr: literals

@Suite(.serialized) struct StateExprLiteralTests {
    @Test func parseInts() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("0")) == .value(.int(0)))
        #expect(SpecParser.decodeStateExpr(try parseExpression("42")) == .value(.int(42)))
    }

    @Test("static Swift integer spelling is decoded")
    func decodesStaticSwiftIntegerSpelling() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("1_000")) == .int(1_000))
    }

    @Test func parseBools() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("true")) == .value(.bool(true)))
        #expect(SpecParser.decodeStateExpr(try parseExpression("false")) == .value(.bool(false)))
    }

    @Test func parseStrings() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("\"hello\"")) == .value(.string("hello")))
        #expect(SpecParser.decodeStateExpr(try parseExpression("\"left\"")) == .value(.string("left")))
        #expect(SpecParser.decodeStateExpr(try parseExpression("\"\"")) == .value(.string("")))
    }
}

// MARK: - StateExpr: variables

@Suite(.serialized) struct StateExprVariableTests {
    @Test func parseVariableReferences() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("x")) == .variable("x"))
        #expect(SpecParser.decodeStateExpr(try parseExpression("count")) == .variable("count"))
        #expect(SpecParser.decodeStateExpr(try parseExpression("direction")) == .variable("direction"))
    }
}

@Suite(.serialized) struct SpecVariableDeclarationParsingTests {
    @Test func plainVarDeclarationIsParsedWithoutGenericSpecialization() throws {
        let source = """
        {
            let counter = Var("counter", 0)
            Variable(counter, in: 0...1)
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.count == 1)
        guard parsed.variables.count == 1 else { return }
        #expect(parsed.variables[0].name == "counter")
        #expect(parsed.variables[0].initialization == .memberOf(.setLiteral([.value(.int(0)), .value(.int(1))])))
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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let unresolved = SpecParser.parseSpecClosure(try parseClosure("""
        {
            let values = Var<SetExpr<Int>>("values")
            Variable(values)
        }
        """))
        let resolved = SpecParser.parseSpecClosure(try parseClosure("""
        {
            let values = Var<SetExpr<Int>>("values")
            Variable(values, SetExpr<Int>())
        }
        """))

        do {
            _ = try unresolved.compile(specificationName: "UnresolvedInitializer")
            Issue.record("Expected compilation to reject the unresolved initializer")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .missingVariableInitializer)
        }
        let compilation = try resolved.compile(specificationName: "ResolvedInitializer")
        #expect(compilation.description.variables.map(\.name) == ["values"])
    }

    @Test("generic variable types retain their structural Swift spelling")
    func retainsQualifiedGenericVariableType() throws {
        let source = """
        {
            let successors = Var<SwiftTLA.Function<Model.Node, SwiftTLA.SetExpr<Swift.Int>>>("successors", TLAValue.function([:]))
        }
        """
        let closure = try parseClosure(source)

        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])

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

        let parsed = SpecParser.parseSpecClosure(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.temporal.map(\.name) == ["progress", "eventual", "safe", "recurs", "settles"])
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

    @Test func formalDefinitionIsParsedIntoTheCanonicalFormalModel() throws {
        let source = """
        {
            FormalDefinition(
                "increment",
                parameters: [.value("value")],
                body: value + 1
            )
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Key", finiteValues: [.string("k1"), .string("k2")])]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "InitialState",
                parameters: [],
                body: .functionLiteral(
                    .setLiteral([.value(.string("k1")), .value(.string("k2"))]),
                    "__pcal_function_key",
                    .int(0)
                )
            )
        ])
    }

    @Test func higherOrderFormalDefinitionRoundTripsThroughTheCanonicalParser() throws {
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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum(
                "TestControlLabel",
                cases: ["stop": .string("stop")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.sourceAlgorithms.first?.model.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "same",
                parameters: [.value("value0"), .value("value1")],
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
        #expect(
            parsed.sourceAlgorithms.first.map { algorithmCompilationEncoding($0.model) }
                == algorithmCompilationEncoding(built.model)
        )
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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        guard let definition = parsed.formalOperatorDefinitions.first else {
            Issue.record("Expected one typed formal definition.")
            return
        }
        #expect(definition.parameters == [.value("value0"), .value("value1")])
        guard case .letIn(let operators, let result) = definition.body else {
            Issue.record("Expected the typed formal body to retain its local recursive LET.")
            return
        }
        #expect(operators.map(\.name) == ["SA"])
        #expect(operators[0].parameters == ["current"])
        #expect(result == .recursiveCall("SA", [.variable("value0")]))
        #expect(try TLASpec(
            name: "TypedFormalRendering",
            variables: [],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [definition]
        ).compile().renderedTLAModuleBundle().tla.contains("SA["))
    }

    @Test func typedFormalDefinitionParsesPairLiterals() throws {
        let source = """
        {
            FormalDefinition("PairAt", taking: Int.self, Int.self) { ballot, value in
                Pair.literal(ballot.expr, value.expr) == Pair.literal(0, 1)
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.formalOperatorDefinitions.first?.body == .equal(
            .tupleLiteral([.variable("value0"), .variable("value1")]),
            .value(.tuple([.int(0), .int(1)]))
        ))
    }

    @Test func formalOperatorLambdaAndArgumentKindsRoundTripThroughTheParser() throws {
        let expression = try parseExpression("""
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
            try parseExpression("FormalCall(as: Bool.self, \"SafeAt\", 3, 5)")
        )

        #expect(parsed == built.stateExpr)
        #expect(built.stateExpr == .operatorApplication(
            .reference("SafeAt", arity: 2), [.value(3), .value(5)]
        ))
    }

    @Test("typed facade closure binders preserve lexical shadowing")
    func typedFacadeBindersPreserveLexicalShadowing() throws {
        let parsed = try #require(SpecParser.decodeTypedFacadeValue(
            try parseExpression("""
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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

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
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.map(\.message) == ["Malformed Variable declaration"])
    }
}

// MARK: - StateExpr: arithmetic operators

@Suite(.serialized) struct StateExprArithmeticTests {
    @Test func parseArithmetic() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("x + 5")) == StateExpr.add(.variable("x"), .value(.int(5))))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x - 3")) == StateExpr.subtract(.variable("x"), .value(.int(3))))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x * 2")) == StateExpr.multiply(.variable("x"), .value(.int(2))))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x / 4")) == StateExpr.divide(.variable("x"), .value(.int(4))))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x % 7")) == StateExpr.modulo(.variable("x"), .value(.int(7))))
    }
}

// MARK: - StateExpr: comparison operators

@Suite(.serialized) struct StateExprComparisonTests {
    @Test func parseComparisons() throws {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.decodeStateExpr(try parseExpression("x == y")) == StateExpr.equal(x, y))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x != y")) == StateExpr.notEqual(x, y))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x < y")) == StateExpr.lessThan(x, y))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x <= y")) == StateExpr.lessOrEqual(x, y))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x > y")) == StateExpr.greaterThan(x, y))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x >= y")) == StateExpr.greaterOrEqual(x, y))
    }
}

// MARK: - StateExpr: logical and prefix operators

@Suite(.serialized) struct StateExprLogicalPrefixTests {
    @Test func parseLogical() throws {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.decodeStateExpr(try parseExpression("x && y")) == StateExpr.and(x, y))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x || y")) == StateExpr.or(x, y))
    }

    @Test func parsePrefix() throws {
        let x: StateExpr = .variable("x")
        #expect(SpecParser.decodeStateExpr(try parseExpression("!x")) == StateExpr.not(x))
        #expect(SpecParser.decodeStateExpr(try parseExpression("-x")) == StateExpr.negate(x))
        #expect(SpecParser.decodeStateExpr(try parseExpression("-1")) == StateExpr.value(.int(-1)))
    }

    @Test func preservesSwiftInfixPrecedence() throws {
        let index: StateExpr = .variable("index")
        let count: StateExpr = .variable("count")
        #expect(
            SpecParser.decodeStateExpr(try parseExpression("index <= count + 1"))
                == StateExpr.lessOrEqual(index, .add(count, .value(.int(1))))
        )
    }

    @Test func parseParenthesized() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("(x)")) == .variable("x"))
    }
}

// MARK: - StateExpr: range operator

@Suite(.serialized) struct StateExprRangeTests {
    @Test func parseRangeOperator() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("1...3")) == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))]))
        #expect(SpecParser.decodeStateExpr(try parseExpression("0...2")) == StateExpr.setLiteral([.value(.int(0)), .value(.int(1)), .value(.int(2))]))
    }
}

// MARK: - StateExpr: member access properties

@Suite(.serialized) struct StateExprMemberAccessTests {
    @Test func parseKnownProperties() throws {
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(try parseExpression("s.cardinality")) == StateExpr.cardinality(s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("s.flattened")) == StateExpr.unionAll(s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("s.subsets")) == StateExpr.powerSet(s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("s.domain")) == StateExpr.domain(s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("s.count")) == StateExpr.tupleLength(s))
    }

    @Test func parseUnknownPropertyAsRecordAccess() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("msg.type")) == StateExpr.recordAccess(.variable("msg"), "type"))
        #expect(SpecParser.decodeStateExpr(try parseExpression("ballot.val")) == StateExpr.recordAccess(.variable("ballot"), "val"))
    }
}

@Suite(.serialized) struct SourceLiteralParsingTests {
    @Test("escaped source string preserves its formal value")
    func preservesEscapedStringLiteral() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseExpression(#""alpha\"beta""#))
                == .value(.string("alpha\"beta"))
        )
    }
}

@Suite(.serialized) struct TypedFacadeSyntaxTests {
    @Test("typed facade grammar accepts only its declared module qualification")
    func admitsOnlyDeclaredTypedFacadeQualification() throws {
        let unqualified = try parseExpression("SetExpr<Int>()")
        let swiftTLAQualified = try parseExpression("SwiftTLA.SetExpr<Int>()")
        let unrelatedQualified = try parseExpression("Other.SetExpr<Int>()")
        let unqualifiedParameter = try parseExpression(#"Parameter("value")"#)
        let swiftTLAQualifiedParameter = try parseExpression(#"SwiftTLA.Parameter("value")"#)
        let unrelatedQualifiedParameter = try parseExpression(#"Other.Parameter("value")"#)
        let parameter = StateExpr.variable("value")

        #expect(SpecParser.decodeTypedFacadeValue(unqualified) == .value(.set([])))
        #expect(SpecParser.decodeTypedFacadeValue(swiftTLAQualified) == .value(.set([])))
        #expect(SpecParser.decodeTypedFacadeValue(unrelatedQualified) == nil)
        #expect(SpecParser.decodeTypedFacadeValue(unqualifiedParameter) == parameter)
        #expect(SpecParser.decodeTypedFacadeValue(swiftTLAQualifiedParameter) == parameter)
        #expect(SpecParser.decodeTypedFacadeValue(unrelatedQualifiedParameter) == nil)
    }

    @Test("qualified empty set uses its structural type")
    func parsesQualifiedEmptySet() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseExpression("SwiftTLA.SetExpr<Int>()"))
                == .value(.set([]))
        )
    }

    @Test("formal names must be static")
    func rejectsInterpolatedFormalNames() throws {
        #expect(SpecParser.decodeTypedFacadeValue(
            try parseExpression(#"FormalCall(as: Bool.self, "Safe\(suffix)")"#)
        ) == nil)
        #expect(SpecParser.decodeTypedFacadeValue(
            try parseExpression(#"ModuleCall("Instance\(suffix)", "Value")"#)
        ) == nil)
        #expect(SpecParser.decodeStateExpr(
            try parseExpression(#"At("step\(suffix)", worker)"#)
        ) == nil)
    }

    @Test("control locations require a declared label case")
    func requiresDeclaredControlLocation() throws {
        let parser = ParserSession(enumDefinitions: [
            parserEnum("Label", cases: ["receive": .string("receive")])
        ])
        let expected = StateExpr.equal(
            .functionApply(.programCounter, .variable("worker")),
            .controlLocation(.init("receive"))
        )

        #expect(parser.decodeStateExpr(
            try parseExpression("At(Label.receive, worker)")
        ) == expected)
        for source in [
            #"At("receive", worker)"#,
            "At(.receive, worker)",
            "At(Other.receive, worker)",
            "At(Label.missing, worker)"
        ] {
            #expect(parser.decodeStateExpr(try parseExpression(source)) == nil)
        }
    }
}

// MARK: - StateExpr: method calls (binary)

@Suite(.serialized) struct StateExprBinaryMethodTests {
    @Test func parseBinaryMethods() throws {
        let x: StateExpr = .variable("x")
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.isIn(s)")) == StateExpr.in(x, s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.union(s)")) == StateExpr.union(x, s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.intersection(s)")) == StateExpr.intersection(x, s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.subtracting(s)")) == StateExpr.setDifference(x, s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.isSubset(of: s)")) == StateExpr.subset(x, s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.applying(s)")) == StateExpr.functionApply(x, s))
        let filterResult = SpecParser.decodeStateExpr(try parseExpression("x.filtering(s)"))
        guard case .setFilter(let filterDomain, _, let filterBody) = filterResult else {
            Issue.record("Expected a structural set filter")
            return
        }
        #expect(filterDomain == x)
        #expect(filterBody == s)
        let mapResult = SpecParser.decodeStateExpr(try parseExpression("x.mapping(s)"))
        guard case .setMap(let mapBody, _, let mapDomain) = mapResult else {
            Issue.record("Expected a structural set map")
            return
        }
        #expect(mapBody == s)
        #expect(mapDomain == x)
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.appending(s)")) == StateExpr.tupleAppend(x, s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.concatenating(s)")) == StateExpr.tupleConcatenate(x, s))
        #expect(SpecParser.decodeStateExpr(try parseExpression("x.integerDivided(by: 2)")) == StateExpr.integerDivide(x, .value(.int(2))))
    }
}

// MARK: - StateExpr: method calls (multi-arg)

@Suite(.serialized) struct StateExprMultiArgMethodTests {
    @Test func parseUpdated() throws {
        let f: StateExpr = .variable("f")
        #expect(SpecParser.decodeStateExpr(try parseExpression("f.updated(at: 0, to: 1)")) == StateExpr.except(f, .value(.int(0)), .value(.int(1))))
    }

    @Test func parseAt() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseExpression("t.at(3)"))
                == StateExpr.tupleAccess(.variable("t"), 3)
        )
    }
}

// MARK: - StateExpr: static calls

@Suite(.serialized) struct StateExprStaticCallTests {
    @Test func parseStaticSet() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseExpression("StateExpr.set([1, 2, 3])"))
                == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        )
    }

    @Test func parseStaticTuple() throws {
        #expect(SpecParser.decodeStateExpr(try parseExpression("StateExpr.tuple([1, x])")) == StateExpr.tupleLiteral([.value(.int(1)), .variable("x")]))
    }

    @Test func parseStaticRecord() throws {
        #expect(
            SpecParser.decodeStateExpr(try parseExpression("StateExpr.record(name: x, age: 42)"))
                == StateExpr.record(["name": .variable("x"), "age": .value(.int(42))])
        )
    }

    @Test func parseStaticIf() throws {
        let result = SpecParser.decodeStateExpr(try parseExpression("StateExpr.if(x == 0, then: 1, else: 2)"))
        #expect(result == StateExpr.ifThenElse(
            StateExpr.equal(.variable("x"), .value(.int(0))),
            .value(.int(1)),
            .value(.int(2))
        ))
    }

    @Test func parseStaticFunction() throws {
        #expect(SpecParser.decodeStateExpr(
            try parseExpression("StateExpr.functionLiteral(StateExpr.set([1, 2]), \"x\", x + 1)")
        ) == .functionLiteral(
            .setLiteral([.int(1), .int(2)]),
            "x",
            .add(.variable("x"), .int(1))
        ))
    }

    @Test func parseStaticForAll() throws {
        #expect(SpecParser.decodeStateExpr(
            try parseExpression("StateExpr.forAll(StateExpr.set([1, 2]), \"x\", x > 0)")
        ) == .forAll(
            .setLiteral([.int(1), .int(2)]),
            "x",
            .greaterThan(.variable("x"), .int(0))
        ))
    }

    @Test func parseStaticExists() throws {
        #expect(SpecParser.decodeStateExpr(
            try parseExpression("StateExpr.exists(StateExpr.set([1, 2]), \"x\", x > 0)")
        ) == .exists(
            .setLiteral([.int(1), .int(2)]),
            "x",
            .greaterThan(.variable("x"), .int(0))
        ))
    }

    @Test func parseStaticChoose() throws {
        #expect(SpecParser.decodeStateExpr(
            try parseExpression("StateExpr.choose(StateExpr.set([1, 2]), \"x\", x > 0)")
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
            .value(.bool(true))
        ) = SpecParser.decodeStateExpr(
            try parseExpression("StateExpr.any(from: StateExpr.set([1, 2]))")
        ) else {
            Issue.record("Expected a choice over the declared set")
            return
        }
    }

    @Test func parseStaticFirstMatchWithFallback() throws {
        let result = SpecParser.decodeStateExpr(
            try parseExpression("StateExpr.firstMatch((when: x == 0, then: 10), (when: x == 1, then: 20), fallback: 99)")
        )
        #expect(result == StateExpr.caseExpr(
            [
                StateExpr.equal(.variable("x"), .value(.int(0))), .value(.int(10)),
                StateExpr.equal(.variable("x"), .value(.int(1))), .value(.int(20))
            ],
            .value(.int(99))
        ))
    }

    @Test func parseStaticFirstMatchNoFallback() throws {
        let result = SpecParser.decodeStateExpr(
            try parseExpression("StateExpr.firstMatch((when: x < 0, then: -1))")
        )
        #expect(result == StateExpr.caseExpr(
            [StateExpr.lessThan(.variable("x"), .value(.int(0))), StateExpr.value(.int(-1))],
            nil
        ))
    }
}

// MARK: - ActionExpr: basic assignments

@Suite(.serialized) struct ActionExprBasicTests {
    @Test func parseBecomes() throws {
        #expect(SpecParser.decodeActionExpr(try parseExpression("x.becomes(5)")) == ActionExpr.assign(.named("x"), .value(.int(5))))
        #expect(
            SpecParser.decodeActionExpr(try parseExpression("x.becomes(x + 1)"))
                == ActionExpr.assign(.named("x"), StateExpr.add(.variable("x"), .value(.int(1))))
        )
    }

    @Test func parseStays() throws {
        #expect(SpecParser.decodeActionExpr(try parseExpression("x.stays")) == ActionExpr.unchanged(.named("x")))
    }

    @Test func parseGuardedBecomes() throws {
        #expect(SpecParser.decodeActionExpr(try parseExpression("x.becomes(1).when(x == 0)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign(.named("x"), .value(.int(1)))
        ))
    }

    @Test func parseDoubleWhen() throws {
        let result = SpecParser.decodeActionExpr(try parseExpression("x.becomes(1).when(x > 0).when(x < 5)"))
        #expect(result == ActionExpr.and(
            ActionExpr.guard_(StateExpr.and(
                StateExpr.lessThan(.variable("x"), .value(.int(5))),
                StateExpr.greaterThan(.variable("x"), .value(.int(0)))
            )),
            ActionExpr.assign(.named("x"), .value(.int(1)))
        ))
    }

    @Test func parseNondeterministicAssign() throws {
        let result = SpecParser.decodeActionExpr(
            try parseExpression("x.becomes(StateExpr.any(from: StateExpr.set([1, 2, 3])))")
        )
        let expectedSet = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        #expect(result == ActionExpr.chooseAction(.named("x"), expectedSet))
    }
}

// MARK: - ActionExpr: AND / OR combinations

@Suite(.serialized) struct ActionExprCombinatorTests {
    @Test func parseAndOfTwoActions() throws {
        #expect(SpecParser.decodeActionExpr(try parseExpression("x.becomes(1) && y.becomes(2)")) == ActionExpr.and(
            ActionExpr.assign(.named("x"), .value(.int(1))),
            ActionExpr.assign(.named("y"), .value(.int(2)))
        ))
    }

    @Test func parseOrOfTwoActions() throws {
        #expect(SpecParser.decodeActionExpr(try parseExpression("x.becomes(1) || x.becomes(2)")) == ActionExpr.or(
            ActionExpr.assign(.named("x"), .value(.int(1))),
            ActionExpr.assign(.named("x"), .value(.int(2)))
        ))
    }

    @Test func parseGuardAndAction() throws {
        #expect(SpecParser.decodeActionExpr(try parseExpression("x > 0 && x.becomes(x - 1)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.greaterThan(.variable("x"), .value(.int(0)))),
            ActionExpr.assign(.named("x"), StateExpr.subtract(.variable("x"), .value(.int(1))))
        ))
    }

    @Test func parseActionAndGuard() throws {
        #expect(SpecParser.decodeActionExpr(try parseExpression("x.becomes(0) && x == 0")) == ActionExpr.and(
            ActionExpr.assign(.named("x"), .value(.int(0))),
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0))))
        ))
    }

    @Test func parseStateOrAction() throws {
        #expect(SpecParser.decodeActionExpr(try parseExpression("x == 0 || x.becomes(1)")) == ActionExpr.or(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign(.named("x"), .value(.int(1)))
        ))
    }

    @Test func parseHourClockStyleNestedOr() throws {
        let result = SpecParser.decodeActionExpr(
            try parseExpression("(x != 12) && x.becomes(x + 1) || (x == 12) && x.becomes(1)")
        )
        let left = ActionExpr.and(
            ActionExpr.guard_(StateExpr.notEqual(.variable("x"), .value(.int(12)))),
            ActionExpr.assign(.named("x"), StateExpr.add(.variable("x"), .value(.int(1))))
        )
        let right = ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(12)))),
            ActionExpr.assign(.named("x"), .value(.int(1)))
        )
        #expect(result == ActionExpr.or(left, right))
    }
}

// MARK: - ActionExpr: closure parsing

@Suite(.serialized) struct ActionExprClosureTests {
    @Test func parseEmptyClosure() throws {
        let closure = try parseClosure("{}")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.guard_(.value(.bool(true))))
    }

    @Test func parseSingleStatementClosure() throws {
        let closure = try parseClosure("{ x.becomes(1) }")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.assign(.named("x"), .value(.int(1))))
    }

    @Test func parseMultiStatementClosure() throws {
        let closure = try parseClosure("{ x.becomes(1) ; y.stays }")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.and(
            ActionExpr.assign(.named("x"), .value(.int(1))),
            ActionExpr.unchanged(.named("y"))
        ))
    }
}

// MARK: - TemporalExpr

@Suite(.serialized) struct TemporalExprTests {
    @Test func parseLeadsTo() throws {
        let call = try #require(try parseExpression("x.leadsTo(y)").as(FunctionCallExprSyntax.self))
        #expect(
            SpecParser.decodeTemporal(call)
                == TemporalExpr.leadsTo(.variable("x"), .variable("y"))
        )
    }

    @Test func parseLeadsToWithExpressions() throws {
        let call = try #require(
            try parseExpression("(x > 0).leadsTo(y == 0)").as(FunctionCallExprSyntax.self)
        )
        let result = SpecParser.decodeTemporal(call)
        #expect(result == TemporalExpr.leadsTo(
            StateExpr.greaterThan(.variable("x"), .value(.int(0))),
            StateExpr.equal(.variable("y"), .value(.int(0)))
        ))
    }
}


// MARK: - Enum phase parsing

private let cameraModeDefinition = parserEnum(
    "CameraMode",
    cases: [
        "idle": .string("idle"),
        "live": .string("live"),
        "recording": .string("recording"),
        "playback": .string("playback")
    ]
)

@Suite(.serialized) struct EnumPhaseParsingTests {
    @Test func enumFactsDoNotLeakFromOneParseIntoTheNextDecoderCall() throws {
        let closure = try parseClosure("""
        {
            Invariant("idleOnly") { mode == CameraMode.idle }
        }
        """)

        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.invariants.first?.body == .equal(.variable("mode"), .value(.string("idle"))))
        #expect(
            SpecParser.decodeStateExpr(try parseExpression("CameraMode.idle"))
                == .recordAccess(.variable("CameraMode"), "idle")
        )
    }

    @Test func parseQualifiedEnumCaseInInvariant() throws {
        let source = """
        {
            Invariant("idleOnly") {
                mode == CameraMode.idle
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.invariants.count == 1)
        #expect(parsed.invariants[0].body == .equal(.variable("mode"), .value(.string("idle"))))
    }

    @Test func parseEnumAssignment() throws {
        let source = """
        {
            Action("test") {
                mode.becomes(CameraMode.live)
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.actions.count == 1)
        #expect(parsed.actions[0].body == .assign(.named("mode"), .value(.string("live"))))
    }

    @Test("qualified formal Action parses as an action declaration")
    func parsesQualifiedFormalAction() throws {
        let parsed = SpecParser.parseSpecClosure(try parseClosure("""
        {
            SwiftTLA.Action("advance") {
                count.becomes(count + 1)
            }
        }
        """))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions == [
            .init(
                name: "advance",
                body: .assign(.named("count"), .add(.variable("count"), .value(.int(1))))
            )
        ])
    }

    @Test func parsesVariadicActionParametersInDeclarationOrder() throws {
        let source = """
        {
            Action("moveElevator", parameters: [
                ActionParameter("person", values: [1, 2]),
                ActionParameter("elevator", values: [10, 20]),
                ActionParameter("direction", values: [100, 200])
            ]) {
                floor.becomes(1)
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)
        #expect(parsed.actions.count == 1)
        #expect(parsed.actions[0].bindings.map(\.name) == ["person", "elevator", "direction"])
        #expect(parsed.actions[0].bindings.map(\.values) == [
            [.int(1), .int(2)], [.int(10), .int(20)], [.int(100), .int(200)]
        ])
        #expect(parsed.actions[0].bindings.map(\.generatedSwiftType) == ["Int", "Int", "Int"])
        #expect(parsed.actions[0].body == .assign(.named("floor"), .value(.int(1))))
    }

    @Test func parsesParameterizedActionLocalBindingsInLexicalScope() throws {
        let source = """
        {
            Action("pass", parameters: [
                ActionParameter("from", values: [1, 2]),
                ActionParameter("to", values: [1, 2]),
                ActionParameter("round", values: [1, 2])
            ]) {
                let from = Expr<Int>(.variable("from"))
                let to = Expr<Int>(.variable("to"))
                let round = Expr<Int>(.variable("round"))
                leader == from && leader.becomes(to + round)
            }
        }
        """

        let parsed = SpecParser.parseSpecClosure(try parseClosure(source))

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions[0].bindings.map(\.name) == ["from", "to", "round"])
        #expect(parsed.actions[0].body == .and(
            .guard_(.equal(.variable("leader"), .variable("from"))),
            .assign(.named("leader"), .add(.variable("to"), .variable("round")))
        ))
    }

    @Test func diagnosesInvalidDomainsAtEveryParameterPosition() throws {
        let source = """
        {
            Action("moveElevator", parameters: [
                ActionParameter("person", values: personIDs),
                ActionParameter("elevator", values: []),
                ActionParameter("direction", values: [1, 1])
            ]) {
                floor.becomes(1)
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)
        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Parameterized action 'moveElevator' parameter 'person' requires an explicitly written finite values array.",
            "Parameterized action 'moveElevator' parameter 'elevator' requires a non-empty finite values array.",
            "Parameterized action 'moveElevator' parameter 'direction' has duplicate finite-domain values."
        ])
    }

    @Test func normalizesTypedFacadeAndEnumDomainsToBuilderAST() throws {
        let source = """
        {
            let floor = Var<Int>("floor")
            let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
            let calls = Var<SetExpr<Record<CarSchema>>>("calls")
            Variable(floor, 0)
            Variable(cars, Function<CarID, Record<CarSchema>>.literal(
                (CarID.carA, Record<CarSchema>.literal(
                    .init(CarSchema.floor, 0),
                    .init(CarSchema.doorsOpen, false)
                )),
                (CarID.carB, Record<CarSchema>.literal(
                    .init(CarSchema.floor, 1),
                    .init(CarSchema.doorsOpen, true)
                ))
            ))
            Variable(calls, SetExpr<Record<CarSchema>>())
            Action("move", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                cars.becomes(cars.updating(.carA) { car in
                    car.updating(CarSchema.floor, to: 2)
                })
            }
            Action("readCar") {
                floor.becomes(cars[CarID.carA][CarSchema.floor])
            }
            Action("initialize") {
                cars.becomes(Function<CarID, Record<CarSchema>>.literal(
                    (CarID.carA, Record<CarSchema>.literal(
                        .init(CarSchema.floor, 0),
                        .init(CarSchema.doorsOpen, false)
                    )),
                    (CarID.carB, Record<CarSchema>.literal(
                        .init(CarSchema.floor, 1),
                        .init(CarSchema.doorsOpen, true)
                    ))
                ))
            }
            Action("insertCall") {
                calls.inserting(Record<CarSchema>.literal(
                    .init(CarSchema.floor, 0),
                    .init(CarSchema.doorsOpen, false)
                ))
            }
            Action("removeCall") {
                calls.removing(Record<CarSchema>.literal(
                    .init(CarSchema.floor, 0),
                    .init(CarSchema.doorsOpen, false)
                ))
            }
            Action("containsCall") {
                calls.contains(Record<CarSchema>.literal(
                    .init(CarSchema.floor, 0),
                    .init(CarSchema.doorsOpen, false)
                )) && floor.becomes(1)
            }
        }
        """
        let enumDefinitions = [
            parserEnum("PersonID", cases: ["alice": .string("alice"), "bob": .string("bob")]),
            parserEnum("CarID", cases: ["carA": .string("carA"), "carB": .string("carB")]),
            parserEnum(
                "Direction",
                cases: ["up": .string("up"), "down": .string("down")],
                finiteValues: [.string("up"), .string("down")]
            )
        ]
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: enumDefinitions
        )

        let floor = Var<Int>("floor")
        let cars = Var<Function<TestCarID, Record<TestCarSchema>>>("cars")
        let calls = Var<SetExpr<Record<TestCarSchema>>>("calls")
        let closed = Record<TestCarSchema>.literal(
            .init(TestCarSchema.floor, 0),
            .init(TestCarSchema.doorsOpen, false)
        )
        let open = Record<TestCarSchema>.literal(
            .init(TestCarSchema.floor, 1),
            .init(TestCarSchema.doorsOpen, true)
        )
        let bindings = [
            ActionParameter("person", values: TestPersonID.finiteValues).actionBinding,
            ActionParameter("car", values: TestCarID.finiteValues).actionBinding,
            ActionParameter("direction", values: TestDirection.finiteValues).actionBinding
        ]
        let builderActions: [(String, ActionExpr, [ActionBinding])] = [
            ("move", cars.becomes(cars.updating(.carA) { car in
                car.updating(TestCarSchema.floor, to: 2)
            }), bindings),
            ("readCar", floor.becomes(cars[.carA][TestCarSchema.floor]), []),
            ("initialize", cars.becomes(
                Function<TestCarID, Record<TestCarSchema>>.literal((.carA, closed), (.carB, open))), []),
            ("insertCall", calls.inserting(closed), []),
            ("removeCall", calls.removing(closed), []),
            ("containsCall", calls.contains(closed) && floor.becomes(1), [])
        ]

        #expect(parsed.diagnostics.isEmpty)
        #expect(Set(parsed.variables.map(\.name)) == ["floor", "cars", "calls"])
        #expect(parsed.actions.count == builderActions.count)
        #expect(parsed.actions[0].bindings.map(\.generatedSwiftType) == ["PersonID", "CarID", "Direction"])
        for (parsedAction, builtAction) in zip(parsed.actions, builderActions) {
            #expect(parsedAction.name == builtAction.0)
            #expect(parsedAction.body == builtAction.1)
            #expect(parsedAction.bindings.map(\.name) == builtAction.2.map(\.name))
            #expect(parsedAction.bindings.map(\.values) == builtAction.2.map(\.values))
        }
    }

    @Test func diagnosesUnsupportedTypedUpdateAtItsSource() throws {
        let source = """
        {
            Action("update", parameters: [
                ActionParameter("person", values: ["alice", "bob"])
            ]) {
                car.becomes(car.updating(CarSchema.field(dynamicKeyPath), to: 2))
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Parameterized action 'update' contains an unsupported typed update; use a directly written finite enum case or schema field token."
        ])
        #expect(parsed.diagnostics.first?.source.contains("dynamicKeyPath") == true)
    }

    @Test func macroAcceptsLocalEnumFiniteDomainsInOrderedBindings() throws {
        #expect(TypedFacadeEnumDomainMacro.spec.actions.first?.bindings == [
            ActionBinding(name: "person", values: [.string("alice"), .string("bob")]),
            ActionBinding(name: "car", values: [.string("carA"), .string("carB")]),
            ActionBinding(name: "direction", values: [.string("up"), .string("down")])
        ])
    }

    @Test("macro parser and result builder produce one generated surface identity")
    func macroParserAndResultBuilderShareGeneratedSurfaceIdentity() throws {
        let compilation = try TypedFacadeEnumDomainMacro.spec.compile()

        #expect(compilation.identity.value == TypedFacadeEnumDomainMacro._expectedCompilationIdentity)
        _ = try TypedFacadeEnumDomainMacro.makeMachine()
    }

    @Test func rejectsUnsupportedInvariantSource() throws {
        let source = """
        {
            Invariant("bad") {
                mode == CameraMode.unknown
            }
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.invariants.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Invariant 'bad' contains an unsupported invariant expression."
        ])
    }

    @Test func parseEnumInvariant() throws {
        let source = """
        {
            Invariant("notError") {
                mode != CameraMode.error
            }
        }
        """
        let enumDefinitions = [
            parserEnum("CameraMode", cases: ["idle": .string("idle"), "error": .string("error")])
        ]
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: enumDefinitions)
        #expect(parsed.invariants.count == 1)
        #expect(parsed.invariants[0].body == .notEqual(.variable("mode"), .value(.string("error"))))
    }

    @Test func parseInitializedEnumVar() throws {
        let source = """
        {
            let mode = Var<CameraMode>(CameraMode.idle)
        }
        """
        let closure = try parseClosure(source)
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.variables.count == 1)
        #expect(parsed.variables[0].name == "mode")
        #expect(parsed.variables[0].initialization == .value(.string("idle")))
        #expect(parsed.variables[0].generatedSwiftType == "CameraMode")
    }

}

private enum TestPersonID: String, FiniteTLAValueDomain {
    case alice, bob
    static var defaultValue: Self { .alice }
    static let finiteValues = [Self.alice, .bob]
}

@TLAModel
private struct DefinePhaseGeneratedModel {
    enum Step: String, CaseIterable { case stay }

    enum Mode: String, FiniteTLAValueDomain {
        case define

        static var defaultValue: Self { .define }
        static let finiteValues = [Self.define]
    }

    static var spec: TLASpec {
        #spec("DefinePhaseGeneratedModel") {
            Algorithm("Phase", scoped: { scope in
                let mode: SharedVariable<Mode> = scope.sharedVar("mode", initial: .define)
                Do(Step.stay) { Assign(mode, to: mode) }
            })
            FormalDefinition("Visible", parameters: [], body: true, plusCalPhase: .define)
        }
    }
}

@Suite(.serialized) struct DefinePhaseGeneratedModelTests {
    @Test("generated models retain definitions in the authored PlusCal define section")
    func keepsDefinePhaseDeclaration() throws {
        let plusCal = try DefinePhaseGeneratedModel.spec.compile().renderedPlusCalBundle().root.tla
        let define = try #require(plusCal.range(of: "define {"))
        let visible = try #require(plusCal.range(of: "Visible == TRUE"))
        #expect(define.lowerBound < visible.lowerBound)
    }
}

@TLAModel
private struct FormalDefinitionFidelityMacro {
    static var spec: TLASpec {
        TLASpec("FormalDefinitionFidelityMacro") {
            let value = Var<Int>("value")
            Variable(value, 0)
            FormalDefinition("Refines", parameters: [], body: true)
            SwiftTLA.Action("stay") { value.stays }
        }
    }
}

@Suite(.serialized) struct FormalDefinitionFidelityMacroTests {
    @Test func generatedModelRetainsFormalDefinition() throws {
        #expect(FormalDefinitionFidelityMacro.spec.formalOperatorDefinitions.map(\.name) == ["Refines"])
        _ = try FormalDefinitionFidelityMacro.spec.compile()
    }
}

@TLAModel
private struct TypedFacadeEnumDomainMacro {
    enum PersonID: String, FiniteTLAValueDomain {
        case alice, bob
        static var defaultValue: Self { .alice }
        static let finiteValues = [Self.alice, .bob]
    }

    enum CarID: String, FiniteTLAValueDomain {
        case carA, carB
        static var defaultValue: Self { .carA }
        static let finiteValues = [Self.carA, .carB]
    }

    enum Direction: String, FiniteTLAValueDomain {
        case up, down
        static var defaultValue: Self { .up }
        static let finiteValues = [Self.up, .down]
    }

    static var spec: TLASpec {
        TLASpec("TypedFacadeEnumDomainMacro") {
            let floor = Var<Int>("floor")
            Variable(floor, 0)
            SwiftTLA.Action("move", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                floor.becomes(1)
            }
        }
    }
}

private enum TestCarID: String, FiniteTLAValueDomain {
    case carA, carB
    static var defaultValue: Self { .carA }
    static let finiteValues = [Self.carA, .carB]
}

private enum TestDirection: String, FiniteTLAValueDomain {
    case up, down
    static var defaultValue: Self { .up }
    static let finiteValues = [Self.up, .down]
}

private struct TestCarFields {
    let floor: Int
    let doorsOpen: Bool
}

private enum TestCarSchema: TLARecordSchema {
    typealias Fields = TestCarFields
    static func fieldName<Value>(for field: KeyPath<TestCarFields, Value>) -> String? {
        let key = field as AnyKeyPath
        if key == \TestCarFields.floor { return "floor" }
        if key == \TestCarFields.doorsOpen { return "doorsOpen" }
        return nil
    }

    static let floor = field(\TestCarFields.floor)
    static let doorsOpen = field(\TestCarFields.doorsOpen)
    static let fields = [
        TLARecordFieldDeclaration(floor, default: 0),
        TLARecordFieldDeclaration(doorsOpen, default: false)
    ]
}
