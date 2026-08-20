import Testing
@testable import SwiftTLA
import SwiftTLAMacros

private struct CompilerPipelineMember: Identifiable, Sendable {
    let id: Int
}

@TLAModel
private struct CompilerPipelineGeneratedModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineGeneratedModel") {
            let counter = Var<Int>("counter")
            Variable(counter, 0)
            Action("increment") { counter.becomes(counter + 1) }
        }
    }
}

@TLAModel
private struct CompilerPipelineExplicitFormalNameModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineExplicitFormalName") {
            let counter = Var<Int>("counter", 0)
            Variable(counter)
            Action("increment") { counter.becomes(counter + 1) }
        }
    }
}

@TLAModel
private struct CompilerPipelineAlgorithmModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineAlgorithmModel") {
            Algorithm("CompilerPipelineAlgorithmModel") {
                let count = SharedVar(initial: 0)
                Do("increment") {
                    Assign(count, to: count + 1)
                }
            }
        }
    }
}

@TLAModel
private struct CompilerPipelineInitializationModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineInitializationModel") {
            let computed = Var<Int>("computed")
            let choice = Var<Int>("choice")
            Variable(computed: computed) { computed + 1 }
            Variable(from: choice.name, StateExpr.set([1, 2]))
            Action("stay") { computed.stays && choice.stays }
        }
    }
}

@TLAModel
private struct CompilerPipelineCollectionModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineCollectionModel") {
            let devices = SymmetricCollectionVar<CompilerPipelineMember, Int>("devices")
            SymmetricCollection(devices, verificationScope: 2, initial: 0)
            CollectionAction("advance", on: devices) { member in
                devices[member] == 0 && devices.update(member, to: 1)
            }
        }
    }
}

@Suite("Compiler pipeline canonicalization")
struct CompilerPipelineCanonicalizationTests {
    @Test("macro compilation uses the explicit formal module name")
    func macroUsesExplicitFormalModuleName() throws {
        let compilation = try CompilerPipelineExplicitFormalNameModel.compiledSpecification()

        #expect(compilation.spec.name == "CompilerPipelineExplicitFormalName")
        #expect(compilation.identity == try CompilerPipelineExplicitFormalNameModel.spec.compile().identity)
    }

    @Test("direct specifications retain one identity through runtime and checker")
    func directSpecificationUsesOneCompiledPayload() throws {
        let counter = Var<Int>("counter", 0)
        let spec = TLASpec("CanonicalCounter") {
            Variable(counter, 0)
            Action("increment") {
                counter.becomes(counter + 1)
            }
            Invariant("NonNegative") { counter >= 0 }
        }

        let compilation = try spec.compile()
        let runtime = SpecRuntime(compilation: compilation)
        let checker = ModelChecker(compilation: compilation, maxStates: 3)

        #expect(runtime.compilation?.identity == compilation.identity)
        #expect(checker.compilation?.identity == compilation.identity)
        #expect(try runtime.successors(.init(name: "increment"), from: ["counter": .int(0)]) == [["counter": .int(1)]])
        #expect(try runtime.check("NonNegative", in: ["counter": .int(0)]))
        #expect(runtime.propertyOutcomes(in: ["counter": .int(0)]) == [.satisfied(name: "NonNegative")])
        #expect(try checker.exploreGraph().states.count == 3)
    }

    @Test("compiled layout assigns private IDs in declaration order")
    func compiledLayoutAssignsDeclarationIDs() throws {
        let spec = TLASpec(
            name: "Layout",
            variables: [
                .init(name: "first", initial: .int(0)),
                .init(name: "second", initial: .int(1))
            ],
            actions: [
                .init(name: "advance", body: .unchanged("first")),
                .init(name: "hold", body: .unchanged("second"))
            ],
            invariants: [.init(name: "Safe", body: .value(.bool(true)))]
        )

        let compilation = try spec.compile()

        #expect(compilation.layout.variableID(named: "first") == .init(ordinal: 0))
        #expect(compilation.layout.variableID(named: "second") == .init(ordinal: 1))
        #expect(compilation.layout.actionID(named: "advance") == .init(ordinal: 0))
        #expect(compilation.layout.actionID(named: "hold") == .init(ordinal: 1))
        #expect(compilation.layout.declarations.map(\.name) == ["first", "second", "advance", "hold", "Safe"])
    }

