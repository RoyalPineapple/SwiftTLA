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

private enum FirstGeneratedSurfaceValue: String, FiniteTLAValueDomain {
    case value

    static let defaultValue = Self.value
    static let finiteValues = [Self.value]
}

private enum SecondGeneratedSurfaceValue: String, FiniteTLAValueDomain {
    case value

    static let defaultValue = Self.value
    static let finiteValues = [Self.value]
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
                let computed: SharedVariable<Int> = scope.sharedVar("computed", initial: seed + 1)
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
    @Test("generated Swift value types contribute to compilation identity")
    func generatedSwiftValueTypesContributeToCompilationIdentity() throws {
        let first = try TLASpec("GeneratedSurfaceIdentity") {
            Var("value", FirstGeneratedSurfaceValue.value)
        }.compile()
        let second = try TLASpec("GeneratedSurfaceIdentity") {
            Var("value", SecondGeneratedSurfaceValue.value)
        }.compile()

        #expect(first.renderedTLAModuleBundle().tla == second.renderedTLAModuleBundle().tla)
        #expect(first.machineSurfacePlan.variables.map(\.swiftType) == ["FirstGeneratedSurfaceValue"])
        #expect((first.identity == second.identity) == false)

        let firstAction = try TLASpec("GeneratedActionSurfaceIdentity") {
            Var("value", 0)
            Action(
                "Choose",
                parameters: [ActionParameter("choice", values: FirstGeneratedSurfaceValue.finiteValues)]
            ) { StateExpr.value(.bool(true)) }
        }.compile()
        let secondAction = try TLASpec("GeneratedActionSurfaceIdentity") {
            Var("value", 0)
            Action(
                "Choose",
                parameters: [ActionParameter("choice", values: SecondGeneratedSurfaceValue.finiteValues)]
            ) { StateExpr.value(.bool(true)) }
        }.compile()

        #expect(firstAction.renderedTLAModuleBundle().tla == secondAction.renderedTLAModuleBundle().tla)
        #expect((firstAction.identity == secondAction.identity) == false)
    }

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
        let firstModule = first.renderedTLAModuleBundle().root.tla
        let secondModule = second.renderedTLAModuleBundle().root.tla

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
        let invariant = try #require(compilation.semantics.invariants.first)
        guard case .forAll(_, let first, .forAll(_, let second, _)) = invariant.body else {
            Issue.record("Expected nested compiled quantifiers")
            return
        }
        let module = compilation.renderedTLAModuleBundle().root.tla

