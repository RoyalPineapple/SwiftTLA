import Testing
@testable import SwiftTLA
import SwiftTLAMacros

private struct CompilerPipelineMember: Identifiable, Sendable {
    let id: Int
}

private enum CompilerPipelineNode: String, FiniteTLAValueDomain, CaseIterable {
    case first
    case second

    static var defaultValue: Self { .first }
    static let finiteValues: [Self] = [.first, .second]

    var tlaValue: TLAValue { .string(rawValue) }
}

@TLAModel
private struct CompilerPipelineGeneratedModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineGeneratedModel") {
            Algorithm("CompilerPipelineGeneratedModel", scoped: { scope in
                let counter = scope.sharedVar("counter", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(counter, to: counter + 1)
                }
            })
        }
    }
}

@TLAModel
private struct CompilerPipelineExplicitFormalNameModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineExplicitFormalName") {
            Algorithm("CompilerPipelineExplicitFormalName", scoped: { scope in
                let counter = scope.sharedVar("counter", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(counter, to: counter + 1)
                }
            })
        }
    }
}

@TLAModel
private struct CompilerPipelineAlgorithmModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineAlgorithmModel") {
            Algorithm("CompilerPipelineAlgorithmModel", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(count, to: count + 1)
                }
            })
        }
    }
}