    @Test("compiled layout assigns scoped control-label identities")
    func compiledLayoutAssignsScopedControlLabelIDs() throws {
        let algorithm = Algorithm("ControlLayout") {
            let value = SharedVar("value", initial: 0)
            value
            Each(Node.all) { _ in
                Do("start") {
                    Assign(value, to: value + 1)
                }
            }
            Procedure("first") {
                Do("start") {
                    Return()
                }
            }
            Procedure("second") {
                Do("start") {
                    Return()
                }
            }
        }

        let compilation = try algorithm.lower().compile()
        let labels = compilation.layout.controlLabels

        #expect(labels.map(\.id) == [.init(ordinal: 0), .init(ordinal: 1), .init(ordinal: 2)])
        #expect(labels.map(\.sourceName) == ["start", "start", "start"])
        #expect(labels.map(\.renderedName) == ["start", "procedure.first.start", "procedure.second.start"])
        #expect(labels.map(\.owner) == [
            .process(algorithm: "ControlLayout", ordinal: 0, typeName: "Node"),
            .procedure(algorithm: "ControlLayout", name: "first"),
            .procedure(algorithm: "ControlLayout", name: "second")
        ])
        #expect(compilation.identity != try Algorithm("ControlLayout") {
            let value = SharedVar("value", initial: 0)
            value
            Each(Node.all) { _ in
                Do("changed") {
                    Assign(value, to: value + 1)
                }
            }
            Procedure("first") {
                Do("start") {
                    Return()
                }
            }
            Procedure("second") {
                Do("start") {
                    Return()
                }
            }
        }.lower().compile().identity)
    }

    @Test("compiled actions use declaration and binder identities")
    func compiledActionsUsePrivateIdentities() throws {
        let spec = TLASpec(
            name: "CompiledActions",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [
                .init(
                    name: "step",
                    body: .existsAction(
                        "current",
                        .setLiteral([.int(1)]),
                        .assign("counter", .variable("current"))
                    )
                )
            ],
            invariants: []
        )

        let compilation = try spec.compile()

        guard case .existsAction(let binder, _, .assign(let variable, .boundValue(let value))) = compilation.model.actions[0].body else {
            Issue.record("Expected a compiled binder assignment")
            return
        }
        #expect(variable == .init(ordinal: 0))
        #expect(value == binder)
    }

    @Test("compiled choices are visible to their action guards and updates")
    func compiledChoicesUseSelectedSlotValues() throws {
        let spec = TLASpec(
            name: "CompiledChoice",
            variables: [
                .init(name: "counter", initial: .int(0)),
                .init(name: "candidate", initial: .int(0))
            ],
            actions: [
                .init(
                    name: "select",
                    body: .chooseAction("candidate", .setLiteral([.int(1), .int(2)]))
                        && .guard_(.equal(.variable("candidate"), .int(2)))
                        && .assign("counter", .variable("candidate"))
                )
            ],
            invariants: []
        )
        let compilation = try spec.compile()
        let state = try FormalState(formalValues: [.int(0), .int(0)], compilation: compilation)
        let nextStates = try CompiledActionEnumerator(state: state, model: compilation.model)
            .enumerate(try #require(compilation.model.actions.first))

        #expect(nextStates.count == 1)
        #expect(try nextStates[0].value(for: .init(ordinal: 0)) == .integer(2))
        #expect(try nextStates[0].value(for: .init(ordinal: 1)) == .integer(2))
    }

    @Test("compiled action bindings enumerate their declared values")
    func compiledActionBindingsUseBinderSlots() throws {
        let spec = TLASpec(
            name: "CompiledActionBinding",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [
                .init(
                    name: "advance",
                    body: .assign("counter", .variable("increment")),
                    bindings: [.init(name: "increment", values: [.int(1), .int(2)])]
                )
            ],
            invariants: []
        )
        let compilation = try spec.compile()
        let state = try FormalState(formalValues: [.int(0)], compilation: compilation)
        let next = try CompiledActionEnumerator(state: state, model: compilation.model)
            .enumerate(try #require(compilation.model.actions.first))

        let values = try next.map { try $0.value(for: .init(ordinal: 0)) }
        #expect(Set(values) == [.integer(1), .integer(2)])
    }

    @Test("compiled formal calls use operator identities")
    func compiledFormalCallsUseOperatorIDs() throws {
        let double = FormalOperatorDefinition(
            name: "Double",
            parameters: [.value("value")],
            body: .multiply(.variable("value"), .int(2))
        )
        let spec = TLASpec(
            name: "CompiledFormalCall",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [
                .init(
                    name: "advance",
                    body: .assign(
                        "counter",
                        .operatorApplication(.reference("Double", arity: 1), [.value(.int(2))])
                    )
                )
            ],
            invariants: [],
            formalOperatorDefinitions: [double]
        )
        let compilation = try spec.compile()
        let state = try FormalState(formalValues: [.int(0)], compilation: compilation)
        let next = try CompiledActionEnumerator(state: state, model: compilation.model)
            .enumerate(try #require(compilation.model.actions.first))

        guard case .assign(_, .operatorApplication(.reference(let id, _), _)) = compilation.model.actions[0].body else {
            Issue.record("Expected an operator identity")
            return
        }
        #expect(compilation.bindings.operators["Double"] == id)
        #expect(try #require(next.first).value(for: .init(ordinal: 0)) == .integer(4))
    }

    @Test("compiled higher-order calls bind operator identities")
    func compiledHigherOrderCallsBindOperatorIDs() throws {
        let applyTwice = FormalOperatorDefinition(
            name: "ApplyTwice",
            parameters: [.operator("operation", arity: 1), .value("initial")],
            body: .operatorApplication(
                .reference("operation", arity: 1),
                [.value(.operatorApplication(
                    .reference("operation", arity: 1),
                    [.value(.variable("initial"))]
                ))]
            )
        )
        let increment = FormalOperator.lambda(.init(
            parameters: ["value"],
            body: .add(.variable("value"), .int(1))
        ))
        let spec = TLASpec(
            name: "CompiledHigherOrderCall",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [
                .init(
                    name: "advance",
                    body: .assign(
                        "counter",
                        .operatorApplication(
                            .reference("ApplyTwice", arity: 2),
                            [.operator(increment), .value(.int(4))]
                        )
                    )
                )
            ],
            invariants: [],
            formalOperatorDefinitions: [applyTwice]
        )
        let compilation = try spec.compile()
        let state = try FormalState(formalValues: [.int(0)], compilation: compilation)
        let next = try CompiledActionEnumerator(state: state, model: compilation.model)
            .enumerate(try #require(compilation.model.actions.first))

        #expect(try #require(next.first).value(for: .init(ordinal: 0)) == .integer(6))
    }

    @Test("compiled runtime enumerates slot-backed initial and successor states")
    func compiledRuntimeUsesSlotsForExecution() throws {
        let spec = TLASpec(
            name: "CompiledRuntime",
            variables: [
                .init(name: "counter", initial: .int(0)),
                .init(name: "choice", initialSet: .setLiteral([.int(1), .int(2)]))
            ],
            actions: [
                .init(
                    name: "advance",
                    body: .guard_(.lessThan(.variable("counter"), .variable("choice")))
                        && .assign("counter", .add(.variable("counter"), .int(1)))
                )
            ],
            invariants: [.init(name: "Bounded", body: .lessOrEqual(.variable("counter"), .variable("choice"))]
        )
        let compilation = try spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try runtime.initialStates()

        #expect(initial.count == 2)
        let firstSuccessor = try runtime.successors(from: try #require(initial.first))
        #expect(firstSuccessor.count == 1)
        #expect(try runtime.invariantHolds(compilation.model.invariants[0], in: firstSuccessor[0].state))

        let exploration = try ModelChecker(compilation: compilation, maxStates: 10).explore()
        #expect(exploration.graph.states.count == 5)
        #expect(exploration.isComplete)
    }

    @Test("compiled higher-order calls retain lambda binder identities")
    func compiledHigherOrderCallsUsePrivateIdentities() throws {
        let call = StateExpr.operatorApplication(
            .lambda(.init(parameters: ["current"], body: .equal(.variable("current"), .int(1)))),
            [.value(.int(1))]
        )
        let spec = TLASpec(
            name: "CompiledLambda",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "step", body: .guard_(call) && .unchanged("counter"))],
            invariants: []
        )

        let compilation = try spec.compile()

        guard case .and(.guard_(.operatorApplication(.lambda(let lambda), _)), .unchanged) = compilation.model.actions[0].body else {
            Issue.record("Expected a compiled higher-order call")
            return
        }
        guard case .equal(.boundValue(let value), _) = lambda.body else {
            Issue.record("Expected a compiled lambda binder")
            return
        }
        #expect(value == lambda.parameters[0])
    }

    @Test("compiled ranges retain their bound variable identities")
    func compiledRangesUseBoundPaths() throws {
        let spec = TLASpec(
            name: "CompiledRange",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "step", body: .guard_(.in(.int(1), .integerRange(.variable("counter"), .int(2))))],
            invariants: []
        )

        let compilation = try spec.compile()

        guard case .guard_(.in(_, .integerRange(.stateVariable(let value), _))) = compilation.model.actions[0].body else {
            Issue.record("Expected a compiled integer range")
            return
        }
        #expect(value == compilation.layout.variables[0].id)
    }

    @Test("formal state stores values by compiled variable identity")
    func formalStateUsesVariableSlots() throws {
        let spec = TLASpec(
            name: "FormalState",
            variables: [
                .init(name: "first", initial: .int(1)),
                .init(name: "second", initial: .int(2)),
            ],
            actions: [],
            invariants: []
        )
        let compilation = try spec.compile()
        let first = compilation.layout.variables[0].id
        let second = compilation.layout.variables[1].id
        let state = try FormalState(formalValues: [.int(1), .int(2)], compilation: compilation)
        let updated = try state.updating(second, to: .integer(3))

        #expect(try state.value(for: first) == .integer(1))
        #expect(try state.value(for: second) == .integer(2))
        #expect(try updated.value(for: first) == .integer(1))
        #expect(try updated.value(for: second) == .integer(3))
    }

    @Test("compiled runtimes reject states from another declaration layout")
    func compiledRuntimeRejectsForeignState() throws {
        let first = try TLASpec(
            name: "FirstLayout",
            variables: [.init(name: "count", initial: .int(0))],
            actions: [],
            invariants: []
        ).compile()
        let second = try TLASpec(
            name: "SecondLayout",
            variables: [.init(name: "count", initial: .int(0))],
            actions: [],
            invariants: []
        ).compile()

        let foreignState = try FormalState(formalValues: [.int(0)], compilation: first)
        #expect(throws: CompiledEvaluationError.self) {
            try CompiledRuntime(compilation: second).successors(from: foreignState)
        }
    }

    @Test("compiled evaluator reads slots and binders without names")
    func compiledEvaluatorUsesPrivateIdentities() throws {
        let spec = TLASpec(
            name: "CompiledEvaluation",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [
                .init(
                    name: "step",
                    body: .existsAction(
                        "current",
                        .setLiteral([.int(1)]),
                        .guard_(.equal(.add(.variable("counter"), .variable("current")), .int(2)))
                    )
                )
            ],
            invariants: []
        )
        let compilation = try spec.compile()
        let state = try FormalState(formalValues: [.int(1)], compilation: compilation)

        guard case .existsAction(let binder, _, .guard_(let expression)) = compilation.model.actions[0].body else {
            Issue.record("Expected a compiled action binder")
            return
        }
        let result = try CompiledEvaluator(
            state: state,
            model: compilation.model,
            bindings: .init().binding(.integer(1), to: binder)
        ).evaluate(expression)

        #expect(result == .boolean(true))
    }

    @Test("compiled evaluator executes local operators through bound values")
    func compiledEvaluatorExecutesLocalOperators() throws {
        let expression = StateExpr.letIn(
            [LocalOperator("increment", parameters: ["value"], body: .add(.variable("value"), .int(1)))],
            .equal(.recursiveCall("increment", [.int(1)]), .int(2))
        )
        let spec = TLASpec(
            name: "CompiledLocalOperator",
            variables: [],
            actions: [.init(name: "step", body: .guard_(expression))],
            invariants: []
        )
        let compilation = try spec.compile()
        let state = try FormalState(formalValues: [], compilation: compilation)

        guard case .guard_(let compiled) = compilation.model.actions[0].body else {
            Issue.record("Expected a compiled guard")
            return
        }
        #expect(try CompiledEvaluator(state: state, model: compilation.model).evaluate(compiled) == .boolean(true))
    }

    @Test("compiled actions update formal state by variable identity")
    func compiledActionsUpdateFormalState() throws {
        let spec = TLASpec(
            name: "CompiledActionExecution",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "step", body: .assign("counter", .add(.variable("counter"), .int(1))))],
            invariants: []
        )
        let compilation = try spec.compile()
        let state = try FormalState(formalValues: [.int(1)], compilation: compilation)

        let successors = try CompiledActionEnumerator(state: state, model: compilation.model).enumerate(compilation.model.actions[0])

        #expect(successors.count == 1)
        #expect(try successors[0].value(for: compilation.layout.variables[0].id) == .integer(2))
    }

    @Test("declaration order changes the compilation identity")
    func declarationOrderChangesCompilationIdentity() throws {
        let first = TLASpec(
            name: "LayoutIdentity",
            variables: [
                .init(name: "first", initial: .int(0)),
                .init(name: "second", initial: .int(1))
            ],
            actions: [],
            invariants: []
        )
        let second = TLASpec(
            name: "LayoutIdentity",
            variables: [
                .init(name: "second", initial: .int(1)),
                .init(name: "first", initial: .int(0))
            ],
            actions: [],
            invariants: []
        )

        #expect(try first.compile().identity != second.compile().identity)
    }

    @Test("compiled descriptions preserve declaration order without exposing runtime slots")
    func compiledDescriptionPreservesDeclaredOrder() throws {
        let compilation = try TLASpec(
            name: "Description",
            variables: [
                .init(name: "count", initial: .int(0)),
                .init(name: "limit", initial: .int(10))
            ],
            actions: [.init(name: "advance", body: .unchanged("count"))],
            invariants: []
        ).compile()

        #expect(compilation.description.identity == compilation.identity)
        #expect(compilation.description.variables.map(\.name) == ["count", "limit"])
        #expect(compilation.description.actions.map(\.name) == ["advance"])
        #expect(compilation.description.imports.map(\.name) == ["Description"])
    }

    @Test("#spec Algorithm lowering reaches macro-generated consumers through one identity")
    func algorithmSpecificationUsesMacroCompiledPayload() throws {
        let compilation = try CompilerPipelineAlgorithmModel.compiledSpecification()

        #expect(CompilerPipelineAlgorithmModel.runtime.compilation?.identity == compilation.identity)
        #expect(try CompilerPipelineAlgorithmModel.verifySpec() > 0)
        #expect(try CompilerPipelineAlgorithmModel.transitionMatrix().isEmpty == false)
        #expect(try compilation.renderedTLAModuleBundle().tla == try CompilerPipelineAlgorithmModel.spec.compile().renderedTLAModuleBundle().tla)
    }

    @Test("duplicate declarations fail with an actionable typed diagnostic")
    func duplicateVariableBlocksCompilation() {
        let spec = TLASpec(
            name: "Invalid",
            variables: [NamedVar(name: "value", initial: .int(0)), NamedVar(name: "value", initial: .int(1))],
            actions: [],
            invariants: []
        )

        #expect(throws: CompilationDiagnostic.self) {
            try spec.compile()
        }
    }

    @Test("binding resolves variables and nested binders before execution")
    func bindingResolvesScopedNames() throws {
        let quantified = StateExpr.forAll(
            .setLiteral([.int(1)]),
            "current",
            .exists(
                .setLiteral([.int(2)]),
                "current",
                .equal(.variable("current"), .int(2))
            )
        )
        let spec = TLASpec(
            name: "Binding",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "step", body: .guard_(quantified) && .unchanged("counter"))],
            invariants: []
        )

        let compilation = try spec.compile()

        #expect(compilation.bindings.variables["counter"] == .init(ordinal: 0))
        #expect(compilation.bindings.references.values.contains(.binder(.init(ordinal: 0))))
        #expect(compilation.bindings.references.values.contains(.binder(.init(ordinal: 1))))
    }

    @Test("free references fail at the binding gate")
    func freeReferenceBlocksCompilation() {
        let spec = TLASpec(
            name: "FreeReference",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "step", body: .assign("counter", .variable("missing")))],
            invariants: []
        )

        do {
            _ = try spec.compile()
            Issue.record("Expected a binding diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unknownReference)
            #expect(diagnostic.stage == .binding)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }

    @Test("assignment to an action binder fails at the binding gate")
    func assignmentToBinderBlocksCompilation() {
        let spec = TLASpec(
            name: "BinderAssignment",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [
                .init(
                    name: "step",
                    body: .existsAction("current", .setLiteral([.int(1)]), .assign("current", .int(1)))
                )
            ],
            invariants: []
        )

        do {
            _ = try spec.compile()
            Issue.record("Expected a binding diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .assignmentToBinder)
            #expect(diagnostic.stage == .binding)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }

    @Test("unlinked formal symbols fail at the binding gate")
    func unresolvedFormalSymbolBlocksCompilation() {
        let spec = TLASpec(
            name: "UnresolvedSymbol",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [
                .init(
                    name: "step",
                    body: .guard_(.operatorApplication(.reference("Missing", arity: 0), []))
                        && .unchanged("counter")
                )
            ],
            invariants: []
        )

        do {
            _ = try spec.compile()
            Issue.record("Expected a binding diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unresolvedImportedSymbol)
            #expect(diagnostic.stage == .binding)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }

    @Test("local recursive operators remain visible throughout their LET body")
    func localRecursiveOperatorRemainsInScope() throws {
        let recursive = StateExpr.letIn(
            [
                .init(
                    "countDown",
                    parameters: ["current"],
                    domain: .integerRange(.int(0), .int(2)),
                    body: .equal(.variable("current"), .int(0))
                )
            ],
            .functionApply(.variable("countDown"), .int(1))
        )
        let spec = TLASpec(
            name: "LocalRecursion",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "step", body: .guard_(recursive) && .unchanged("counter"))],
            invariants: []
        )

        _ = try spec.compile()
    }

    @Test("macro-generated consumers and rendering retain the compiled identity")
    func macroGeneratedConsumersUseCompiledPayload() throws {
        let compilation = try CompilerPipelineGeneratedModel.compiledSpecification()

        #expect(CompilerPipelineGeneratedModel.runtime.compilation?.identity == compilation.identity)
        #expect(try CompilerPipelineGeneratedModel.verifySpec() > 0)
        #expect(try CompilerPipelineGeneratedModel.transitionMatrix().isEmpty == false)
        #expect(try compilation.renderedTLAModuleBundle().tla == try CompilerPipelineGeneratedModel.spec.compile().renderedTLAModuleBundle().tla)
    }

    @Test("#spec lowering preserves every canonical variable initialization field")
    func specMacroRetainsInitializationForms() throws {
        let compilation = try CompilerPipelineInitializationModel.compiledSpecification()
        let computed = try #require(compilation.spec.variables.first { $0.name == "computed" })
        let choice = try #require(compilation.spec.variables.first { $0.name == "choice" })

        #expect(computed.initExpr == .add(.variable("computed"), .int(1)))
        #expect(computed.lazySet == nil)
        #expect(choice.initExpr == nil)
        #expect(choice.lazySet == .setLiteral([.value(.int(1)), .value(.int(2))]))
        #expect(CompilerPipelineInitializationModel.runtime.compilation?.identity == compilation.identity)
    }

    @Test("#spec lowering preserves symmetric collection metadata")
    func specMacroRetainsSymmetricCollectionMetadata() throws {
        let compilation = try CompilerPipelineCollectionModel.compiledSpecification()
        let devices = try #require(compilation.spec.variables.first { $0.name == "devices" })
        let declaration = try #require(compilation.spec.symmetricCollections.first { $0.name == "devices" })

        #expect(devices.collectionType == .dictionary(2))
        #expect(declaration.variable == devices)
        #expect(declaration.verificationScope == 2)
        #expect(CompilerPipelineCollectionModel.runtime.compilation?.identity == compilation.identity)
    }

    @Test("semantic compilation fields change the identity")
    func semanticFieldsContributeToIdentity() throws {
        let base = TLASpec(
            name: "Fingerprint",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [NamedAction(name: "step", body: .assign("value", .int(1)))],
            invariants: []
        )
        let variants = [
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], checkDeadlock: true),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], theorems: ["Safety == TRUE"]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], recursiveDefs: ["CountDown(_)"]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], recursiveFuncs: [.init(name: "CountDown", params: ["n"], body: .variable("n"))]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], symmetricCollections: [.init(name: "members", verificationScope: 1, initial: .int(0))]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], extendsModules: "Naturals")
        ]

        let identity = try base.compile().identity
        for variant in variants {
            #expect(try variant.compile().identity != identity)
        }
    }

    @Test("identity includes action domains, all initialisation forms, and imported semantics")
    func structuralFieldsContributeToIdentity() throws {
        let base = TLASpec(
            name: "StructuralFingerprint",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [NamedAction(name: "step", body: .assign("value", .int(1)), bindings: [
                .init(name: "choice", values: [.int(0), .int(1)])
            ])],
            invariants: []
        )
        let importedA = TLASpec(
            name: "Imported",
            variables: [NamedVar(name: "inner", initial: .int(0))],
            actions: [NamedAction(name: "stay", body: .unchanged("inner"))],
            invariants: []
        )
        let importedB = TLASpec(
            name: "Imported",
            variables: [NamedVar(name: "inner", initial: .int(1))],
            actions: [NamedAction(name: "stay", body: .unchanged("inner"))],
            invariants: []
        )
        let variants = [
            TLASpec(name: "StructuralFingerprint", variables: base.variables, actions: [
                .init(name: "step", body: .assign("value", .int(1)), bindings: [.init(name: "choice", values: [.int(0), .int(2)])])
            ], invariants: []),
            TLASpec(name: "StructuralFingerprint", variables: [
                .init(name: "value", initial: .int(0), initExpr: .value(.int(1)))
            ], actions: base.actions, invariants: []),
            TLASpec(name: "StructuralFingerprint", variables: [
                .init(name: "value", initial: .int(0), collectionType: .dictionary(2))
            ], actions: base.actions, invariants: []),
            TLASpec(name: "StructuralFingerprint", variables: base.variables, actions: base.actions, invariants: [], imports: [importedA]),
            TLASpec(name: "StructuralFingerprint", variables: base.variables, actions: base.actions, invariants: [], imports: [importedB])
        ]

        let identity = try base.compile().identity
        for variant in variants {
            #expect(try variant.compile().identity != identity)
        }
        #expect(try variants[3].compile().identity != variants[4].compile().identity)
    }

    @Test("nested set values with separator-bearing strings have distinct identities")
    func separatorBearingSetValuesDoNotCollide() throws {
        let splitValues = TLASpec(
            name: "SeparatorCollision",
            variables: [
                NamedVar(name: "value", initial: .set([.string("a"), .string("b")]))
            ],
            actions: [],
            invariants: []
        )
        let embeddedSeparator = TLASpec(
            name: "SeparatorCollision",
            variables: [
                NamedVar(name: "value", initial: .set([.string("a\u{1E}string|b")]))
            ],
            actions: [],
            invariants: []
        )

        #expect(try splitValues.compile().identity != embeddedSeparator.compile().identity)
    }
}