        #expect(first != second)
        #expect(module.contains("\\A b0 \\in"))
        #expect(module.contains("\\A b1 \\in"))
    }

    @Test("compiled binder names do not shadow declarations")
    func compiledBinderNamesDoNotShadowDeclarations() throws {
        let spec = TLASpec("BinderCollision") {
            Var("b0", 1)
            Invariant("Safe") {
                .forAll(
                    .setLiteral([.value(.int(1))]),
                    "value",
                    .equal(.variable("value"), .variable("b0"))
                )
            }
        }

        let module = try spec.compile().renderedTLAModuleBundle().root.tla

        #expect(module.contains("VARIABLES b0"))
        #expect(module.contains("\\A _b0 \\in"))
        #expect(module.contains("(_b0 = b0)"))
    }

    @Test("compiled binder names do not shadow theorem names")
    func compiledBinderNamesDoNotShadowTheoremNames() throws {
        let spec = TLASpec("BinderTheoremCollision") {
            Theorem(name: "b0", always: .value(.bool(true)))
            Invariant("Safe") {
                .forAll(
                    .setLiteral([.value(.int(1))]),
                    "value",
                    .equal(.variable("value"), .int(1))
                )
            }
        }

        let module = try spec.compile().renderedTLAModuleBundle().root.tla

        #expect(spec.theorems.map(\.name) == ["b0"])
        #expect(module.contains("\\A _b0 \\in"))
    }

    @Test("macro compilation uses the explicit formal module name")
    func macroUsesExplicitFormalModuleName() throws {
        let compilation = try CompilerPipelineExplicitFormalNameModel.spec.compile()
        let repeated = try CompilerPipelineExplicitFormalNameModel.spec.compile()

        #expect(compilation.description.name == "CompilerPipelineExplicitFormalName")
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
        let checker = ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 3, symmetryReduction: .disabled))

        #expect(checker.compilation.identity == compilation.identity)
        let initial = try firstCompiledState(in: compilation)
        let successor = try #require(
            try compiledSuccessors(named: "increment", arguments: [], in: compilation, from: initial).first
        )
        let graph = try checker.exploreGraph()
        #expect(try renderedValue(named: "counter", in: successor, compilation: compilation) == .int(1))
        let invariant = try #require(compilation.semantics.invariants.first)
        #expect(invariant.name == "NonNegative")
        #expect(try CompiledRuntime(compilation: compilation).invariantHolds(invariant, in: initial))
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
                configuration: FiniteExplorationConfiguration(maximumStateLimit: 3, symmetryReduction: .disabled)
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

        let source = try loweredSourceSpecification(algorithm)
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
        let changedCompilation = try loweredSourceSpecification(changed).compile()
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
        let compilation = try loweredSourceSpecification(algorithm).compile()
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
        #expect(compilation.semantics.formalOperatorDefinitions.contains { $0.id == id })
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
                    initialization: .memberOf(.setLiteral([.value(.int(1)), .value(.int(2))])),
                    generatedSwiftType: "Int",
                    origin: .source
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

        let exploration = try ModelChecker(compilation: compilation, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)).explore()
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

        guard case .and(
            .guard_(.in(_, .integerRange(.stateVariable(let value), _))),
            .unchanged
        ) = compilation.semantics.actions[0].body else {
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

        guard case .existsAction(
            let binder,
            _,
            .and(.guard_(let expression), .unchanged)
        ) = compilation.semantics.actions[0].body else {
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

        guard case .and(
            .guard_(.equal(.recordLiteral(let record), _)),
            .unchanged
        ) = compilation.semantics.actions[0].body,
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

        guard case .and(
            .guard_(.equal(.recordAccess(_, let field, _), _)),
            .unchanged
        ) = compilation.semantics.actions[0].body else {
            Issue.record("Expected a compiled record access")
            return
        }
        #expect(field.ordinal == 0)
        let initial = try firstCompiledState(in: compilation)
        let successors = try compiledSuccessors(named: "step", arguments: [], in: compilation, from: initial)
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
        let initial = try firstCompiledState(in: compilation)
        let successor = try #require(
            try compiledSuccessors(named: "step", arguments: [], in: compilation, from: initial).first
        )
        let stateValue = try renderedValue(named: "state", in: successor, compilation: compilation)

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
        #expect(compilation.description.imports.isEmpty)
    }

    @Test("#spec Algorithm lowering reaches macro-generated consumers through one identity")
    func algorithmSpecificationUsesMacroCompiledPayload() throws {
        let compilation = try CompilerPipelineAlgorithmModel.spec.compile()
        let repeated = try CompilerPipelineAlgorithmModel.spec.compile()
        let rendered = compilation.renderedTLAModuleBundle().tla
        let repeatedRendered = repeated.renderedTLAModuleBundle().tla

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
        let action = try #require(compilation.semantics.actions.first)
        guard case .and(
            .guard_(.forAll(_, let outer, .exists(_, let inner, .equal(.boundValue(let reference), _)))),
            .unchanged(let variable)
        ) = action.body else {
            Issue.record("Expected compiled quantified action")
            return
        }
        #expect(outer != inner)
        #expect(reference == inner)
        #expect(variable == .init(ordinal: 0))
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
        let rendered = compilation.renderedTLAModuleBundle().tla
        let repeatedRendered = repeated.renderedTLAModuleBundle().tla

        #expect(repeated.identity == compilation.identity)
        #expect(rendered == repeatedRendered)
    }

    @Test("#spec lowering preserves each typed variable initialization form")
    func specMacroRetainsInitializationForms() throws {
        let source = try CompilerPipelineInitializationModel.spec.loweredSourceModel()
        let compilation = try source.compile()
        let seed = try #require(source.variables.first { $0.name == "seed" })
        let computed = try #require(source.variables.first { $0.name == "computed" })
        let choice = try #require(source.variables.first { $0.name == "choice" })
        let repeated = try CompilerPipelineInitializationModel.spec.compile()

        #expect(seed.initialization == .value(.int(0)))
        #expect(computed.initialization == .expression(.add(.variable("seed"), .int(1))))
        #expect(choice.initialization == .memberOf(.setLiteral([.value(.int(1)), .value(.int(2))])))
        #expect(repeated.identity == compilation.identity)
    }

    @Test("variable initialization follows dependencies instead of declaration order")
    func variableInitializationFollowsDependencies() throws {
        let compilation = try TLASpec(
            name: "InitializerDependencyOrder",
            variables: [
                .init(
                    name: "derived",
                    initialization: .expression(.add(.variable("choice"), .int(1))),
                    generatedSwiftType: "Int",
                    origin: .source
                ),
                .init(
                    name: "choice",
                    initialization: .memberOf(.integerRange(.int(1), .variable("limit"))),
                    generatedSwiftType: "Int",
                    origin: .source
                ),
                .init(name: "limit", initial: .int(3))
            ],
            actions: [],
            invariants: []
        ).compile()
        let states = try CompiledRuntime(compilation: compilation).initialStates()

        #expect(Set(try states.map {
            try renderedValue(named: "derived", in: $0, compilation: compilation)
        }) == [.int(2), .int(3), .int(4)])
    }

    @Test("variable initialization follows dependencies through formal definitions")
    func variableInitializationFollowsFormalDefinitionDependencies() throws {
        let compilation = try TLASpec(
            name: "FormalInitializerDependency",
            variables: [
                .init(
                    name: "derived",
                    initialization: .expression(
                        .operatorApplication(.reference("Derived", arity: 0), [])
                    ),
                    generatedSwiftType: "Int",
                    origin: .source
                ),
                .init(name: "seed", initial: .int(4))
            ],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                .init(
                    name: "Derived",
                    parameters: [],
                    body: .add(.variable("seed"), .int(1))
                )
            ]
        ).compile()
        let state = try firstCompiledState(in: compilation)

        #expect(try renderedValue(named: "derived", in: state, compilation: compilation) == .int(5))
    }

    @Test("a zero-arity formal definition is a variable initializer value")
    func zeroArityFormalDefinitionInitializesVariable() throws {
        let compilation = try TLASpec(
            name: "ZeroArityInitializer",
            variables: [
                .init(
                    name: "value",
                    initialization: .expression(.variable("InitialValue")),
                    generatedSwiftType: "Int",
                    origin: .source
                )
            ],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                .init(name: "InitialValue", parameters: [], body: .int(3))
            ]
        ).compile()
        let state = try firstCompiledState(in: compilation)

        #expect(try renderedValue(named: "value", in: state, compilation: compilation) == .int(3))
    }

    @Test("a formal definition with parameters is not a value")
    func parameterizedFormalDefinitionCannotInitializeVariableWithoutArguments() {
        let spec = TLASpec(
            name: "ParameterizedInitializer",
            variables: [
                .init(
                    name: "value",
                    initialization: .expression(.variable("InitialValue")),
                    generatedSwiftType: "Int",
                    origin: .source
                )
            ],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                .init(name: "InitialValue", parameters: [.value("argument")], body: .variable("argument"))
            ]
        )

        do {
            _ = try spec.compile()
            Issue.record("Expected a formal operator application diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidFormalOperatorApplication)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }

    @Test("mutually dependent variable initializers fail compilation")
    func mutuallyDependentVariableInitializersFailCompilation() {
        let spec = TLASpec(
            name: "CyclicInitializers",
            variables: [
                .init(
                    name: "downstream",
                    initialization: .expression(.variable("first")),
                    generatedSwiftType: "Int",
                    origin: .source
                ),
                .init(
                    name: "first",
                    initialization: .expression(.variable("second")),
                    generatedSwiftType: "Int",
                    origin: .source
                ),
                .init(
                    name: "second",
                    initialization: .expression(.variable("first")),
                    generatedSwiftType: "Int",
                    origin: .source
                )
            ],
            actions: [],
            invariants: []
        )

        do {
            _ = try spec.compile()
            Issue.record("Expected a cyclic variable-initialization diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .cyclicVariableInitialization)
            #expect(diagnostic.actual == "dependency cycle first -> second -> first")
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }

    @Test("unused local operators do not create variable-initialization cycles")
    func unusedLocalOperatorsDoNotCreateInitializationCycles() throws {
        let compilation = try TLASpec(
            name: "UnusedLocalInitializerOperator",
            variables: [
                .init(
                    name: "owner",
                    initialization: .expression(.letIn([
                        .init("unused", body: .variable("owner"))
                    ], .int(1))),
                    generatedSwiftType: "Int",
                    origin: .source
                )
            ],
            actions: [],
            invariants: []
        ).compile()
        let state = try firstCompiledState(in: compilation)

        #expect(try renderedValue(named: "owner", in: state, compilation: compilation) == .int(1))
    }

    @Test("action enabledness hidden in a formal definition cannot initialize a variable")
    func formalDefinitionCannotHideEnablednessInVariableInitialization() {
        let spec = TLASpec(
            name: "EnabledInitializer",
            variables: [
                .init(
                    name: "ready",
                    initialization: .expression(
                        .operatorApplication(.reference("IsReady", arity: 0), [])
                    ),
                    generatedSwiftType: "Bool",
                    origin: .source
                )
            ],
            actions: [.init(name: "stay", body: .unchanged(.named("ready")))],
            invariants: [],
            formalOperatorDefinitions: [
                .init(name: "IsReady", parameters: [], body: .enabledAction("stay"))
            ]
        )

        do {
            _ = try spec.compile()
            Issue.record("Expected an invalid variable-initialization diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidVariableInitialization)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }

    @Test("unused operator arguments do not create variable-initialization dependencies")
    func unusedOperatorArgumentsDoNotCreateInitializationDependencies() throws {
        let compilation = try TLASpec(
            name: "UnusedInitializerOperatorArgument",
            variables: [
                .init(
                    name: "owner",
                    initialization: .expression(.operatorApplication(
                        .reference("Ignore", arity: 2),
                        [
                            .operator(.lambda(.init(
                                parameters: ["ignored"],
                                body: .variable("owner")
                            ))),
                            .value(.int(1))
                        ]
                    )),
                    generatedSwiftType: "Int",
                    origin: .source
                )
            ],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                .init(
                    name: "Ignore",
                    parameters: [.operator("operation", arity: 1), .value("value")],
                    body: .variable("value")
                )
            ]
        ).compile()
        let state = try firstCompiledState(in: compilation)

        #expect(try renderedValue(named: "owner", in: state, compilation: compilation) == .int(1))
    }

    @Test("formal values remain substitutional during variable initialization")
    func formalValuesRemainSubstitutionalDuringInitialization() throws {
        let compilation = try TLASpec(
            name: "UnusedInitializerValue",
            variables: [
                .init(
                    name: "operatorValue",
                    initialization: .expression(.operatorApplication(
                        .reference("Ignore", arity: 1),
                        [.value(.variable("operatorValue"))]
                    )),
                    generatedSwiftType: "Int",
                    origin: .source
                ),
                .init(
                    name: "letValue",
                    initialization: .expression(.letValue(
                        "ignored",
                        .variable("letValue"),
                        .int(2)
                    )),
                    generatedSwiftType: "Int",
                    origin: .source
                ),
                .init(
                    name: "nestedValue",
                    initialization: .expression(.letValue(
                        "outer",
                        .int(3),
                        .operatorApplication(
                            .reference("Identity", arity: 1),
                            [.value(.variable("outer"))]
                        )
                    )),
                    generatedSwiftType: "Int",
                    origin: .source
                )
            ],
            actions: [],
            invariants: [],
            formalOperatorDefinitions: [
                .init(name: "Ignore", parameters: [.value("ignored")], body: .int(1)),
                .init(name: "Identity", parameters: [.value("value")], body: .variable("value"))
            ]
        ).compile()
        let state = try firstCompiledState(in: compilation)

        #expect(try renderedValue(named: "operatorValue", in: state, compilation: compilation) == .int(1))
        #expect(try renderedValue(named: "letValue", in: state, compilation: compilation) == .int(2))
        #expect(try renderedValue(named: "nestedValue", in: state, compilation: compilation) == .int(3))
    }

    @Test("symmetric collection actions lower to the declared finite member binding")
    func symmetricCollectionActionsUseDeclaredMemberBindings() throws {
        let source = try CompilerPipelineCollectionModel.spec.loweredSourceModel()
        let compilation = try source.compile()
        let devices = try #require(source.variables.first { $0.name == "devices" })
        let declaration = try #require(source.symmetricCollections.first { $0.name == "devices" })
        let action = try #require(source.actions.first { $0.name == "advance" })
        let compiledAction = try #require(compilation.semantics.actions.first)
        let machineVariable = try #require(
            compilation.machineSurfacePlan.variables.first { $0.formalName == "devices" }
        )
        let machineCollection = try #require(machineVariable.symmetricCollection)
        let initialState = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let successors = try CompiledRuntime(compilation: compilation)
            .successors(for: compiledAction.id, from: initialState)
        let rendered = compilation.renderedTLAModuleBundle().tla
        let repeated = try CompilerPipelineCollectionModel.spec.compile()
        let repeatedRendered = repeated.renderedTLAModuleBundle().tla
        let hasOuterExistential: Bool
        if case .existsAction = action.body {
            hasOuterExistential = true
        } else {
            hasOuterExistential = false
        }

        #expect(devices.collectionType == .dictionary(2))
        #expect(declaration.variable == devices)
        #expect(declaration.verificationScope == 2)
        #expect(action.bindings.isEmpty)
        #expect(compiledAction.bindings.count == 1)
        #expect(compiledAction.bindings[0].values == declaration.metadata.members)
        #expect(compiledAction.symmetricCollection == compilation.layout.variableID(named: "devices"))
        #expect(machineVariable.swiftType == "[CompilerPipelineMember.ID: Int]")
        #expect(machineCollection.formalName == "devices")
        #expect(compilation.machineSurfacePlan.symmetricCollections == [machineCollection])
        #expect(hasOuterExistential)
        #expect(try successors.map { successor in
            try successor.arguments.map { try $0.rendered(using: compilation.layout) }
        } == declaration.metadata.members.map { [$0] })
        #expect(rendered.contains("advance("))
        #expect(!rendered.contains("__swift_tla_binder_"))
        #expect(rendered.contains("advance__0 == advance(DevicesMember0)"))
        #expect(rendered.contains("advance__1 == advance(DevicesMember1)"))
        #expect(repeated.identity == compilation.identity)
        #expect(repeatedRendered == rendered)
    }

    @Test("lowered collection actions retain nested existential bodies")
    func loweredCollectionActionsRetainNestedExistentials() throws {
        let devices = SymmetricCollectionVar<CompilerPipelineMember, Int>("devices")
        let specification = TLASpec("NestedCollectionExistential") {
            SymmetricCollection(devices, verificationScope: 2, initial: 0)
            CollectionAction("advance", on: devices) { member in
                .existsAction(
                    "choice",
                    .setLiteral([.int(1)]),
                    devices.update(member, to: 1)
                )
            }
        }

        let first = try specification.loweredSourceModel()
        let second = try first.loweredSourceModel()
        let firstAction = try #require(first.actions.first)
        let secondAction = try #require(second.actions.first)
        let firstCompilation = try first.compile()
        let secondCompilation = try second.compile()
        let compiledAction = try #require(firstCompilation.semantics.actions.first)

        #expect(firstAction == secondAction)
        #expect(firstAction.bindings.isEmpty)
        #expect(compiledAction.bindings[0].values == specification.symmetricCollections[0].metadata.members)
        guard case .existsAction = compiledAction.body else {
            Issue.record("Expected the authored nested existential to remain in the compiled body")
            return
        }
        #expect(firstCompilation.identity == secondCompilation.identity)
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
        let source = compilation.renderedTLAModuleBundle().tla
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
                .init(
                    name: "value",
                    initialization: .expression(.value(.int(1))),
                    generatedSwiftType: "Int",
                    origin: .source
                )
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
