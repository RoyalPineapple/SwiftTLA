import Testing
import SwiftSyntax
import SwiftParser
import SwiftTLA
import SwiftTLAMacros

// Proves SpecParser's compact decoder produces the same AST as the runtime
// builder for every expression form in the DSL. Each test parses a source
// string and compares the result to the equivalent value built through
// Swift's type system (operator overloads and method calls).

// MARK: - Helpers

private func parseExpression(_ source: String) -> ExprSyntax {
    Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
}

private func parserEnum(
    _ typeName: String,
    cases: TLARecord = .init([]),
    formalDomain: [TLAValue]? = nil
) -> ParserEnumDefinition {
    .init(typeName: typeName, cases: cases, formalDomain: formalDomain)
}

@Suite(.serialized) struct AlgorithmBuilderParsingTests {
    private func compile(
        _ parsed: SpecParser.ParsedSpecComponents,
        named name: String
    ) throws -> CompiledSpecification {
        try parsed.compile(specificationName: name)
    }

    @Test("Algorithm Each Do syntax lowers through the ordinary parser AST")
    func parsesBoundedAlgorithm() throws {
        let source = """
        {
            Algorithm("Counter") {
                let count = SharedVar(initial: 0)
                Each(Node.all) { node in
                    Do("increment") {
                        Await(count < 2)
                        Assign(count, to: count + 1)
                    }
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Node", formalDomain: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let compilation = try compile(parsed, named: "Counter")
        let specification = compilation.spec
        #expect(specification.variables.map(\.name) == ["pc", "count"])
        #expect(specification.actions.map(\.name) == ["increment", "Terminating"])
        #expect(specification.actions.first?.bindings == [
            ActionBinding(name: "process", values: [.string("left"), .string("right")])
        ])
        let facts = parsed.machineSurfaceSwiftFacts(for: compilation)
        #expect(facts.actionBindingTypes["increment"] == ["process": "Node"])
    }

    @Test("Algorithm parser rejects declarations it does not lower")
    func rejectsUnsupportedAlgorithmDeclaration() {
        let source = """
        {
            Algorithm("Unsupported") {
                UnsupportedAlgorithmConstruct()
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.actions.isEmpty)
        #expect(
            parsed.diagnostics.first?.message
                == "Unsupported Algorithm declaration 'UnsupportedAlgorithmConstruct()'. "
                    + "Supported declarations are SharedVar, Macro, Procedure, Each, Do, While, and properties."
        )
    }