@TLAModel
private struct CompilerPipelineInitializationModel {
    static var spec: TLASpec {
        #spec("CompilerPipelineInitializationModel") {
            Algorithm("CompilerPipelineInitializationModel", scoped: { scope in
                let seed = scope.sharedVar("seed", initial: 0)
                let computed = scope.sharedVar("computed", initial: seed + 1)
                let choice = scope.sharedVar("choice", in: SetExpr<Int>.literal(1, 2))
                Do(TestControlLabel.done) {
                    Assign(computed, to: computed)
                    Assign(choice, to: choice)
                }
            })
        }
    }
}

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
    @Test("equivalent source models retain stable binder names")
    func equivalentSourceModelsRetainStableBinderNames() throws {
        func sourceModel() -> TLASpec {
            TLASpec("StableBinders") {
                Invariant("allPositive") {
                    All(in: SetExpr<Int>.literal(1, 2)) { value in value >= 1 }
                }
            }
        }

        let first = try sourceModel().compile()
        _ = sourceModel()
        let second = try sourceModel().compile()
        let firstModule = try first.renderedTLAModuleBundle().root.tla
        let secondModule = try second.renderedTLAModuleBundle().root.tla

        #expect(first.identity == second.identity)
        #expect(firstModule == secondModule)
    }

    @Test("compiled binders have distinct rendered names")
    func compiledBindersHaveDistinctRenderedNames() throws {
        let spec = TLASpec("DistinctBinders") {
            Invariant("Safe") {
                .forAll(
                    .setLiteral([.value(.int(1))]),
                    "value",
                    .forAll(.setLiteral([.value(.int(1))]), "value", .value(.bool(true)))
                )
            }
        }

        let compilation = try spec.compile()
        let first = try #require(compilation.bindings.binderName(.init(ordinal: 0)))
        let second = try #require(compilation.bindings.binderName(.init(ordinal: 1)))
        let module = try compilation.renderedTLAModuleBundle().root.tla

        #expect(first != second)
        #expect(module.contains(first))
        #expect(module.contains(second))
    }

    @Test("macro compilation uses the explicit formal module name")
    func macroUsesExplicitFormalModuleName() throws {
        let compilation = try CompilerPipelineExplicitFormalNameModel.spec.compile()
        let repeated = try CompilerPipelineExplicitFormalNameModel.spec.compile()

        #expect(compilation.spec.name == "CompilerPipelineExplicitFormalName")
        #expect(compilation.identity == repeated.identity)
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
        let checker = ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 3))

        #expect(checker.compilation.identity == compilation.identity)
        let counterToken = try #require(TLAStateProjection.Token(validating: "counter"))
        let initial = try TLAStateProjection(validating: [.init(token: counterToken, value: .int(0))])
        let action = try #require(compilation.compiledActions.first).id
        let successor = try #require(
            try compilation.successors(for: action, arguments: [], from: initial).first
        )
        let graph = try checker.exploreGraph()
        #expect(successor.value(for: counterToken) == .int(1))
        #expect(compilation.propertyOutcomes(in: initial) == [.satisfied(name: "NonNegative")])
        #expect(graph.states.count == 3)
    }

    @Test("state limits retain exactly the declared number of states")
    func stateLimitIsAnExactRetainedStateBoundary() throws {
        func exploration(guarded: Bool) throws -> ModelExplorationResult {
            let counter = Var<Int>("counter", 0)
            let action = counter.becomes(counter + 1)
            let spec = TLASpec("StateLimitBoundary") {
                Variable(counter, 0)
                Action("increment") {
                    guarded ? ActionExpr.guard_(counter < 2) && action : action
                }
            }
            return try ModelChecker(
                compilation: spec.compile(),
                configuration: FiniteExplorationConfiguration(maximumStateLimit: 3)
            ).explore()
        }

        let complete = try exploration(guarded: true)
        #expect(complete.graph.states.count == 3)
        #expect(complete.isComplete)

        let bounded = try exploration(guarded: false)
        #expect(bounded.graph.states.count == 3)
        guard case .depthExceeded(statesCount: 3, limit: 3) = bounded.result else {
            Issue.record("Expected the fourth distinct state to stop exploration at the declared limit.")
            return
        }
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
                .init(name: "advance", body: .unchanged(.named("first"))),
                .init(name: "hold", body: .unchanged(.named("second")))
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

    @Test("compiled layout assigns scoped control-location identities")
    func compiledLayoutAssignsScopedControlLocationIDs() throws {
        let algorithm = Algorithm("ControlLayout", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(CompilerPipelineNode.all) { _ in
                Do(TestControlLabel.start) {
                    Assign(value, to: value + 1)
                }
            }
            Procedure("first") {
                Do(TestControlLabel.start) {
                    Return()
                }
            }
            Procedure("second") {
                Do(TestControlLabel.start) {
                    Return()
                }
            }
        })

        let source = try compiledSourceSpecification(algorithm)
        #expect(source.actions.map(\.controlOwner) == [
            .process(algorithm: "ControlLayout", ordinal: 0, typeName: "CompilerPipelineNode"),
            .procedure(algorithm: "ControlLayout", name: "first"),
            .procedure(algorithm: "ControlLayout", name: "second"),
            nil
        ])
        let compilation = try source.compile()
        let description = compilation.description

        #expect(description.procedures.map { "\($0.algorithm).\($0.name)" } == [
            "ControlLayout.first",
            "ControlLayout.second"
        ])
        #expect(description.controlLocations.map(\.sourceName) == ["start", "start", "start", "Done"])
        #expect(description.controlLocations.map(\.renderedName) == ["start", "procedure.first.start", "procedure.second.start", "Done"])
        #expect(description.controlLocations.map(\.owner) == [
            .process(algorithm: "ControlLayout", declarationOrder: 0, typeName: "CompilerPipelineNode"),
            .procedure(algorithm: "ControlLayout", name: "first"),
            .procedure(algorithm: "ControlLayout", name: "second"),
            .generated(algorithm: "ControlLayout", purpose: "Done")
        ])
        let changed = Algorithm("ControlLayout", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(CompilerPipelineNode.all) { _ in
                Do(TestControlLabel.changed) {
                    Assign(value, to: value + 1)
                }
            }
            Procedure("first") {
                Do(TestControlLabel.start) {
                    Return()
                }
            }
            Procedure("second") {
                Do(TestControlLabel.start) {
                    Return()
                }
            }
        })
        let changedCompilation = try compiledSourceSpecification(changed).compile()
        #expect(compilation.identity != changedCompilation.identity)
    }

    @Test("compiled algorithm control state uses control-location identities")
    func compiledAlgorithmUsesControlLocationIdentities() throws {
        let algorithm = Algorithm("ControlRuntime", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(CompilerPipelineNode.all) { _ in
                Do(TestControlLabel.start) {
                    Assign(value, to: value + 1)
                    Goto(TestControlLabel.finish)
                }
                Do(TestControlLabel.finish) {
                    Stop()
                }
            }
        })
        let compilation = try compiledSourceSpecification(algorithm).compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let pc = try #require(compilation.layout.variableID(named: "pc"))
        let initial = try #require(runtime.initialStates().first)

        guard case .function(let initialControls) = try initial.value(for: pc) else {
            Issue.record("Expected a process-family control function")
            return
        }
        #expect(initialControls.values.allSatisfy {
            if case .controlLocation = $0 { return true }
            return false
        })

        let successors = try runtime.successors(from: initial)
        let advanced = try #require(successors.first)
        guard case .function(let nextControls) = try advanced.state.value(for: pc) else {
            Issue.record("Expected a process-family control function")
            return
        }
        #expect(nextControls.values.allSatisfy {
            if case .controlLocation = $0 { return true }
            return false
        })
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
                        .assign(.named("counter"), .variable("current"))
                    )
                )
            ],
            invariants: []
        )

        let compilation = try spec.compile()

        guard case .existsAction(let binder, _, .assign(let variable, .boundValue(let value))) = compilation.semantics.actions[0].body else {
            Issue.record("Expected a compiled binder assignment")
            return
        }
        #expect(variable == .init(ordinal: 0))
        #expect(value == binder)
    }

    @Test("compiled temporal properties use bound variable identities")
    func compiledTemporalPropertiesUsePrivateIdentities() throws {
        let spec = TLASpec(
            name: "CompiledTemporal",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "stay", body: .unchanged(.named("counter")))],
            invariants: [],
            temporalProperties: [
                .init(name: "EventuallyZero", expr: .eventually(.equal(.variable("counter"), .value(.int(0)))))
            ]
        )

        let compilation = try spec.compile()

        guard case .eventually(.equal(.stateVariable(let variable), .value(.int(0)))) = compilation.semantics.temporalProperties[0].expression else {
            Issue.record("Expected a compiled temporal predicate")
            return
        }
        #expect(variable == .init(ordinal: 0))
    }

    @Test("compilation rejects an unbound temporal reference")
    func compilationRejectsUnboundTemporalReference() {
        let spec = TLASpec(
            name: "InvalidTemporal",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "stay", body: .unchanged(.named("counter")))],
            invariants: [],
            temporalProperties: [
                .init(name: "Missing", expr: .always(.variable("missing")))
            ]
        )

        #expect(throws: CompilationDiagnostic.self) {
            try spec.compile()
        }
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
                    body: .chooseAction(.named("candidate"), .setLiteral([.int(1), .int(2)]))
                        && .guard_(.equal(.variable("candidate"), .int(2)))
                        && .assign(.named("counter"), .variable("candidate"))
                )
            ],
            invariants: []
        )
        let compilation = try spec.compile()
        let state = try CompiledState(formalValues: [.int(0), .int(0)], compilation: compilation)
        let action = try #require(compilation.semantics.actions.first)
        let nextStates = try CompiledRuntime(compilation: compilation)
            .successors(for: action.id, from: state)
            .map(\.state)
        let counter = try nextStates[0].value(for: .init(ordinal: 0))
        let candidate = try nextStates[0].value(for: .init(ordinal: 1))

        #expect(nextStates.count == 1)
        #expect(counter == .integer(2))
        #expect(candidate == .integer(2))
    }

    @Test("compiled action bindings enumerate their declared values")
    func compiledActionBindingsUseBinderSlots() throws {
        let spec = TLASpec(
            name: "CompiledActionBinding",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [
                .init(
                    name: "advance",
                    body: .assign(.named("counter"), .variable("increment")),
                    bindings: [.init(name: "increment", values: [.int(1), .int(2)])]
                )
            ],
            invariants: []
        )
        let compilation = try spec.compile()
        let state = try CompiledState(formalValues: [.int(0)], compilation: compilation)
        let action = try #require(compilation.semantics.actions.first)
        let next = try CompiledRuntime(compilation: compilation)
            .successors(for: action.id, from: state)
            .map(\.state)

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
                        .named("counter"),
                        .operatorApplication(.reference("Double", arity: 1), [.value(.int(2))])
                    )
                )
            ],
            invariants: [],
            formalOperatorDefinitions: [double]
        )
        let compilation = try spec.compile()
        let state = try CompiledState(formalValues: [.int(0)], compilation: compilation)
        let action = try #require(compilation.semantics.actions.first)
        let next = try CompiledRuntime(compilation: compilation)
            .successors(for: action.id, from: state)
            .map(\.state)

        guard case .assign(_, .operatorApplication(.reference(let id, _), _)) = compilation.semantics.actions[0].body else {
            Issue.record("Expected an operator identity")
            return
        }
        let counter = try #require(next.first).value(for: .init(ordinal: 0))
        #expect(compilation.bindings.operatorName(id) == "Double")
        #expect(counter == .integer(4))
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
                        .named("counter"),
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
        let state = try CompiledState(formalValues: [.int(0)], compilation: compilation)
        let action = try #require(compilation.semantics.actions.first)
        let next = try CompiledRuntime(compilation: compilation)
            .successors(for: action.id, from: state)
            .map(\.state)
        let counter = try #require(next.first).value(for: .init(ordinal: 0))

        #expect(counter == .integer(6))
    }

    @Test("compiled runtime enumerates slot-backed initial and successor states")
    func compiledRuntimeUsesSlotsForExecution() throws {
        let spec = TLASpec(
            name: "CompiledRuntime",
            variables: [
                .init(name: "counter", initial: .int(0)),
                .init(
                    name: "choice",
                    initial: .int(0),
                    initialSet: .setLiteral([.value(.int(1)), .value(.int(2))])
                )
            ],
            actions: [
                .init(
                    name: "advance",
                    body: .guard_(.lessThan(.variable("counter"), .variable("choice")))
                        && .assign(.named("counter"), .add(.variable("counter"), .int(1)))
                )
            ],
            invariants: [.init(name: "Bounded", body: .lessOrEqual(.variable("counter"), .variable("choice")))]
        )
        let compilation = try spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try runtime.initialStates()

        #expect(initial.count == 2)
        let firstSuccessor = try runtime.successors(from: try #require(initial.first))
        let invariantHolds = try runtime.invariantHolds(compilation.semantics.invariants[0], in: firstSuccessor[0].state)
        #expect(firstSuccessor.count == 1)
        #expect(invariantHolds)

        let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).explore()
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
            actions: [.init(name: "step", body: .guard_(call) && .unchanged(.named("counter")))],
            invariants: []
        )

        let compilation = try spec.compile()

        guard case .and(.guard_(.operatorApplication(.lambda(let lambda), _)), .unchanged) = compilation.semantics.actions[0].body else {
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
            actions: [.init(name: "step", body: .guard_(.in(.int(1), .integerRange(.variable("counter"), .int(2)))))],
            invariants: []
        )

        let compilation = try spec.compile()

        guard case .guard_(.in(_, .integerRange(.stateVariable(let value), _))) = compilation.semantics.actions[0].body else {
            Issue.record("Expected a compiled integer range")
            return
        }
        #expect(value == compilation.layout.variables[0].id)
    }

    @Test("formal state stores values by compiled variable identity")
    func formalStateUsesVariableSlots() throws {
        let spec = TLASpec(
            name: "CompiledState",
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
        let state = try CompiledState(formalValues: [.int(1), .int(2)], compilation: compilation)
        let updated = try state.updating(second, to: .integer(3))
        let stateFirst = try state.value(for: first)
        let stateSecond = try state.value(for: second)
        let updatedFirst = try updated.value(for: first)
        let updatedSecond = try updated.value(for: second)

        #expect(stateFirst == .integer(1))
        #expect(stateSecond == .integer(2))
        #expect(updatedFirst == .integer(1))
        #expect(updatedSecond == .integer(3))
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

        let foreignState = try CompiledState(formalValues: [.int(0)], compilation: first)
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
        let state = try CompiledState(formalValues: [.int(1)], compilation: compilation)

        guard case .existsAction(let binder, _, .guard_(let expression)) = compilation.semantics.actions[0].body else {
            Issue.record("Expected a compiled action binder")
            return
        }
        let result = try CompiledEvaluator(
            state: state,
            semantics: compilation.semantics,
            layout: compilation.layout,
            bindings: .init().binding(.integer(1), to: binder)
        ).evaluate(expression)

        #expect(result == .boolean(true))
    }

    @Test("compiled record expressions have canonical field order")
    func compiledRecordExpressionsHaveCanonicalFieldOrder() throws {
        let record = StateRecordExpression([
            .init(name: "z", value: .int(1)),
            .init(name: "a", value: .int(2))
        ])
        let compilation = try TLASpec(
            name: "RecordFields",
            variables: [],
            actions: [.init(name: "step", body: .guard_(.equal(.recordLiteral(record), .recordLiteral(record))))],
            invariants: []
        ).compile()

        #expect(compilation.layout.fields.map(\.renderedName) == ["a", "z"])
    }

    @Test("compiled record fields retain their bound identity beside like-named variables")
    func compiledRecordFieldsUseBoundIdentity() throws {
        let compilation = try TLASpec(
            name: "RecordFieldBinding",
            variables: [.init(name: "value", initial: .int(1))],
            actions: [
                .init(
                    name: "step",
                    body: .guard_(.equal(
                        .recordLiteral(.init([.init(name: "value", value: .variable("value"))])),
                        .recordLiteral(.init([.init(name: "value", value: .int(1))]))
                    ))
                )
            ],
            invariants: []
        ).compile()

        guard case .guard_(.equal(.recordLiteral(let record), _)) = compilation.semantics.actions[0].body,
              case .stateVariable(let variable) = record.fields[0].value else {
            Issue.record("Expected a compiled record with a bound variable value")
            return
        }

        #expect(record.fields[0].id == compilation.layout.fields[0].id)
        #expect(variable == compilation.layout.variables[0].id)
    }

    @Test("source record expressions have canonical field order")
    func sourceRecordExpressionsHaveCanonicalFieldOrder() {
        let record = StateRecordExpression([
            .init(name: "z", value: .int(1)),
            .init(name: "a", value: .int(2))
        ])

        #expect(record.fields.map(\.name) == ["a", "z"])
    }

    @Test("duplicate source record fields fail compilation")
    func duplicateSourceRecordFieldsFailCompilation() {
        let record = StateRecordExpression([
            .init(name: "value", value: .int(1)),
            .init(name: "value", value: .int(2))
        ])
        let spec = TLASpec(
            name: "DuplicateRecordField",
            variables: [],
            actions: [.init(name: "step", body: .guard_(.equal(.recordLiteral(record), .recordLiteral(record))))],
            invariants: []
        )

        do {
            _ = try spec.compile()
            Issue.record("Expected a duplicate record field diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .duplicateRecordField)
        } catch {
            Issue.record("Expected a duplicate record field diagnostic, received \(error)")
        }
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
        let state = try CompiledState(formalValues: [], compilation: compilation)

        guard case .guard_(let compiled) = compilation.semantics.actions[0].body else {
            Issue.record("Expected a compiled guard")
            return
        }
        let result = try CompiledEvaluator(
            state: state,
            semantics: compilation.semantics,
            layout: compilation.layout
        ).evaluate(compiled)
        #expect(result == .boolean(true))
    }

    @Test("compiled actions update formal state by variable identity")
    func compiledActionsUpdateFormalState() throws {
        let spec = TLASpec(
            name: "CompiledActionExecution",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "step", body: .assign(.named("counter"), .add(.variable("counter"), .int(1))))],
            invariants: []
        )
        let compilation = try spec.compile()
        let state = try CompiledState(formalValues: [.int(1)], compilation: compilation)

        let action = compilation.semantics.actions[0]
        let successors = try CompiledRuntime(compilation: compilation)
            .successors(for: action.id, from: state)
            .map(\.state)
        let counter = try successors[0].value(for: compilation.layout.variables[0].id)

        #expect(successors.count == 1)
        #expect(counter == .integer(2))
    }

    @Test("compiled record access uses a field identity")
    func compiledRecordAccessUsesFieldIdentity() throws {
        let recordInitial: TLARecord = ["count": .int(1)]
        let state = Var<TLARecord>("state", recordInitial)
        let spec = TLASpec("CompiledRecordAccess") {
            Variable(state)
            Action("step") {
                ActionExpr.guard_(.equal(.recordAccess(.variable("state"), "count"), .int(1)))
            }
        }
        let compilation = try spec.compile()

        guard case .guard_(.equal(.recordAccess(_, let field, _), _)) = compilation.semantics.actions[0].body else {
            Issue.record("Expected a compiled record access")
            return
        }
        #expect(field.ordinal == 0)
        let action = try #require(compilation.compiledActions.first).id
        let initial = try #require(try compilation.initialStateProjections().first)
        let successors = try compilation.successors(for: action, arguments: [], from: initial)
        #expect(successors.count == 1)
    }

    @Test("compiled record function access retains its formal key")
    func compiledRecordFunctionAccessRetainsFormalKey() throws {
        let recordInitial: TLARecord = ["count": .int(1)]
        let state = Var<TLARecord>("state", recordInitial)
        let key = Var<String>("key", "count")
        let spec = TLASpec("CompiledRecordFunctionAccess") {
            Variable(state)
            Variable(key)
            Action("step") {
                ActionExpr.and(
                    .guard_(.equal(.functionApply(.variable("state"), .variable("key")), .int(1))),
                    .assign(.named("state"), .except(.variable("state"), .variable("key"), .int(2)))
                )
            }
        }
        let compilation = try spec.compile()
        let action = try #require(compilation.compiledActions.first).id
        let initial = try #require(try compilation.initialStateProjections().first)
        let projection = try #require(
            try compilation.successors(for: action, arguments: [], from: initial).first
        )
        let stateToken = try #require(TLAStateProjection.Token(validating: "state"))
        let stateValue = try #require(projection.value(for: stateToken))

        #expect(stateValue == TLAValue.record(["count": .int(2)]))
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

        let firstIdentity = try first.compile().identity
        let secondIdentity = try second.compile().identity
        #expect(firstIdentity != secondIdentity)
    }

    @Test("generated host types change the machine surface without changing formal identity")
    func generatedHostTypesStayOutsideFormalIdentity() throws {
        func specification(
            variableType: String = "Count",
            bindingType: String = "Worker",
            collectionAction: String? = nil
        ) -> TLASpec {
            let collection = SymmetricCollectionDecl(
                name: "devices",
                verificationScope: 1,
                initial: .int(0),
                generatedElementType: "Device",
                generatedValueType: "Int"
            )
            return TLASpec(
                name: "GeneratedSchemaIdentity",
                variables: [
                    .init(
                        name: "count",
                        initial: .int(0),
                        generatedSwiftType: variableType,
                        origin: .source
                    ),
                    collection.variable
                ],
                actions: [
                    .init(
                        name: "advance",
                        body: .guard_(.value(.bool(true))),
                        bindings: [.init(
                            name: "worker",
                            values: [.int(0)],
                            generatedSwiftType: bindingType
                        )],
                        controlOwner: nil,
                        generatedSymmetricCollectionName: collectionAction
                    )
                ],
                invariants: [],
                symmetricCollections: [collection]
            )
        }

        let baseline = try specification().compile()
        let variableType = try specification(variableType: "Counter").compile()
        let bindingType = try specification(bindingType: "Process").compile()
        let collectionAction = try specification(collectionAction: "devices").compile()

        #expect(variableType.identity == baseline.identity)
        #expect(bindingType.identity == baseline.identity)
        #expect(variableType.machineSurfacePlan != baseline.machineSurfacePlan)
        #expect(bindingType.machineSurfacePlan != baseline.machineSurfacePlan)
        #expect(collectionAction.identity != baseline.identity)
    }

    @Test("compiled descriptions preserve declaration order without exposing runtime slots")
    func compiledDescriptionPreservesDeclaredOrder() throws {
        let compilation = try TLASpec(
            name: "Description",
            variables: [
                .init(name: "count", initial: .int(0)),
                .init(name: "limit", initial: .int(10))
            ],
            actions: [.init(name: "advance", body: .unchanged(.named("count")))],
            invariants: []
        ).compile()

        #expect(compilation.description.identity == compilation.identity)
        #expect(compilation.description.variables.map(\.name) == ["count", "limit"])
        #expect(compilation.description.actions.map(\.name) == ["advance"])
        #expect(compilation.description.imports.map(\.name) == ["Description"])
    }

    @Test("#spec Algorithm lowering reaches macro-generated consumers through one identity")
    func algorithmSpecificationUsesMacroCompiledPayload() throws {
        let compilation = try CompilerPipelineAlgorithmModel.spec.compile()
        let repeated = try CompilerPipelineAlgorithmModel.spec.compile()
        let rendered = try compilation.renderedTLAModuleBundle().tla
        let repeatedRendered = try repeated.renderedTLAModuleBundle().tla

        #expect(repeated.identity == compilation.identity)
        #expect(rendered == repeatedRendered)
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
            actions: [.init(name: "step", body: .guard_(quantified) && .unchanged(.named("counter")))],
            invariants: []
        )

        let compilation = try spec.compile()

        #expect(compilation.layout.variableID(named: "counter") == .init(ordinal: 0))
        #expect(compilation.bindings.references.values.contains(.variable(.init(ordinal: 0))))
        #expect(compilation.bindings.references.values.contains(.binder(.init(ordinal: 0))))
        #expect(compilation.bindings.references.values.contains(.binder(.init(ordinal: 1))))
    }

    @Test("free references fail at the binding gate")
    func freeReferenceBlocksCompilation() {
        let spec = TLASpec(
            name: "FreeReference",
            variables: [.init(name: "counter", initial: .int(0))],
            actions: [.init(name: "step", body: .assign(.named("counter"), .variable("missing")))],
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
                    body: .existsAction("current", .setLiteral([.int(1)]), .assign(.named("current"), .int(1)))
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
                        && .unchanged(.named("counter"))
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
            actions: [.init(name: "step", body: .guard_(recursive) && .unchanged(.named("counter")))],
            invariants: []
        )

        _ = try spec.compile()
    }

    @Test("macro-generated consumers and rendering retain the compiled identity")
    func macroGeneratedConsumersUseCompiledPayload() throws {
        let compilation = try CompilerPipelineGeneratedModel.spec.compile()
        let repeated = try CompilerPipelineGeneratedModel.spec.compile()
        let rendered = try compilation.renderedTLAModuleBundle().tla
        let repeatedRendered = try repeated.renderedTLAModuleBundle().tla

        #expect(repeated.identity == compilation.identity)
        #expect(rendered == repeatedRendered)
    }

    @Test("#spec lowering preserves every canonical variable initialization field")
    func specMacroRetainsInitializationForms() throws {
        let compilation = try CompilerPipelineInitializationModel.spec.compile()
        let computed = try #require(compilation.spec.variables.first { $0.name == "computed" })
        let choice = try #require(compilation.spec.variables.first { $0.name == "choice" })
        let repeated = try CompilerPipelineInitializationModel.spec.compile()

        #expect(computed.initExpr == .add(.variable("seed"), .int(1)))
        #expect(computed.lazySet == nil)
        #expect(choice.initialSet == .setLiteral([.value(.int(1)), .value(.int(2))]))
        #expect(choice.lazySet == nil)
        #expect(repeated.identity == compilation.identity)
    }

    @Test("#spec lowering preserves symmetric collection metadata")
    func specMacroRetainsSymmetricCollectionMetadata() throws {
        let compilation = try CompilerPipelineCollectionModel.spec.compile()
        let devices = try #require(compilation.spec.variables.first { $0.name == "devices" })
        let declaration = try #require(compilation.spec.symmetricCollections.first { $0.name == "devices" })
        let repeated = try CompilerPipelineCollectionModel.spec.compile()

        #expect(devices.collectionType == .dictionary(2))
        #expect(declaration.variable == devices)
        #expect(declaration.verificationScope == 2)
        #expect(repeated.identity == compilation.identity)
    }

    @Test("semantic compilation fields change the identity")
    func semanticFieldsContributeToIdentity() throws {
        let base = TLASpec(
            name: "Fingerprint",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [NamedAction(name: "step", body: .assign(.named("value"), .int(1)))],
            invariants: []
        )
        let variants = [
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], checkDeadlock: true),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], theorems: [Theorem(name: "Safety", always: .value(.bool(true)))]),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], recursiveFuncs: [.init(name: "CountDown", params: ["n"], body: .variable("n"))]),
            {
                let collection = SymmetricCollectionDecl(
                    name: "members",
                    verificationScope: 1,
                    initial: .int(0),
                    generatedElementType: "Member",
                    generatedValueType: "Int"
                )
                return TLASpec(
                    name: "Fingerprint",
                    variables: base.variables + [collection.variable],
                    actions: base.actions,
                    invariants: [],
                    symmetricCollections: [collection]
                )
            }(),
            TLASpec(name: "Fingerprint", variables: base.variables, actions: base.actions, invariants: [], extendsModules: [.naturals])
        ]

        let identity = try base.compile().identity
        for variant in variants {
            let variantIdentity = try variant.compile().identity
            #expect(variantIdentity != identity)
        }
    }

    @Test("compiled layout owns direct action rendered names")
    func compiledLayoutOwnsDirectActionRenderedNames() throws {
        let compilation = try TLASpec(
            name: "DirectActionNames",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [
                .init(name: "procedure.work.enter", body: .assign(.named("value"), .int(1))),
                .init(name: "procedure_work_enter", body: .assign(.named("value"), .int(2)))
            ],
            invariants: []
        ).compile()

        #expect(compilation.description.actions.map(\.renderedName) == [
            "procedure_work_enter",
            "procedure_work_enter__2"
        ])
        let source = try compilation.renderedTLAModuleBundle().tla
        #expect(source.contains("procedure_work_enter =="))
        #expect(source.contains("procedure_work_enter__2 =="))
    }

    @Test("identity includes action domains, all initialisation forms, and imported semantics")
    func structuralFieldsContributeToIdentity() throws {
        let base = TLASpec(
            name: "StructuralFingerprint",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [NamedAction(name: "step", body: .assign(.named("value"), .int(1)), bindings: [
                .init(name: "choice", values: [.int(0), .int(1)])
            ])],
            invariants: []
        )
        let importedA = TLASpec(
            name: "Imported",
            variables: [NamedVar(name: "inner", initial: .int(0))],
            actions: [NamedAction(name: "stay", body: .unchanged(.named("inner")))],
            invariants: []
        )
        let importedB = TLASpec(
            name: "Imported",
            variables: [NamedVar(name: "inner", initial: .int(1))],
            actions: [NamedAction(name: "stay", body: .unchanged(.named("inner")))],
            invariants: []
        )
        let variants = [
            TLASpec(name: "StructuralFingerprint", variables: base.variables, actions: [
                .init(name: "step", body: .assign(.named("value"), .int(1)), bindings: [.init(name: "choice", values: [.int(0), .int(2)])])
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
            let variantIdentity = try variant.compile().identity
            #expect(variantIdentity != identity)
        }
        let importedAIdentity = try variants[3].compile().identity
        let importedBIdentity = try variants[4].compile().identity
        #expect(importedAIdentity != importedBIdentity)
    }

    @Test("nested set values with separator-bearing strings have distinct identities")
    func separatorBearingSetValuesDoNotCollide() throws {
        let split = Var<SetExpr<String>>("value", SetExpr("a", "b"))
        let embedded = Var<SetExpr<String>>("value", SetExpr("a\u{1E}string|b"))
        let splitValues = TLASpec("SeparatorCollision") { Variable(split) }
        let embeddedSeparator = TLASpec("SeparatorCollision") { Variable(embedded) }

        let splitIdentity = try splitValues.compile().identity
        let embeddedIdentity = try embeddedSeparator.compile().identity
        #expect(splitIdentity != embeddedIdentity)
    }

    @Test("invalid action parameter declarations fail during compilation")
    func invalidActionParameterDeclarationsFailDuringCompilation() {
        let specification = TLASpec(
            name: "InvalidActionParameters",
            variables: [NamedVar(name: "value", initial: .int(0))],
            actions: [
                .init(
                    name: "advance",
                    body: .assign(.named("value"), .int(1)),
                    bindings: [.init(name: "", values: [.int(1)])]
                )
            ],
            invariants: []
        )

        do {
            _ = try specification.compile()
            Issue.record("Expected invalid action parameters to fail compilation")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidActionBinding)
            #expect(diagnostic.stage == .lowering)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }

    @Test("invalid formal declarations fail during compilation")
    func invalidFormalDeclarationsFailDuringCompilation() {
        let specification = TLASpec(
            name: "InvalidFormalDeclaration",
            variables: [],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                .init(name: "", parameters: [], body: .value(.bool(true)))
            ]
        )

        do {
            _ = try specification.compile()
            Issue.record("Expected invalid formal declaration to fail compilation")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidFormalDeclaration)
            #expect(diagnostic.stage == .binding)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }
}