    @Test("parser lowers the mechanical PlusCal statements through the shared IR")
    func parsesMechanicalPlusCalStatements() throws {
        let source = """
        {
            Algorithm("Counter") {
                let count = SharedVar(initial: 0)
                Each(Node.all, fairness: .strong) { node in
                    While("increment", count < 2) {
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
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Node", formalDomain: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try compile(parsed, named: "Counter").spec
        #expect(specification.invariants.map(\.name) == ["__pcal_assert_increment_0_0", "__pcal_assert_increment_0_1"])
        #expect(specification.fairness == [
            .strongFairnessActionCall(.init(name: "increment", arguments: [.string("left")])),
            .strongFairnessActionCall(.init(name: "increment", arguments: [.string("right")]))
        ])
    }

    @Test("Algorithm parser preserves a process-bound formal lambda application")
    func parsesProcessScopedFormalLambdaApplication() throws {
        let source = """
        {
            Algorithm("ScopedFormalLambda") {
                let counters = SharedVar(initial: Function<Worker, Int>.literal(
                    (.left, 0),
                    (.right, 0)
                ))
                Each(Worker.all) { worker in
                    Do("advance") {
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
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Worker", formalDomain: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try compile(parsed, named: "ScopedFormalLambda").spec
        #expect(specification.actions.map(\.name) == ["advance", "Terminating"])
        #expect(specification.actions.first?.body.description.contains("LAMBDA value : (value + 1)") == true)
    }

    @Test("formal operator parsing failure retains all six diagnostic fields")
    func malformedFormalLambdaRetainsSixFieldDiagnostic() {
        let source = """
        {
            Algorithm("MalformedFormalLambda") {
                let counter = SharedVar(initial: 0)
                Do("advance") {
                    Assign(counter, to: Expr<Int>(StateExpr.operatorApplication(
                        .lambda(FormalLambda(parameters: [], body: .int(1))),
                        [.value(counter.expr.raw)]
                    )))
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)
        guard let diagnostic = parsed.diagnostics.first else {
            Issue.record("Expected a malformed formal-lambda diagnostic")
            return
        }

        #expect(diagnostic.description.contains("What failed:") == true)
        #expect(diagnostic.description.contains("Where:") == true)
        #expect(diagnostic.description.contains("Expected:") == true)
        #expect(diagnostic.description.contains("Actual:") == true)
        #expect(diagnostic.description.contains("Change status:") == true)
        #expect(diagnostic.description.contains("Next safe action:") == true)
    }

    @Test("parser lowers ordered multi-source With bindings")
    func parsesThreeIndependentWithBindings() throws {
        let source = """
        {
            Algorithm("ThreeWith") {
                let selected = SharedVar(initial: 0)
                Do("choose") {
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
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try compile(parsed, named: "ThreeWith").spec
        #expect(specification.actions.first?.body.description.contains("__pcal_with_0") == true)
        #expect(specification.actions.first?.body.description.contains("__pcal_with_2") == true)
    }

    @Test("parser preserves a bounded statement macro through compilation")
    func parsesStatementMacro() throws {
        let source = """
        {
            Algorithm("MacroLock") {
                let lock = SharedVar(initial: 1)
                let acquire = Macro { (value: MacroParameter<Int>) in
                    Await(value == 1)
                    Assign(value, to: 0)
                }
                Each(Node.all) { _ in
                    Do("acquire") { acquire(lock) }
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Node", formalDomain: [.string("left"), .string("right")])]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try compile(parsed, named: "MacroLock").spec
        #expect(specification.actions.map(\.name) == ["acquire", "Terminating"])
        #expect(specification.actions.first?.body.description.contains("lock") == true)
    }

    @Test("parser expands every statement macro parameter in caller scope")
    func parsesTwoParameterStatementMacro() throws {
        let source = """
        {
            Algorithm("CopyValue") {
                let destination = SharedVar(initial: 0)
                let source = SharedVar(initial: 7)
                let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                    Assign(target, to: value.expr)
                }
                Do("copy") { copy(destination, source) }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try compile(parsed, named: "CopyValue").spec
        #expect(specification.actions.first?.body.description.contains("destination' = source") == true)
        #expect(specification.actions.first?.body.description.contains("__pcal_macro_parameter") == false)
    }

    @Test("parser retains formal expression macro arguments")
    func parsesExpressionStatementMacroArguments() throws {
        let source = """
        {
            Algorithm("OffsetValue") {
                let destination = SharedVar(initial: 0)
                let source = SharedVar(initial: 7)
                let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                    Assign(target, to: value.expr)
                }
                Do("copy") { copy(destination, source.expr + 1) }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try compile(parsed, named: "OffsetValue").spec
        #expect(specification.actions.first?.body.description.contains("destination' = (source + 1)") == true)
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
                Do("vote") { vote(Pair.literal(1, 2)) }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try compile(parsed, named: "PairVote").spec
        #expect(specification.actions.first?.body.description.contains("SafeAt(1, 2)") == true)
    }

    @Test("parser rejects an expression used for a macro assignment target")
    func diagnosesExpressionMacroAssignmentTarget() {
        let source = """
        {
            Algorithm("InvalidMacroTarget") {
                let destination = SharedVar(initial: 0)
                let write = Macro { (target: MacroParameter<Int>) in
                    Assign(target, to: 1)
                }
                Do("write") { write(destination.expr + 1) }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.actions.isEmpty)
        let diagnostic = parsed.diagnostics.first?.message ?? ""
        #expect(diagnostic.contains("What failed: statement macro 'write' assigns through parameter"))
        #expect(diagnostic.contains("Expected a formal variable assignment target"))
        #expect(diagnostic.contains("What changed: no model was changed"))
        #expect(diagnostic.contains("Next safe action"))
    }

    @Test("source model compiles procedure bindings to deterministic formal slots")
    func parsesTypedProcedureBindings() throws {
        let source = """
        {
            Algorithm("ProcedureSource") {
                let output = SharedVar(initial: 0)
                Procedure("work", parameters: Int.self) { value in
                    let offset = LocalVar(initial: 1)
                    Do("enter") {
                        Await(value.expr >= 0)
                        Assign(output, to: value.expr + offset.expr)
                        Return()
                    }
                }
                Do("start") { Call("work", with: 7) }
                Do("finished") { Stop() }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try compile(parsed, named: "ProcedureSource").spec
        #expect(specification.variables.contains { $0.name == "parameter0" })
        #expect(specification.actions.contains { $0.name == "procedure.work.enter" })
    }

    @Test("statement macro arity diagnostics identify the declaration and safe repair")
    func diagnosesStatementMacroArity() {
        let source = """
        {
            Algorithm("BadMacroCall") {
                let destination = SharedVar(initial: 0)
                let source = SharedVar(initial: 7)
                let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                    Assign(target, to: value.expr)
                }
                Do("copy") { copy(destination) }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.first?.message.contains("Statement macro 'copy' expects 2 arguments but received 1.") == true)
    }

    @Test("parser expands a parameterless statement macro")
    func parsesParameterlessStatementMacro() throws {
        let source = """
        {
            Algorithm("ParameterlessMacro") {
                let count = SharedVar(initial: 0)
                let increment = Macro {
                    Assign(count, to: count + 1)
                }
                Do("increment") { increment() }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        let specification = try compile(parsed, named: "ParameterlessMacro").spec
        #expect(specification.actions.first?.body.description.contains("count' = (count + 1)") == true)
    }

    @Test("parser retains a filtered formal function initial domain")
    func parsesFilteredFunctionInitialDomain() throws {
        let source = """
        {
            Algorithm("FunctionDomain") {
                let successors = SharedVar(in: Where(
                    Functions(from: Node.all, to: Subsets(of: SetExpr<Node>.literal(.first, .second)))
                ) { successor in
                    All(Node.all) { node in
                        successor[node].cardinality == 1
                    }
                })
                Do("done") { Stop() }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum(
                "Node",
                cases: ["first": .string("first"), "second": .string("second")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let compilation = try compile(parsed, named: "FunctionDomain")
        let successors = try #require(compilation.spec.variables.first { $0.name == "successors" })
        #expect(parsed.machineSurfaceSwiftFacts(for: compilation).variableTypes["successors"] == "Function<Node, SetExpr<Node>>")
        #expect(successors.initialSet?.description.contains("Cardinality") == true)
    }

    @Test("parser retains a typed record-valued function comprehension")
    func parsesRecordFunctionComprehension() throws {
        let source = """
        {
            Algorithm("RecordFunction") {
                let cars = SharedVar(initial: Function<Car, Record<Model.CarRecord>>.mapping { _ in
                    Record.literal(
                        .init(Model.CarRecord.floor, 4),
                        .init(Model.CarRecord.door, .closed)
                    )
                })
                Do("hold") { Assign(cars, to: cars.expr) }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [
                parserEnum("Door", cases: ["closed": .string("closed")]),
                parserEnum("Car", formalDomain: [.string("north"), .string("south")])
            ]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try compile(parsed, named: "RecordFunction").spec
        let carsDeclaration = try #require(specification.variables.first { $0.name == "cars" })
        guard case .function(let cars) = carsDeclaration.initial else {
            Issue.record("Expected cars to retain a formal finite function")
            return
        }
        #expect(cars.count == 2)
        #expect(cars.values.allSatisfy { value in
            guard case .record(let fields) = value else { return false }
            return fields["floor"] == .int(4) && fields["door"] == .string("closed")
        })
    }

    @Test("parser retains an empty typed set in a function comprehension")
    func parsesEmptySetFunctionComprehension() throws {
        let source = """
        {
            Algorithm("Votes") {
                let votes = SharedVar(initial: Function<Acceptor, SetExpr<Int>>.mapping { _ in SetExpr() })
                Do("hold") { Assign(votes, to: votes.expr) }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Acceptor", formalDomain: [.string("a1"), .string("a2")])]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try compile(parsed, named: "Votes").spec
        let votesDeclaration = try #require(specification.variables.first { $0.name == "votes" })
        guard case .function(let votes) = votesDeclaration.initial else {
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
                    Do("hold") {
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
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum(
                "Node",
                cases: ["one": .int(1), "two": .int(2)]
            )]
        )

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try compile(parsed, named: "FiniteFunction").spec
        #expect(specification.actions.first?.body.description.contains("CASE") == true)
        #expect(specification.actions.first?.body.description.contains("_typedFunctionEntry") == true)
    }

    @Test("source model compiles a static formal selection")
    func parsesStaticFormalSelection() throws {
        let source = """
        {
            Algorithm("StaticChoice") {
                let selected = Select(
                    from: SetExpr<Int>.literal(1, 2, 3),
                    matching: { value in value.expr % 2 == 0 }
                )
                let current = SharedVar(initial: selected)
                Do("done") { Stop() }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        let specification = try compile(parsed, named: "StaticChoice").spec
        #expect(specification.variables.first { $0.name == "current" }?.initial == .int(2))
    }

    @Test("parser expands a statement macro with the current process identifier")
    func parsesStatementMacroWithProcessIdentifier() throws {
        let source = """
        {
            Algorithm("MacroProcess") {
                let marked = SharedVar(initial: Function<Node, Bool>.literal((Node.left, false), (Node.right, false)))
                let mark = Macro { (node: MacroParameter<Node>) in
                    Assign(marked, to: marked.updating(node, to: true))
                }
                Each(Node.all) { node in
                    Do("mark") { mark(node) }
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum(
                "Node",
                cases: ["left": .string("left"), "right": .string("right")]
            )]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try compile(parsed, named: "MacroProcess").spec
        let body = try? #require(specification.actions.first?.body)
        #expect(body?.description.contains("process") == true)
        #expect(body?.description.contains("__pcal_macro_parameter") == false)
    }

    @Test("parser uses a PlusCal label enum's declared raw value")
    func parsesDeclaredRawAlgorithmLabel() throws {
        let source = """
        {
            Algorithm("RawLabel") {
                Each(Node.all) { _ in
                    Do(Step.resourceManager) { Stop() }
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [
                parserEnum("Step", cases: ["resourceManager": .string("RS")]),
                parserEnum("Node", formalDomain: [.string("left"), .string("right")])
            ]
        )

        #expect(parsed.diagnostics.isEmpty)
        let specification = try compile(parsed, named: "RawLabel").spec
        #expect(specification.actions.map(\.name) == ["RS", "Terminating"])
    }

    @Test("parsed and result-builder algorithms compile to the same declarations")
    func parserTreeMatchesRuntimeAlgorithm() throws {
        let source = """
        {
            Algorithm("Counter") {
                let count = SharedVar(initial: 0)
                Each(Node.all) { _ in
                    Do("increment") {
                        Await(count < 2)
                        Assign(count, to: count + 1)
                    }
                }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Node", formalDomain: [.string("left"), .string("right")])]
        )
        let runtime = TLASpec("Counter") {
            Algorithm("Counter") {
                let count = SharedVar("count", initial: 0)
                count
                Each(ParserNode.all) { _ in
                    Do("increment") {
                        Await(count < 2)
                        Assign(count, to: count + 1)
                    }
                }
            }
        }
        let runtimeSpecification = try runtime.compile().spec
        let runtimeTree = canonicalTestSpec(
            variables: runtimeSpecification.variables.map { ($0.name, $0.initial, $0.initialSet) },
            actions: runtimeSpecification.actions.map { ($0.name, $0.body, $0.bindings) },
            invariants: runtimeSpecification.invariants.map { ($0.name, $0.body) }
        )
        let parserSpecification = try compile(parsed, named: "Counter").spec
        let parserTree = canonicalTestSpec(
            variables: parserSpecification.variables.map { ($0.name, $0.initial, $0.initialSet) },
            actions: parserSpecification.actions.map { ($0.name, $0.body, $0.bindings) },
            invariants: parserSpecification.invariants.map { ($0.name, $0.body) }
        )
        #expect(_tlaAlphaEquivalent(parserTree, runtimeTree))
    }
}

private enum ParserNode: String, FiniteDomainKey {
    case left
    case right

    static let formalDomain: [ParserNode] = [.left, .right]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.parser-node")

    var tlaValue: TLAValue { .string(rawValue) }
}

// MARK: - StateExpr: literals

@Suite(.serialized) struct StateExprLiteralTests {
    @Test func parseInts() {
        #expect(SpecParser.decodeStateExpr(parseExpression("0")) == .value(.int(0)))
        #expect(SpecParser.decodeStateExpr(parseExpression("42")) == .value(.int(42)))
    }

    @Test func parseBools() {
        #expect(SpecParser.decodeStateExpr(parseExpression("true")) == .value(.bool(true)))
        #expect(SpecParser.decodeStateExpr(parseExpression("false")) == .value(.bool(false)))
    }

    @Test func parseStrings() {
        #expect(SpecParser.decodeStateExpr(parseExpression("\"hello\"")) == .value(.string("hello")))
        #expect(SpecParser.decodeStateExpr(parseExpression("\"left\"")) == .value(.string("left")))
        #expect(SpecParser.decodeStateExpr(parseExpression("\"\"")) == .value(.string("")))
    }
}

// MARK: - StateExpr: variables

@Suite(.serialized) struct StateExprVariableTests {
    @Test func parseVariableReferences() {
        #expect(SpecParser.decodeStateExpr(parseExpression("x")) == .variable("x"))
        #expect(SpecParser.decodeStateExpr(parseExpression("count")) == .variable("count"))
        #expect(SpecParser.decodeStateExpr(parseExpression("direction")) == .variable("direction"))
    }
}

@Suite(.serialized) struct SpecVariableDeclarationParsingTests {
    @Test func plainVarDeclarationIsParsedWithoutGenericSpecialization() {
        let source = """
        {
            let counter = Var("counter", 0)
            Variable(counter, in: 0...1)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.count == 1)
        guard parsed.variables.count == 1 else { return }
        #expect(parsed.variables[0].name == "counter")
        #expect(parsed.variables[0].initial == .set([.int(0), .int(1)]))
        #expect(parsed.variables[0].initialSet == .setLiteral([.value(.int(0)), .value(.int(1))]))
        #expect(parsed.variables[0].swiftTypeName == "Int")
    }

    @Test func oneArgumentVariableReferencesPreserveBindingMetadataAndOrder() {
        let source = """
        {
            let queued = Var("queued", TLAValue.set([]))
            Variable(queued)
            let phase = Var("phase", 0)
            Variable(phase)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.variables.count == 2)
        #expect(parsed.variables[0].name == "queued")
        #expect(parsed.variables[0].initial == .set([]))
        #expect(parsed.variables[0].swiftTypeName == "TLAValue")
        #expect(parsed.variables[1].name == "phase")
        #expect(parsed.variables[1].initial == .int(0))
        #expect(parsed.variables[1].swiftTypeName == "Int")
    }

    @Test func finiteVariableDomainsCompareAsFormalSets() {
        let parsed = canonicalTestSpec(
            variables: [(
                name: "counter",
                initial: .set([.int(0), .int(1)]),
                initialSet: .setLiteral([.int(0), .int(1)])
            )],
            actions: [],
            invariants: []
        )
        let built = canonicalTestSpec(
            variables: [(
                name: "counter",
                initial: .set([.int(0), .int(1)]),
                initialSet: .setLiteral([.int(1), .int(0)])
            )],
            actions: [],
            invariants: []
        )

        #expect(_tlaAlphaEquivalent(parsed, built))
    }

    @Test func fidelityDifferenceRetainsTheFirstFormalNodeAndRecoveryAction() {
        let parserTree = canonicalTestSpec(
            variables: [(
                name: "counter",
                initial: .int(0),
                initialSet: nil
            )],
            actions: [("advance", .assign("counter", .int(1)), [])],
            invariants: []
        )
        let builderTree = canonicalTestSpec(
            variables: [(
                name: "counter",
                initial: .int(0),
                initialSet: nil
            )],
            actions: [("advance", .assign("counter", .int(2)), [])],
            invariants: []
        )

        let evidence = _tlaFidelityEvidence(parserTree, builderTree)

        #expect(evidence?.whatFailed == "action body differs after alpha normalization")
        #expect(evidence?.location == .semanticPath("actions[0].body (advance)"))
        #expect(evidence?.expected.contains("assign(counter,value(1))") == true)
        #expect(evidence?.actual.contains("assign(counter,value(2))") == true)
        #expect(evidence?.changeStatus == .noSpecificationWasCommitted)
        #expect(evidence?.nextSafeAction.contains("#spec body") == true)
        #expect(evidence?.description.contains("What failed:") == true)
        #expect(evidence?.description.contains("Next safe action:") == true)
    }

    @Test func formalOperatorDefinitionsArePartOfParserBuilderFidelity() {
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

        let evidence = _tlaFidelityEvidence(parserTree, builderTree)

        #expect(!_tlaAlphaEquivalent(parserTree, builderTree))
        #expect(evidence?.location == .semanticPath("formalOperatorDefinitions[0] (increment)"))
        #expect(evidence?.expected.contains("value(1)") == true)
        #expect(evidence?.actual.contains("value(2)") == true)
        #expect(evidence?.changeStatus == .noSpecificationWasCommitted)
        #expect(evidence?.sourceSpan.description == "source span unavailable")
        #expect(evidence?.nextSafeAction.contains("FormalDefinition") == true)
    }

    @Test func literalDefinitionsAreRetainedForParserBuilderFidelity() {
        let source = """
        {
            Definition("Refines == C!Spec")
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)
        let parserTree = canonicalTestSpec(
            variables: [], actions: [], invariants: [], definitions: parsed.definitions
        )
        let builderTree = canonicalTestSpec(
            variables: [], actions: [], invariants: [], definitions: [.init(text: "Refines == C!Spec")]
        )

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.definitions == [.init(text: "Refines == C!Spec")])
        #expect(_tlaAlphaEquivalent(parserTree, builderTree))
        #expect(_tlaFidelityEvidence(parserTree, builderTree) == nil)
    }

    @Test func dynamicDefinitionProducesStructuredDiagnostic() {
        let source = """
        {
            let body = "Refines == C!Spec"
            Definition(body)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.definitions.isEmpty)
        #expect(parsed.diagnostics.count == 1)
        #expect(parsed.diagnostics.first?.message == "Definition requires a literal TLA+ declaration.")
        #expect(parsed.diagnostics.first?.expected == "Definition(\"Name == expression\")")
    }

    @Test func formalDefinitionParameterNamesAreAlphaEquivalent() {
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

        #expect(_tlaAlphaEquivalent(parserTree, builderTree))
        #expect(_tlaFidelityEvidence(parserTree, builderTree) == nil)
    }

    @Test func formalDefinitionIsParsedIntoTheCanonicalFormalModel() {
        let source = """
        {
            FormalDefinition(
                "increment",
                parameters: [.value("value")],
                body: value + 1
            )
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
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

    @Test func formalDefinitionRetainsTypedFiniteFunctionBodies() {
        let source = """
        {
            FormalDefinition(
                "InitialState",
                parameters: [],
                body: Function<Key, Int>.mapping { _ in 0 }.raw
            )
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [parserEnum("Key", formalDomain: [.string("k1"), .string("k2")])]
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

    @Test func higherOrderFormalDefinitionRoundTripsThroughTheCanonicalParser() {
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
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
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

    @Test func algorithmTypedFormalDefinitionParsesWithClosureBinders() {
        let source = """
        {
            Algorithm("Formal") {
                FormalDefinition("same", taking: Int.self, Int.self) { ballot, value in
                    ballot == value
                }
                let count = SharedVar("count", initial: 0)
                count
                Do("stop") { Stop() }
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "same",
                parameters: [.value("value0"), .value("value1")],
                body: .equal(.variable("value0"), .variable("value1"))
            )
        ])
        let built = Algorithm("Formal") {
            FormalDefinition("same", taking: Int.self, Int.self) { left, right in left == right }
            let count = SharedVar("count", initial: 0)
            count
            Do("stop") { Stop() }
        }
        #expect(_tlaAlgorithmFidelityEvidence(parsed.algorithmFidelityTokens, [AlgorithmFidelityToken(model: built.model)]) == nil)
    }

    @Test func typedFormalDefinitionParsesClosureBindersAndLocalRecursion() {
        let source = """
        {
            FormalDefinition("SafeAt", taking: Int.self, Int.self) { ballot, limit in
                LetRec("SA", over: IntRange(0, through: limit), taking: Int.self, { recursion, current in
                    If(current == 0, then: true, else: recursion(current.expr - 1))
                }, in: { recursion in recursion(ballot.expr) })
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
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
        #expect(operators[0].body.description.contains("SA["))
        #expect(result.description == "SA[value0]")
    }

    @Test func typedFormalDefinitionParsesPairLiterals() {
        let source = """
        {
            FormalDefinition("PairAt", taking: Int.self, Int.self) { ballot, value in
                Pair.literal(ballot.expr, value.expr) == Pair.literal(0, 1)
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.isEmpty, "\(parsed.diagnostics)")
        #expect(parsed.formalOperatorDefinitions.first?.body.description == "<<value0, value1>> = <<0, 1>>")
    }

    @Test func formalOperatorLambdaAndArgumentKindsRoundTripThroughTheParser() {
        let expression = parseExpression("""
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

    @Test func explicitlyTypedBinaryFormalCallPreservesItsArguments() {
        let built: Expr<Bool> = FormalCall(as: Bool.self, "SafeAt", 3, 5)
        let parsed = SpecParser.decodeTypedFacadeValue(
            parseExpression("FormalCall(as: Bool.self, \"SafeAt\", 3, 5)"),
            substitutions: [:]
        )

        #expect(parsed == built.stateExpr)
        #expect(built.stateExpr == .operatorApplication(
            .reference("SafeAt", arity: 2), [.value(3), .value(5)]
        ))
    }

    @Test func localOperatorParameterNamesAreAlphaEquivalent() {
        let parserTree = canonicalTestSpec(
            variables: [],
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
            variables: [],
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

        #expect(_tlaAlphaEquivalent(parserTree, builderTree))
        #expect(_tlaFidelityEvidence(parserTree, builderTree) == nil)
    }

    @Test func parserDiagnosticRetainsSourceSpanAndNoCommitStatus() {
        let source = """
        {
            Variable(missing)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        guard let diagnostic = parsed.diagnostics.first else {
            Issue.record("Expected a diagnostic for the unbound variable declaration")
            return
        }
        #expect(diagnostic.source == "Variable(missing)")
        #expect(diagnostic.expected == "a supported SwiftTLA declaration or expression")
        #expect(diagnostic.actual == "Variable(missing)")
        #expect(diagnostic.changeStatus == .noFormalModelWasBuilt)
        #expect(diagnostic.sourceSpan.utf8Length == "Variable(missing)".utf8.count)
        #expect(diagnostic.description.contains("Where:") == true)
        #expect(diagnostic.description.contains("Next safe action:") == true)
    }

    @Test func oneArgumentVariableRejectsUnboundReference() {
        let source = """
        {
            Variable(missing)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.variables.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == ["Variable 'missing' is not bound by a prior Var declaration"])
    }

    @Test func variableReferenceRejectsMalformedDeclaration() {
        let source = """
        {
            let phase = Var("phase", 0)
            Variable(phase, bogus: 1)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.diagnostics.map(\.message) == ["Malformed Variable declaration"])
    }
}

// MARK: - StateExpr: arithmetic operators

@Suite(.serialized) struct StateExprArithmeticTests {
    @Test func parseArithmetic() {
        #expect(SpecParser.decodeStateExpr(parseExpression("x + 5")) == StateExpr.add(.variable("x"), .value(.int(5))))
        #expect(SpecParser.decodeStateExpr(parseExpression("x - 3")) == StateExpr.subtract(.variable("x"), .value(.int(3))))
        #expect(SpecParser.decodeStateExpr(parseExpression("x * 2")) == StateExpr.multiply(.variable("x"), .value(.int(2))))
        #expect(SpecParser.decodeStateExpr(parseExpression("x / 4")) == StateExpr.divide(.variable("x"), .value(.int(4))))
        #expect(SpecParser.decodeStateExpr(parseExpression("x % 7")) == StateExpr.modulo(.variable("x"), .value(.int(7))))
    }
}

// MARK: - StateExpr: comparison operators

@Suite(.serialized) struct StateExprComparisonTests {
    @Test func parseComparisons() {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.decodeStateExpr(parseExpression("x == y")) == StateExpr.equal(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x != y")) == StateExpr.notEqual(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x < y")) == StateExpr.lessThan(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x <= y")) == StateExpr.lessOrEqual(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x > y")) == StateExpr.greaterThan(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x >= y")) == StateExpr.greaterOrEqual(x, y))
    }
}

// MARK: - StateExpr: logical and prefix operators

@Suite(.serialized) struct StateExprLogicalPrefixTests {
    @Test func parseLogical() {
        let x: StateExpr = .variable("x")
        let y: StateExpr = .variable("y")
        #expect(SpecParser.decodeStateExpr(parseExpression("x && y")) == StateExpr.and(x, y))
        #expect(SpecParser.decodeStateExpr(parseExpression("x || y")) == StateExpr.or(x, y))
    }

    @Test func parsePrefix() {
        let x: StateExpr = .variable("x")
        #expect(SpecParser.decodeStateExpr(parseExpression("!x")) == StateExpr.not(x))
        #expect(SpecParser.decodeStateExpr(parseExpression("-x")) == StateExpr.negate(x))
        #expect(SpecParser.decodeStateExpr(parseExpression("-1")) == StateExpr.value(.int(-1)))
    }

    @Test func preservesSwiftInfixPrecedence() {
        let index: StateExpr = .variable("index")
        let count: StateExpr = .variable("count")
        #expect(
            SpecParser.decodeStateExpr(parseExpression("index <= count + 1"))
                == StateExpr.lessOrEqual(index, .add(count, .value(.int(1))))
        )
    }

    @Test func parseParenthesized() {
        #expect(SpecParser.decodeStateExpr(parseExpression("(x)")) == .variable("x"))
    }
}

// MARK: - StateExpr: range operator

@Suite(.serialized) struct StateExprRangeTests {
    @Test func parseRangeOperator() {
        #expect(SpecParser.decodeStateExpr(parseExpression("1...3")) == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))]))
        #expect(SpecParser.decodeStateExpr(parseExpression("0...2")) == StateExpr.setLiteral([.value(.int(0)), .value(.int(1)), .value(.int(2))]))
    }
}

// MARK: - StateExpr: member access properties

@Suite(.serialized) struct StateExprMemberAccessTests {
    @Test func parseKnownProperties() {
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(parseExpression("s.cardinality")) == StateExpr.cardinality(s))
        #expect(SpecParser.decodeStateExpr(parseExpression("s.flattened")) == StateExpr.unionAll(s))
        #expect(SpecParser.decodeStateExpr(parseExpression("s.subsets")) == StateExpr.powerSet(s))
        #expect(SpecParser.decodeStateExpr(parseExpression("s.domain")) == StateExpr.domain(s))
        #expect(SpecParser.decodeStateExpr(parseExpression("s.count")) == StateExpr.tupleLength(s))
    }

    @Test func parseUnknownPropertyAsRecordAccess() {
        #expect(SpecParser.decodeStateExpr(parseExpression("msg.type")) == StateExpr.recordAccess(.variable("msg"), "type"))
        #expect(SpecParser.decodeStateExpr(parseExpression("ballot.val")) == StateExpr.recordAccess(.variable("ballot"), "val"))
    }
}

// MARK: - StateExpr: method calls (binary)

@Suite(.serialized) struct StateExprBinaryMethodTests {
    @Test func parseBinaryMethods() {
        let x: StateExpr = .variable("x")
        let s: StateExpr = .variable("s")
        #expect(SpecParser.decodeStateExpr(parseExpression("x.isIn(s)")) == StateExpr.in(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.union(s)")) == StateExpr.union(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.intersection(s)")) == StateExpr.intersection(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.subtracting(s)")) == StateExpr.setDifference(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.isSubset(of: s)")) == StateExpr.subset(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.applying(s)")) == StateExpr.functionApply(x, s))
        let filterResult = SpecParser.decodeStateExpr(parseExpression("x.filtering(s)"))
        #expect(filterResult?.description.contains("\\in") == true)
        let mapResult = SpecParser.decodeStateExpr(parseExpression("x.mapping(s)"))
        #expect(mapResult?.description.contains(":") == true)
        #expect(SpecParser.decodeStateExpr(parseExpression("x.appending(s)")) == StateExpr.tupleAppend(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.concatenating(s)")) == StateExpr.tupleConcatenate(x, s))
        #expect(SpecParser.decodeStateExpr(parseExpression("x.integerDivided(by: 2)")) == StateExpr.integerDivide(x, .value(.int(2))))
    }
}

// MARK: - StateExpr: method calls (multi-arg)

@Suite(.serialized) struct StateExprMultiArgMethodTests {
    @Test func parseUpdated() {
        let f: StateExpr = .variable("f")
        #expect(SpecParser.decodeStateExpr(parseExpression("f.updated(at: 0, to: 1)")) == StateExpr.except(f, .value(.int(0)), .value(.int(1))))
    }

    @Test func parseAt() {
        #expect(
            SpecParser.decodeStateExpr(parseExpression("t.at(3)"))
                == StateExpr.tupleAccess(.variable("t"), 3)
        )
    }
}

// MARK: - StateExpr: static calls

@Suite(.serialized) struct StateExprStaticCallTests {
    @Test func parseStaticSet() {
        #expect(
            SpecParser.decodeStateExpr(parseExpression("StateExpr.set([1, 2, 3])"))
                == StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        )
    }

    @Test func parseStaticTuple() {
        #expect(SpecParser.decodeStateExpr(parseExpression("StateExpr.tuple([1, x])")) == StateExpr.tupleLiteral([.value(.int(1)), .variable("x")]))
    }

    @Test func parseStaticRecord() {
        #expect(
            SpecParser.decodeStateExpr(parseExpression("StateExpr.record(name: x, age: 42)"))
                == StateExpr.record(["name": .variable("x"), "age": .value(.int(42))])
        )
    }

    @Test func parseStaticIf() {
        let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.if(x == 0, then: 1, else: 2)"))
        #expect(result == StateExpr.ifThenElse(
            StateExpr.equal(.variable("x"), .value(.int(0))),
            .value(.int(1)),
            .value(.int(2))
        ))
    }

    @Test func parseStaticEnabled() {
        #expect(SpecParser.decodeStateExpr(parseExpression("StateExpr.enabled(\"Next\")")) == StateExpr.enabledAction("Next"))
    }

    @Test func parseStaticFunction() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.function(domain: StateExpr.set([1, 2]), x + 1)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("|->") && d.contains("x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticForAll() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.for(allIn: StateExpr.set([1, 2]), x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("\\A x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticExists() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.exists(in: StateExpr.set([1, 2]), x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("\\E x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticChoose() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.choose(from: StateExpr.set([1, 2]), matching: x > 0)")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("CHOOSE x") && d.contains("{1, 2}"))
    }

    @Test func parseStaticAny() {
        guard let result = SpecParser.decodeStateExpr(parseExpression("StateExpr.any(from: StateExpr.set([1, 2]))")) else {
            #expect(Bool(false)); return
        }
        let d = result.description
        #expect(d.contains("CHOOSE x") && d.contains("TRUE"))
    }

    @Test func parseStaticFirstMatchWithFallback() {
        let result = SpecParser.decodeStateExpr(
            parseExpression("StateExpr.firstMatch((when: x == 0, then: 10), (when: x == 1, then: 20), fallback: 99)")
        )
        #expect(result == StateExpr.caseExpr(
            [
                StateExpr.equal(.variable("x"), .value(.int(0))), .value(.int(10)),
                StateExpr.equal(.variable("x"), .value(.int(1))), .value(.int(20))
            ],
            .value(.int(99))
        ))
    }

    @Test func parseStaticFirstMatchNoFallback() {
        let result = SpecParser.decodeStateExpr(
            parseExpression("StateExpr.firstMatch((when: x < 0, then: -1))")
        )
        #expect(result == StateExpr.caseExpr(
            [StateExpr.lessThan(.variable("x"), .value(.int(0))), StateExpr.value(.int(-1))],
            nil
        ))
    }
}

// MARK: - ActionExpr: basic assignments

@Suite(.serialized) struct ActionExprBasicTests {
    @Test func parseBecomes() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(5)")) == ActionExpr.assign("x", .value(.int(5))))
        #expect(
            SpecParser.decodeActionExpr(parseExpression("x.becomes(x + 1)"))
                == ActionExpr.assign("x", StateExpr.add(.variable("x"), .value(.int(1))))
        )
    }

    @Test func parseStays() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.stays")) == ActionExpr.unchanged("x"))
    }

    @Test func parseGuardedBecomes() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(1).when(x == 0)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseDoubleWhen() {
        let result = SpecParser.decodeActionExpr(parseExpression("x.becomes(1).when(x > 0).when(x < 5)"))
        #expect(result == ActionExpr.and(
            ActionExpr.guard_(StateExpr.and(
                StateExpr.lessThan(.variable("x"), .value(.int(5))),
                StateExpr.greaterThan(.variable("x"), .value(.int(0)))
            )),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseNondeterministicAssign() {
        let result = SpecParser.decodeActionExpr(
            parseExpression("x.becomes(StateExpr.any(from: StateExpr.set([1, 2, 3])))")
        )
        let expectedSet = StateExpr.setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))])
        #expect(result == ActionExpr.chooseAction("x", expectedSet))
    }
}

// MARK: - ActionExpr: AND / OR combinations

@Suite(.serialized) struct ActionExprCombinatorTests {
    @Test func parseAndOfTwoActions() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(1) && y.becomes(2)")) == ActionExpr.and(
            ActionExpr.assign("x", .value(.int(1))),
            ActionExpr.assign("y", .value(.int(2)))
        ))
    }

    @Test func parseOrOfTwoActions() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(1) || x.becomes(2)")) == ActionExpr.or(
            ActionExpr.assign("x", .value(.int(1))),
            ActionExpr.assign("x", .value(.int(2)))
        ))
    }

    @Test func parseGuardAndAction() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x > 0 && x.becomes(x - 1)")) == ActionExpr.and(
            ActionExpr.guard_(StateExpr.greaterThan(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", StateExpr.subtract(.variable("x"), .value(.int(1))))
        ))
    }

    @Test func parseActionAndGuard() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x.becomes(0) && x == 0")) == ActionExpr.and(
            ActionExpr.assign("x", .value(.int(0))),
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0))))
        ))
    }

    @Test func parseStateOrAction() {
        #expect(SpecParser.decodeActionExpr(parseExpression("x == 0 || x.becomes(1)")) == ActionExpr.or(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(0)))),
            ActionExpr.assign("x", .value(.int(1)))
        ))
    }

    @Test func parseHourClockStyleNestedOr() {
        let result = SpecParser.decodeActionExpr(
            parseExpression("(x != 12) && x.becomes(x + 1) || (x == 12) && x.becomes(1)")
        )
        let left = ActionExpr.and(
            ActionExpr.guard_(StateExpr.notEqual(.variable("x"), .value(.int(12)))),
            ActionExpr.assign("x", StateExpr.add(.variable("x"), .value(.int(1))))
        )
        let right = ActionExpr.and(
            ActionExpr.guard_(StateExpr.equal(.variable("x"), .value(.int(12)))),
            ActionExpr.assign("x", .value(.int(1)))
        )
        #expect(result == ActionExpr.or(left, right))
    }
}

// MARK: - ActionExpr: closure parsing

@Suite(.serialized) struct ActionExprClosureTests {
    @Test func parseEmptyClosure() {
        let closure = parseClosure("{}")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.guard_(.value(.bool(true))))
    }

    @Test func parseSingleStatementClosure() {
        let closure = parseClosure("{ x.becomes(1) }")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.assign("x", .value(.int(1))))
    }

    @Test func parseMultiStatementClosure() {
        let closure = parseClosure("{ x.becomes(1) ; y.stays }")
        #expect(SpecParser.decodeActionFromClosure(closure) == ActionExpr.and(
            ActionExpr.assign("x", .value(.int(1))),
            ActionExpr.unchanged("y")
        ))
    }
}

private func parseClosure(_ source: String) -> ClosureExprSyntax {
    guard case .expr(let expr) = Parser.parse(source: source).statements.first!.item,
          let closure = expr.as(ClosureExprSyntax.self)
    else { fatalError("Not a closure: \(source)") }
    return closure
}

// MARK: - TemporalExpr

@Suite(.serialized) struct TemporalExprTests {
    @Test func parseLeadsTo() {
        #expect(
            SpecParser.decodeTemporal(parseExpression("x.leadsTo(y)").as(FunctionCallExprSyntax.self)!)
                == TemporalExpr.leadsTo(.variable("x"), .variable("y"))
        )
    }

    @Test func parseLeadsToWithExpressions() {
        let result = SpecParser.decodeTemporal(parseExpression("(x > 0).leadsTo(y == 0)").as(FunctionCallExprSyntax.self)!)
        #expect(result == TemporalExpr.leadsTo(
            StateExpr.greaterThan(.variable("x"), .value(.int(0))),
            StateExpr.equal(.variable("y"), .value(.int(0)))
        ))
    }
}

// MARK: - FairnessCondition

@Suite(.serialized) struct FairnessConditionTests {
    @Test func parseWeakFairness() throws {
        #expect(
            SpecParser.decodeFairness(try #require(parseExpression("x.weakFairness(\"Tick\")").as(FunctionCallExprSyntax.self)))
                == FairnessCondition.weakFairness("Tick")
        )
    }

    @Test func parseStrongFairness() throws {
        #expect(
            SpecParser.decodeFairness(try #require(parseExpression("x.strongFairness(\"Tick\")").as(FunctionCallExprSyntax.self)))
                == FairnessCondition.strongFairness("Tick")
        )
    }

    @Test func parseAggregateFairnessDeclaration() throws {
        #expect(
            SpecParser.decodeFairness(try #require(parseExpression("WeakFairnessNext()").as(FunctionCallExprSyntax.self)))
                == FairnessCondition.weakFairnessNext
        )
    }

    @Test func parseUnknownReturnsNil() {
        #expect(SpecParser.decodeFairness(parseExpression("x.unknown()").as(FunctionCallExprSyntax.self)!) == nil)
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
    @Test func enumFactsDoNotLeakFromOneParseIntoTheNextDecoderCall() {
        let closure = Parser.parse(source: """
        {
            Invariant("idleOnly") { mode == CameraMode.idle }
        }
        """).statements.first!.item.as(ClosureExprSyntax.self)!

        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.invariants.first?.body == .equal(.variable("mode"), .value(.string("idle"))))
        #expect(
            SpecParser.decodeStateExpr(parseExpression("CameraMode.idle"))
                == .recordAccess(.variable("CameraMode"), "idle")
        )
    }

    @Test func parseQualifiedEnumCaseInInvariant() {
        let source = """
        {
            Invariant("idleOnly") {
                mode == CameraMode.idle
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.invariants.count == 1)
        #expect(parsed.invariants[0].body == .equal(.variable("mode"), .value(.string("idle"))))
    }

    @Test func parseEnumAssignment() {
        let source = """
        {
            Action("test") {
                mode.becomes(CameraMode.live)
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.actions.count == 1)
        #expect(parsed.actions[0].body == .assign("mode", .value(.string("live"))))
    }

    @Test func parsesVariadicActionParametersInDeclarationOrder() {
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
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)
        #expect(parsed.actions.count == 1)
        #expect(parsed.actions[0].bindings.map(\.name) == ["person", "elevator", "direction"])
        #expect(parsed.actions[0].bindings.map(\.values) == [
            [.int(1), .int(2)], [.int(10), .int(20)], [.int(100), .int(200)]
        ])
        #expect(parsed.actions[0].body == .assign("floor", .value(.int(1))))
    }

    @Test func diagnosesInvalidDomainsAtEveryParameterPosition() {
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
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)
        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Parameterized action 'moveElevator' parameter 'person' requires an explicitly written finite values array.",
            "Parameterized action 'moveElevator' parameter 'elevator' requires a non-empty finite values array.",
            "Parameterized action 'moveElevator' parameter 'direction' has duplicate finite-domain values."
        ])
    }

    @Test func normalizesTypedFacadeAndEnumDomainsToBuilderAST() {
        let source = """
        {
            let floor = Var<Int>("floor")
            let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
            let calls = Var<SetExpr<Record<CarSchema>>>("calls")
            Variable(floor, 0)
            Variable(cars)
            Variable(calls)
            Action("move", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                cars.becomes(cars.updating(CarID.carA) { car in
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
            parserEnum("Direction", cases: ["up": .string("up"), "down": .string("down")])
        ]
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
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
        for (parsedAction, builtAction) in zip(parsed.actions, builderActions) {
            #expect(parsedAction.name == builtAction.0)
            #expect(parsedAction.body == builtAction.1)
            #expect(parsedAction.bindings == builtAction.2)
        }
    }

    @Test func diagnosesUnsupportedTypedUpdateAtItsSource() {
        let source = """
        {
            Action("update", parameters: [
                ActionParameter("person", values: ["alice", "bob"])
            ]) {
                car.becomes(car.updating(CarSchema.field(dynamicKeyPath), to: 2))
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.actions.isEmpty)
        #expect(parsed.diagnostics.map(\.message) == [
            "Parameterized action 'update' contains an unsupported typed update; use a directly written finite enum case or schema field token."
        ])
        #expect(parsed.diagnostics.first?.source.contains("dynamicKeyPath") == true)
    }

    @Test func macroAcceptsLocalEnumFiniteDomainsInOrderedBindings() {
        #expect(TypedFacadeEnumDomainMacro.spec.actions.first?.bindings == [
            ActionBinding(name: "person", values: [.string("alice"), .string("bob")]),
            ActionBinding(name: "car", values: [.string("carA"), .string("carB")]),
            ActionBinding(name: "direction", values: [.string("up"), .string("down")])
        ])
    }

    @Test func parseInvalidEnumCaseReturnsNilForInvariant() {
        let source = """
        {
            Invariant("bad") {
                mode == CameraMode.unknown
            }
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.invariants.isEmpty)
        #expect(parsed.diagnostics.isEmpty)
    }

    @Test func parseEnumInvariant() {
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
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: enumDefinitions)
        #expect(parsed.invariants.count == 1)
        #expect(parsed.invariants[0].body == .notEqual(.variable("mode"), .value(.string("error"))))
    }

    @Test func parseInitializedEnumVar() {
        let source = """
        {
            let mode = Var<CameraMode>(CameraMode.idle)
        }
        """
        let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
        let parsed = SpecParser.parseSpecClosure(closure, enumDefinitions: [cameraModeDefinition])
        #expect(parsed.variables.count == 1)
        #expect(parsed.variables[0].name == "mode")
        #expect(parsed.variables[0].initial == .string("idle"))
        #expect(parsed.variables[0].swiftTypeName == "CameraMode")
    }
}

private enum TestPersonID: String, FiniteTLAValueDomain {
    case alice, bob
    static let finiteValues = [Self.alice, .bob]
}

@TLAModel
private struct DefinePhaseGeneratedModel {
    enum Mode: String, FiniteTLAValueDomain {
        case define

        static let finiteValues = [Self.define]
    }

    static var spec: TLASpec {
        #spec("DefinePhaseGeneratedModel") {
            Algorithm("Phase") {
                let mode: SharedVariable<Mode> = SharedVar(initial: .define)
                Do("stay") { Assign(mode, to: mode) }
            }
            Definition("Visible == TRUE", named: "Visible", plusCalPhase: .define)
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
private struct DefinitionFidelityMacro {
    static var spec: TLASpec {
        TLASpec("DefinitionFidelityMacro") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Definition("Refines == TRUE")
            Action("stay") { value.stays }
        }
    }
}

@Suite(.serialized) struct DefinitionFidelityMacroTests {
    @Test func generatedModelRetainsLiteralDefinition() {
        #expect(DefinitionFidelityMacro.spec.definitions == [.init(text: "Refines == TRUE")])
        _ = try DefinitionFidelityMacro.compiledSpecification()
    }
}

@TLAModel
private struct TypedFacadeEnumDomainMacro {
    enum PersonID: String, FiniteTLAValueDomain {
        case alice, bob
        static let finiteValues = [Self.alice, .bob]
    }

    enum CarID: String, FiniteTLAValueDomain {
        case carA, carB
        static let finiteValues = [Self.carA, .carB]
    }

    enum Direction: String, FiniteTLAValueDomain {
        case up, down
        static let finiteValues = [Self.up, .down]
    }

    static var spec: TLASpec {
        TLASpec("TypedFacadeEnumDomainMacro") {
            let floor = Var<Int>("floor")
            Variable(floor, 0)
            Action("move", parameters: [
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
    static let finiteValues = [Self.carA, .carB]
}

private enum TestDirection: String, FiniteTLAValueDomain {
    case up, down
    static let finiteValues = [Self.up, .down]
}

private struct TestCarFields {
    let floor: Int
    let doorsOpen: Bool
}

private enum TestCarSchema: TLARecordSchema {
    typealias Fields = TestCarFields
    static let fieldNames: Set<String> = ["floor", "doorsOpen"]
    static let defaultRecord: TLAValue = .record(["floor": .int(0), "doorsOpen": .bool(false)])

    static func fieldName<Value>(for field: KeyPath<TestCarFields, Value>) -> String? {
        let key = field as AnyKeyPath
        if key == \TestCarFields.floor { return "floor" }
        if key == \TestCarFields.doorsOpen { return "doorsOpen" }
        return nil
    }

    static let floor = field(\TestCarFields.floor)
    static let doorsOpen = field(\TestCarFields.doorsOpen)
}
