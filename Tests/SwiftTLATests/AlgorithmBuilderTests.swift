import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@Suite("PlusCal algorithm builders")
struct AlgorithmBuilderTests {
    private enum ProcedureName: String, CaseIterable {
        case work
    }

    private enum GeneratedSurfaceKey: String, FiniteTLAValueDomain {
        case value

        static let defaultValue = Self.value
        static let finiteValues = [Self.value]
    }

    private func initialState(of spec: TLASpec) throws -> (CompiledSpecification, CompiledState) {
        let compilation = try spec.compile()
        let state = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        return (compilation, state)
    }

    private func successor(
        named name: String,
        arguments: [TLAValue] = [],
        in compilation: CompiledSpecification,
        from state: CompiledState
    ) throws -> CompiledState {
        try #require(successors(named: name, arguments: arguments, in: compilation, from: state).first)
    }

    private func successors(
        named name: String,
        arguments: [TLAValue]? = nil,
        in compilation: CompiledSpecification,
        from state: CompiledState
    ) throws -> [CompiledState] {
        let action = try #require(compilation.layout.actionID(named: name))
        return try CompiledRuntime(compilation: compilation)
            .successors(for: action, from: state)
            .filter {
                guard let arguments else { return true }
                return try $0.arguments.map { try $0.rendered(using: compilation.layout) } == arguments
            }
            .map(\.state)
    }

    private func value(
        named name: String,
        in state: CompiledState,
        compilation: CompiledSpecification
    ) throws -> TLAValue {
        let variable = try #require(compilation.layout.variableID(named: name))
        return try state.value(for: variable).rendered(using: compilation.layout)
    }

    @Test("compiler lowers an authored algorithm")
    func compilerLowersAuthoredAlgorithm() throws {
        let algorithm = Algorithm("CompileAtGate", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            Do(TestControlLabel.advance) { Assign(count, to: count + 1) }
        })
        let source = TLASpec("CompileAtGate") { algorithm }

        #expect(source.variables.isEmpty)
        let compilation = try source.compile()
        #expect(compilation.description.variables.map(\.name) == ["pc", "count"])
        #expect(compilation.description.actions.map(\.name).contains("advance"))
    }

    @Test("top-level typed expression initialization retains its generated state type")
    func topLevelExpressionInitializationRetainsGeneratedStateType() throws {
        let source = #spec("TypedTopLevelFunction") { scope in
            let values = scope.sharedVar(
                "values",
                initial: Function<GeneratedSurfaceKey, Bool>.mapping { _ in false }
            )
            SwiftTLA.Action("Stay") { values.stays }
        }

        let compilation = try source.compile()
        let variable = try #require(
            compilation.machineSurfacePlan.variables.first { $0.formalName == "values" }
        )

        #expect(variable.swiftType == "Function<GeneratedSurfaceKey, Bool>")
    }

    @Test("unsupported Algorithm fairness fails before lowering")
    func unsupportedAlgorithmFairnessFailsBeforeLowering() {
        let algorithm = Algorithm("UnsupportedFairness") {
            Do(TestControlLabel.advance) { Stop() }
            WeakFairnessNext()
        }

        do {
            _ = try TLASpec("UnsupportedFairness") { algorithm }.compile()
            Issue.record("Expected unsupported Algorithm fairness to prevent compilation.")
        } catch let diagnostic as LanguageCapabilityDiagnostic {
            #expect(diagnostic.code == .unsupportedConstruct)
            #expect(diagnostic.construct.construct == .genericFairness)
            #expect(diagnostic.operation == .compilation)
            #expect(diagnostic.sourcePath == ["algorithm", "components[1]"])
            #expect(diagnostic.expected == "Generic TLA fairness is not admitted inside Algorithm.")
            #expect(diagnostic.actual == "generic fairness declaration inside Algorithm")
            #expect(diagnostic.nextSafeAction == "Use Algorithm(..., fairness:) for sequential fairness or Each(..., fairness:) for process fairness.")
        } catch {
            Issue.record("Expected LanguageCapabilityDiagnostic, received \(error).")
        }
    }

    @Test("unsupported Algorithm fairness in a procedure fails before lowering")
    func unsupportedProcedureFairnessFailsBeforeLowering() {
        let algorithm = Algorithm("UnsupportedProcedureFairness") {
            Procedure(ProcedureName.work) {
                Do(TestControlLabel.advance) { Return() }
                WeakFairnessNext()
            }
        }

        do {
            _ = try TLASpec("UnsupportedProcedureFairness") { algorithm }.compile()
            Issue.record("Expected unsupported procedure fairness to prevent compilation.")
        } catch let diagnostic as LanguageCapabilityDiagnostic {
            #expect(diagnostic.code == .unsupportedConstruct)
            #expect(diagnostic.construct.construct == .genericFairness)
            #expect(diagnostic.operation == .compilation)
            #expect(diagnostic.sourcePath == ["algorithm", "components[0]", "procedure", "components[1]"])
            #expect(diagnostic.expected == "Generic TLA fairness is not admitted inside Algorithm.")
            #expect(diagnostic.actual == "generic fairness declaration inside Algorithm")
            #expect(diagnostic.nextSafeAction == "Use Algorithm(..., fairness:) for sequential fairness or Each(..., fairness:) for process fairness.")
        } catch {
            Issue.record("Expected LanguageCapabilityDiagnostic, received \(error).")
        }
    }

    @Test("unsupported Algorithm property placement retains its construct")
    func unsupportedAlgorithmPropertyPlacementRetainsItsConstruct() {
        let cases: [(DeclaredLanguageConstruct, Algorithm)] = [
            (.algorithmAssume, Algorithm("UnsupportedAssume") {
                Assume(false)
            }),
            (.algorithmTheorem, Algorithm("UnsupportedTheorem") {
                Theorem(name: "Safety", always: .value(.bool(true)))
            })
        ]

        for (construct, algorithm) in cases {
            do {
                _ = try TLASpec("\(construct.rawValue)Gate") { algorithm }.compile()
                Issue.record("Expected \(construct.rawValue) to prevent compilation.")
            } catch let diagnostic as LanguageCapabilityDiagnostic {
                #expect(diagnostic.construct.construct == construct)
                #expect(diagnostic.operation == .compilation)
                #expect(diagnostic.expected == LanguageCapabilityLedger.capability(for: construct).boundary)
                #expect(diagnostic.nextSafeAction == LanguageCapabilityLedger.capability(for: construct).nextSafeAction)
            } catch {
                Issue.record("Expected LanguageCapabilityDiagnostic, received \(error).")
            }
        }
    }

    @Test("unsupported temporal refinement targets fail before linking")
    func unsupportedTemporalRefinementTargetsFailBeforeLinking() {
        let abstract = TLASpec("AbstractTarget") {
            FormalDefinition("Spec", parameters: [], body: true)
        }
        let instance = Instance("Abstract", of: abstract)
        let concrete = TLASpec("UnsupportedTarget") {
            instance
            Refinement(name: "Refines", instance: instance, operator: .liveSpec, mappings: [])
        }

        do {
            _ = try concrete.compile()
            Issue.record("Expected .liveSpec to prevent compilation.")
        } catch let diagnostic as LanguageCapabilityDiagnostic {
            #expect(diagnostic.construct.construct == .temporalRefinementLiveSpec)
            #expect(diagnostic.operation == .compilation)
            #expect(diagnostic.sourcePath == ["refinements", "Refines", "operator"])
            #expect(diagnostic.expected == "Temporal refinement targets that are live specifications are not supported in Algorithm.")
        } catch {
            Issue.record("Expected LanguageCapabilityDiagnostic, received \(error).")
        }
    }

    @Test("action completion preserves assigned compiler control state")
    func actionCompletionPreservesAssignedCompilerControlState() {
        let programCounter = NamedVar(
            name: CompilerControlSymbol.programCounter.rawValue,
            initialization: .value(.string("start")),
            origin: .programCounter
        )
        let action = ActionNormalization.complete(
            .assign(.programCounter, .controlLocation(.done)),
            variables: [programCounter]
        )

        #expect(assignedVars(action).contains(.programCounter))
        #expect(!explicitUnchanged(action).contains(.programCounter))
    }

    @Test("rendered action headers use compiled process bindings")
    func renderedActionHeadersUseCompiledProcessBindings() throws {
        let algorithm = Algorithm("BoundProcessHeader", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            Each(Node.all, fairness: .weak) { _ in
                Do(TestControlLabel.advance) { Assign(count, to: count + 1) }
            }
        })

        let module = try TLASpec("BoundProcessHeader") { algorithm }
            .compile()
            .renderedTLAModuleBundle()
            .tla
        #expect(module.contains("advance(b1) =="))
        #expect(module.contains("__swift_tla_binder_") == false)
    }

    @Test("algorithm builder preserves the order of many elements")
    func algorithmBuilderPreservesManyElementOrder() {
        let algorithm = Algorithm("OrderedElements") {
            Do(TestControlLabel.acquire) { Stop() }
            Do(TestControlLabel.advance) { Stop() }
            Do(TestControlLabel.check) { Stop() }
            Do(TestControlLabel.choose) { Stop() }
            Do(TestControlLabel.copy) { Stop() }
            Do(TestControlLabel.done) { Stop() }
            Do(TestControlLabel.enter) { Stop() }
            Do(TestControlLabel.finish) { Stop() }
            Do(TestControlLabel.hold) { Stop() }
            Do(TestControlLabel.increment) { Stop() }
            Do(TestControlLabel.mark) { Stop() }
            Do(TestControlLabel.open) { Stop() }
        }

        #expect(algorithm.model.sequentialSteps.map(\.label.name) == [
            "acquire", "advance", "check", "choose", "copy", "done",
            "enter", "finish", "hold", "increment", "mark", "open"
        ])
    }

    @Test("Each records its process identity structurally")
    func eachRecordsCurrentProcess() {
        let algorithm = Algorithm("CurrentProcess") {
            Each(Node.all) { node in
                Do(AlgorithmLabel.receive) { Assert(node.expr == node.expr) }
            }
        }

        guard case .process(let process) = algorithm.model.components.first,
              case .step(let step) = process.components.first,
              case .assert(let condition) = step.statements.first
        else {
            Issue.record("Expected one process assertion")
            return
        }
        #expect(condition == .equal(.currentProcess, .currentProcess))
    }

    @Test("current-process replacement preserves lexical bindings")
    func currentProcessReplacementPreservesLexicalBindings() {
        let expression = StateExpr.forAll(
            .setLiteral([.int(1)]),
            "self",
            .equal(.currentProcess, .variable("self"))
        )

        #expect(expression.replacingCurrentProcess(with: .variable("self")) == .forAll(
            .setLiteral([.int(1)]),
            "self_1",
            .equal(.variable("self"), .variable("self_1"))
        ))

        let statement = AlgorithmStatementModel.letBinding(
            variable: "self",
            value: .int(1),
            [.assert(.equal(.currentProcess, .variable("self")))]
        )
        #expect(statement.replacingCurrentProcess(with: .variable("self")) == .letBinding(
            variable: "self_1",
            value: .int(1),
            [.assert(.equal(.variable("self"), .variable("self_1")))]
        ))
    }

    @Test("process-local family references preserve lexical bindings")
    func processLocalFamilyReplacementPreservesLexicalBindings() {
        let scope = ProcessScope()
        let local = scope.localVar("count", initial: 0)
        #expect(local.family(for: Node.self).raw == .processLocalFamily("count"))

        let expression = StateExpr.forAll(
            .setLiteral([.int(1)]),
            "count",
            .equal(.processLocalFamily("count"), .variable("count"))
        )
        #expect(expression.replacingProcessLocalFamily(named: "count", with: .variable("count")) == .forAll(
            .setLiteral([.int(1)]),
            "count_1",
            .equal(.variable("count"), .variable("count_1"))
        ))

        let statement = AlgorithmStatementModel.letBinding(
            variable: "count",
            value: .int(1),
            [.assert(.equal(.processLocalFamily("count"), .variable("count")))]
        )
        #expect(statement.replacingProcessLocalFamily(named: "count", with: .variable("count")) == .letBinding(
            variable: "count_1",
            value: .int(1),
            [.assert(.equal(.variable("count"), .variable("count_1")))]
        ))
    }

    @Test("statement macros expand into their surrounding atomic block")
    func expandsTypedStatementMacro() throws {
        let algorithm = Algorithm("MacroLock", scoped: { scope in
            let lock = scope.sharedVar("lock", initial: 1)
            let acquire = Macro { (value: MacroParameter<Int>) in
                Await(value == 1)
                Assign(value, to: 0)
            }
            let release = Macro { (value: MacroParameter<Int>) in
                Assign(value, to: 1)
            }

            Each(Node.all) { _ in
                Do(TestControlLabel.acquire) { acquire(lock) }
                Do(TestControlLabel.release) { release(lock) }
            }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "acquire", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "lock", in: next, compilation: compilation) == .int(0))
    }

    @Test("two-parameter statement macros bind each argument in caller scope")
    func expandsTwoParameterStatementMacro() throws {
        let algorithm = Algorithm("CopyValue", scoped: { scope in
            let destination = scope.sharedVar("destination", initial: 0)
            let source = scope.sharedVar("source", initial: 7)
            let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                Assign(target, to: value.expr)
            }

            Do(TestControlLabel.copy) { copy(destination, source) }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "copy", in: compilation, from: initial)
        #expect(try value(named: "destination", in: next, compilation: compilation) == .int(7))
        #expect(try value(named: "source", in: next, compilation: compilation) == .int(7))
    }

    @Test("statement macros retain formal expression arguments in read positions")
    func expandsExpressionMacroArguments() throws {
        let algorithm = Algorithm("OffsetValue", scoped: { scope in
            let destination = scope.sharedVar("destination", initial: 0)
            let source = scope.sharedVar("source", initial: 7)
            let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                Assign(target, to: value.expr)
            }

            Do(TestControlLabel.copy) { copy(destination, source.expr + 1) }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "copy", in: compilation, from: initial)
        #expect(try value(named: "destination", in: next, compilation: compilation) == .int(8))
    }

    @Test("statement macros report expression assignment targets during validation")
    func rejectsExpressionMacroAssignmentTarget() {
        let algorithm = Algorithm("RejectedMacroTarget", scoped: { scope in
            let destination = scope.sharedVar("destination", initial: 0)
            let write = Macro { (target: MacroParameter<Int>) in
                Assign(target, to: 0)
            }

            Do(TestControlLabel.write) { write(destination.expr + 1) }
        })

        #expect(algorithm.validate().map(\.code).contains(.statementMacroAssignmentTarget))
        let spec = TLASpec("RejectedMacroTarget") { algorithm }
        #expect(throws: AlgorithmValidationError.self) {
            try spec.compile()
        }
    }

    @Test("algorithm substitution preserves lexical scope and writable targets")
    func substitutesAlgorithmStatementsStructurally() {
        let capture = AlgorithmStatementModel.letBinding(
            variable: "source",
            value: .value(.int(0)),
            [
                .set(target: .root("parameter"), value: .variable("parameter"))
            ]
        )
        let substituted = capture.substitutingVariable(
            "parameter",
            with: .variable("source"),
            assignmentTargets: .replaceWhenVariable
        )

        guard case .letBinding(variable: let binder, value: _, let body) = substituted,
              case .set(let target, let value) = body.first,
              case .root(let root) = target
        else {
            Issue.record("Expected a capture-safe bound assignment.")
            return
        }
        #expect(binder == "source_1")
        #expect(root == "source")
        #expect(value == .variable("source"))

        let shadowed = AlgorithmStatementModel.letBinding(
            variable: "parameter",
            value: .variable("parameter"),
            [
                .set(target: .root("parameter"), value: .variable("parameter"))
            ]
        ).substitutingVariable(
            "parameter",
            with: .variable("source"),
            assignmentTargets: .replaceWhenVariable
        )

        guard case .letBinding(variable: let shadowBinder, value: let definition, let shadowBody) = shadowed,
              case .set(let shadowTarget, let shadowValue) = shadowBody.first,
              case .root(let shadowRoot) = shadowTarget
        else {
            Issue.record("Expected a shadowed assignment.")
            return
        }
        #expect(shadowBinder == "parameter")
        #expect(definition == .variable("source"))
        #expect(shadowRoot == "parameter")
        #expect(shadowValue == .variable("parameter"))
    }

    @Test("typed procedure builders use deterministic formal parameter slots")
    func buildsTypedProcedure() throws {
        let algorithm = Algorithm("ProcedureBuilder", scoped: { scope in
            let output = scope.sharedVar("output", initial: 0)
            Procedure(ProcedureName.work, parameters: Int.self, scoped: { value, scope in
                let offset = scope.localVar("offset", initial: 1)
                Do(TestControlLabel.enter) {
                    Assign(output, to: value.expr + offset.expr)
                    Return()
                }
            })
            Do(TestControlLabel.start) { Call(ProcedureName.work, with: 7) }
            Do(TestControlLabel.finished) { Stop() }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let afterCall = try successor(named: "start", in: compilation, from: initial)
        #expect(try value(named: "parameter0", in: afterCall, compilation: compilation) == .int(7))
        #expect(try value(named: "pc", in: afterCall, compilation: compilation) == .string("enter"))

        let rendered = try TLASpec("ProcedureBuilderExport") {
            FormalDefinition("Marker", parameters: [], body: .value(.string("procedure.work.enter")))
            algorithm
        }.compile().renderedTLAModuleBundle().tla
        #expect(rendered.contains("Marker == \"procedure.work.enter\""))
        #expect(rendered.contains("pc' = \"enter\""))
        #expect(!rendered.contains("pc' = \"procedure.work.enter\""))
    }

    @Test("procedure source bindings normalize to builder formal slots")
    func generatedProcedureKeepsParserFidelity() {
    }

    @Test("parameterless statement macros expand into their surrounding atomic block")
    func expandsParameterlessStatementMacro() throws {
        let algorithm = Algorithm("ParameterlessMacro", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            let increment = Macro {
                Assign(count, to: count + 1)
            }

            Do(TestControlLabel.increment) { increment() }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "increment", in: compilation, from: initial)
        #expect(try value(named: "count", in: next, compilation: compilation) == .int(1))
    }

    @Test("formal function domains stay typed through the builder")
    func buildsFilteredFunctionInitialDomain() throws {
        let nodes = SetExpr<Node>.literal(.first, .second)
        let choices = Where(
            Functions(from: Node.all, to: Subsets(of: nodes))
        ) { successor in
            All(Node.all) { node in
                successor[node].cardinality == 1
            }
        }
        let algorithm = Algorithm("ReachableGraph", scoped: { scope in
            let _ = scope.sharedVar("successors", in: choices)
            Do(TestControlLabel.done) { Stop() }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let compilation = try spec.compile()
        #expect(try CompiledRuntime(compilation: compilation).initialStates().count == 4)
    }

    @Test("static formal selection uses the matching finite value")
    func selectsStaticFormalValue() {
        let selected = Select(
            from: SetExpr<Int>.literal(1, 2, 3),
            matching: { value in value.expr % 2 == 0 }
        )

        #expect(selected.raw == .value(.int(2)))
    }

    @Test("static formal selection can choose a filtered function")
    func selectsFilteredFormalFunction() {
        let nodes = SetExpr<Node>.literal(.first, .second)
        let selected = Select(
            from: Where(Functions(from: Node.all, to: Subsets(of: nodes))) { successor in
                All(Node.all) { node in successor[node].cardinality == 1 }
            },
            matching: { successor in successor.expr == successor.expr }
        )

        guard case .value(.function) = selected.raw else {
            Issue.record("A static filtered selection must produce a formal function value.")
            return
        }
    }

    @Test("generated models retain typed filtered function domains")
    func generatedModelRetainsFilteredFunctionDomain() throws {
        let compilation = try FunctionDomainGeneratedModel.spec.compile()
        #expect(try CompiledRuntime(compilation: compilation).initialStates().count == 4)
    }

    @Test("generated models retain static formal selections")
    func generatedModelRetainsStaticFormalSelection() throws {
        let (compilation, state) = try initialState(of: StaticFormalSelectionModel.spec)
        #expect(try value(named: "current", in: state, compilation: compilation) == .int(2))
    }

    @Test("generated models retain static filtered function selections")
    func generatedModelRetainsStaticFilteredFunctionSelection() throws {
        let compilation = try StaticFilteredFunctionSelectionModel.spec.compile()
        #expect(try CompiledRuntime(compilation: compilation).initialStates().count == 1)
    }

    @Test("statement macros accept the current typed process identifier")
    func expandsMacroWithProcessIdentifier() throws {
        let algorithm = Algorithm("MacroProcess", scoped: { scope in
            let marked = scope.sharedVar(
                "marked",
                initial: Function<Node, Bool>.literal((.first, false), (.second, false))
            )
            let mark = Macro { (node: MacroParameter<Node>) in
                Assign(marked, to: marked.updating(node, to: true))
            }

            Each(Node.all) { node in
                Do(TestControlLabel.mark) { mark(node) }
                Do(TestControlLabel.done) { Stop() }
            }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "mark", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "marked", in: next, compilation: compilation)
            == .function([.string("first"): .bool(true), .string("second"): .bool(false)]))
    }

    @Test("generated models compare macro process identifiers through both construction paths")
    func generatedMacroProcessModelKeepsParserFidelity() {
    }

    @Test("process control initialization joins typed process domains")
    func initializesControlAcrossProcessDomains() throws {
        let algorithm = Algorithm("MixedProcesses") {
            Each(Node.all) { _ in
                Do(TestControlLabel.stringProcess) { Stop() }
            }
            Each(OtherNode.all) { _ in
                Do(TestControlLabel.otherProcess) { Stop() }
            }
        }

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        #expect(try value(named: "pc", in: initial, compilation: compilation) == .function([
            .string("first"): .string("stringProcess"),
            .string("second"): .string("stringProcess"),
            .string("other"): .string("otherProcess")
        ]))
        #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("({\"first\", \"second\"} \\cup {\"other\"})"))
        #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("__pcal_initial_process =") == false)
    }

    @Test("a begin-style algorithm keeps a scalar program counter")
    func lowersSequentialAlgorithmWithoutInventingAProcess() throws {
        let algorithm = Algorithm("SequentialCounter", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Do(TestControlLabel.increment) {
                Let(value + 1) { nextValue in
                    Assign(value, to: nextValue.expr)
                }
            }
            Do(TestControlLabel.finish) {
                Stop()
            }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        #expect(spec.variables.map(\.name) == ["pc", "value"])
        #expect(spec.actions.map(\.name) == ["increment", "finish", "Terminating"])
        #expect(spec.actions.allSatisfy { $0.bindings.isEmpty })

        let (compilation, initial) = try initialState(of: spec)
        guard let programCounter = compilation.layout.programCounterID() else {
            Issue.record("Expected the compiled layout to declare a program counter")
            return
        }
        let programCounterVariable = compilation.layout.variables.first { $0.id == programCounter }
        #expect(programCounterVariable?.declaration.origin == .programCounter)
        guard case .controlLocation(let initialLocation) = try initial.value(for: programCounter) else {
            Issue.record("Expected the compiled program counter to store a control location")
            return
        }
        #expect(compilation.layout.controlLocation(initialLocation)?.sourceName == "increment")
        #expect(try value(named: "pc", in: initial, compilation: compilation) == .string("increment"))
        let next = try successor(named: "increment", in: compilation, from: initial)
        #expect(try value(named: "value", in: next, compilation: compilation) == .int(1))
        #expect(try value(named: "pc", in: next, compilation: compilation) == .string("finish"))
    }

    @Test("sequential Algorithm fairness preserves scalar control and WF Next")
    func lowersSequentialAlgorithmFairness() throws {
        let algorithm = Algorithm("FairSequential", fairness: .weak, scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Do(TestControlLabel.increment) { Assign(value, to: value + 1) }
        })

        let spec = try loweredSourceSpecification(algorithm)
        #expect(spec.variables.map(\.name) == ["pc", "value"])
        #expect(spec.actions.map(\.name) == ["increment", "Terminating"])
        #expect(spec.actions.allSatisfy { $0.bindings.isEmpty })
        #expect(spec.fairness == [.weakFairnessNext])
        #expect(try renderedSourceAlgorithmPlusCal(algorithm).contains("--fair algorithm FairSequential"))
        #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("WF_<<pc, value>>(Next)"))
    }

    @Test("sequential Algorithm fairness rejects process and empty bodies")
    func rejectsSequentialFairnessWithoutSequentialSteps() {
        let algorithms = [
            Algorithm("FairProcess", fairness: .weak) {
                Each(Node.all) { _ in
                    Do(TestControlLabel.advance) { Stop() }
                }
            },
            Algorithm("FairEmpty", fairness: .weak) {}
        ]

        for algorithm in algorithms {
            let diagnostics = algorithm.validate()
            #expect(diagnostics.map(\.code) == [.invalidSequentialFairness])
            #expect(diagnostics.map(\.anchor) == [.algorithm])
            #expect(throws: AlgorithmValidationError.self) {
                try TLASpec(algorithm.model.name) { algorithm }.compile()
            }
        }
    }

    @Test("typed first-slice builders preserve ordered process steps")
    func buildsBoundedAlgorithm() throws {
        let algorithm = Algorithm("ChangRoberts", scoped: { scope in
            let maximum = scope.sharedVar("maximum", initial: 0)
            Each(Node.all, scoped: { node, scope in
                let inbox = scope.localVar("inbox", initial: 0)
                Do(AlgorithmLabel.receive) {
                    Await(inbox > 0)
                    Choose(Node.all) { candidate in
                        If(candidate > node) {
                            Assign(maximum, to: candidate)
                            Goto(AlgorithmLabel.forward)
                        } else: {
                            Goto(AlgorithmLabel.receive)
                        }
                    }
                }
                Do(AlgorithmLabel.forward) {
                    Either {
                        Assign(maximum, to: maximum + 1)
                        Goto(AlgorithmLabel.receive)
                    } or: {
                        Goto(AlgorithmLabel.done)
                    }
                }
                Do(AlgorithmLabel.done) {
                    Stop()
                }
            })
        })

        #expect(algorithm.validate().isEmpty)
        #expect(algorithm.model.components.count == 2)
        #expect(algorithm.model.processes.count == 1)
        #expect(algorithm.model.processes[0].steps.map(\.label.name) == ["receive", "forward", "done"])
    }

    @Test("algorithm-level properties lower with the executable process")
    func lowersAlgorithmProperties() throws {
        let algorithm = Algorithm("Properties", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(AlgorithmLabel.receive) {
                    Assign(value, to: value + 1)
                    Goto(AlgorithmLabel.receive)
                }
            }
            Invariant("NonNegative") { value >= 0 }
            LeadsTo("EventuallyPositive", value == 0, value > 0)
            StateConstraint(value < 3)
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        #expect(spec.invariants.map(\.name) == ["NonNegative"])
        #expect(spec.temporalProperties.map(\.name) == ["EventuallyPositive"])
        #expect(spec.fairness.isEmpty)
        #expect(spec.constraint == .lessThan(.variable("value"), .value(.int(3))))
    }

    @Test("a process-local invariant lowers over its process family")
    func lowersProcessLocalInvariant() throws {
        let algorithm = Algorithm("LocalProperty") {
            Each(Node.all, scoped: { selfID, scope in
                let count = scope.localVar("count", initial: 0)
                Do(AlgorithmLabel.receive) { Skip() }
                Invariant("LocalCount") { count == 0 }
                Invariant("ControlLocation") {
                    At(AlgorithmLabel.receive, selfID) || Finished(selfID)
                }
            })
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        #expect(spec.invariants.map(\.name) == ["LocalCount", "ControlLocation"])
        guard case .forAll(_, let binding, let localCount) = spec.invariants[0].body else {
            Issue.record("A process-local invariant must lower to a bounded universal property.")
            return
        }
        #expect(binding == "process")
        #expect(localCount == .equal(
            .functionApply(.variable("count"), .variable("process")),
            .value(.int(0))
        ))
        guard case .forAll(_, _, let controlLocation) = spec.invariants[1].body else {
            Issue.record("A control-location property must lower to a bounded universal property.")
            return
        }
        #expect(controlLocation == .or(
            .equal(.functionApply(.programCounter, .variable("process")), .controlLocation(.init("receive"))),
            .equal(.functionApply(.programCounter, .variable("process")), .controlLocation(.done))
        ))
    }

    @Test("an authored control label must bind to an algorithm location")
    func rejectsUnknownControlLocation() {
        let algorithm = Algorithm("UnknownControlLocation") {
            Each(Node.all) { selfID in
                Do(AlgorithmLabel.receive) { Skip() }
                Invariant("AtMissing") { At(MissingAlgorithmLabel.missing, selfID) }
            }
        }

        do {
            _ = try TLASpec("UnknownControlLocation") { algorithm }.compile()
            Issue.record("Expected unknown control-location diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unknownControlLocation)
        } catch {
            Issue.record("Expected compilation diagnostic, got \(error)")
        }
    }

    @Test("duplicate authored invariants fail at compilation")
    func rejectsDuplicateAuthoredInvariants() {
        let algorithm = Algorithm("DuplicateInvariant", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Invariant("TypeOK") { value >= 0 }
            Invariant("TypeOK") { value <= 1 }
            Do(AlgorithmLabel.receive) { Stop() }
        })

        do {
            _ = try TLASpec("DuplicateInvariant") { algorithm }.compile()
            Issue.record("Expected duplicate invariant diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .duplicateInvariant)
        } catch {
            Issue.record("Expected compilation diagnostic, got \(error)")
        }
    }

    @Test("validation fails closed for invalid bounded algorithms")
    func rejectsInvalidAlgorithms() {
        let invalid = Algorithm("__pcal_invalid", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(EmptyNode.all) { _ in
                Do(AlgorithmLabel.receive) {
                    Assign(value, to: 1)
                    Assign(value, to: 2)
                    Goto(AlgorithmLabel.forward)
                }
                Do(AlgorithmLabel.receive) {
                    Stop()
                }
            }
            Invariant("outside") { value >= 0 }
        })

        let codes = Set(invalid.validate().map(\.code))
        #expect(codes.contains(.reservedName))
        #expect(codes.contains(.emptyDomain))
        #expect(codes.contains(.duplicateLabel))
        #expect(codes.contains(.invalidTarget))
        #expect(codes.contains(.duplicateRootWrite))
        #expect(throws: AlgorithmValidationError.self) {
            try invalid.requireValid()
        }
    }

    @Test("lowering initializes pc and binds every atomic action to a process")
    func lowersControlStateAndActionBindings() throws {
        let algorithm = Algorithm("BoundedCounter", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(AlgorithmLabel.receive) {
                    Assign(value, to: value + 1)
                    Goto(AlgorithmLabel.done)
                }
                Do(AlgorithmLabel.done) {
                    Stop()
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)

        #expect(spec.variables.map(\.name) == ["pc", "value"])
        #expect(spec.actions.map(\.name) == ["receive", "done", "Terminating"])
        for action in spec.actions where action.name != "Terminating" {
            #expect(action.bindings == [ActionBinding(name: "process", values: Node.finiteValues.map(\.tlaValue))])
        }

        let (compilation, initial) = try initialState(of: spec)
        #expect(try value(named: "pc", in: initial, compilation: compilation) == .function([
            .string("first"): .string("receive"),
            .string("second"): .string("receive")
        ]))
    }

    @Test("an unconditional single-loop process does not invent a program counter")
    func elidesRedundantProgramCounter() throws {
        let algorithm = Algorithm("SingleLoop", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                While(TestControlLabel.advance, true) {
                    Assign(value, to: value + 1)
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        #expect(spec.variables.map(\.name) == ["value"])
        #expect(spec.actions.map(\.name) == ["pcalProcess1"])
        let rendered = try spec.compile().renderedTLAModuleBundle().tla
        #expect(rendered.contains("VARIABLES pc") == false)

        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "pcalProcess1", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "value", in: next, compilation: compilation) == .int(1))
    }

    @Test("lowered atomic actions advance pc and stop before the explicit terminating self loop")
    func lowersAtomicSemantics() throws {
        let algorithm = Algorithm("BoundedCounter", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(AlgorithmLabel.receive) {
                    Assign(value, to: value + 1)
                    Goto(AlgorithmLabel.done)
                }
                Do(AlgorithmLabel.done) {
                    Stop()
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let advanced = try successor(named: "receive", arguments: [.string("first")], in: compilation, from: initial)

        #expect(try value(named: "value", in: advanced, compilation: compilation) == .int(1))
        #expect(try value(named: "pc", in: advanced, compilation: compilation) == .function([
            .string("first"): .string("done"),
            .string("second"): .string("receive")
        ]))

        let stopped = try successor(named: "done", arguments: [.string("first")], in: compilation, from: advanced)
        #expect(try value(named: "pc", in: stopped, compilation: compilation) == .function([
            .string("first"): .string("Done"),
            .string("second"): .string("receive")
        ]))

        let secondAdvanced = try successor(named: "receive", arguments: [.string("second")], in: compilation, from: stopped)
        let allDone = try successor(named: "done", arguments: [.string("second")], in: compilation, from: secondAdvanced)
        let terminal = try successor(named: "Terminating", in: compilation, from: allDone)
        #expect(try terminal.projection(using: compilation.layout) == allDone.projection(using: compilation.layout))
    }

    @Test("lowering represents process-local state as a function of self")
    func lowersLocalState() throws {
        let algorithm = Algorithm("LocalCounter") {
            Each(Node.all, scoped: { _, scope in
                let inbox = scope.localVar("inbox", initial: 0)
                Do(AlgorithmLabel.receive) {
                    Await(inbox == 0)
                    Assign(inbox, to: inbox + 1)
                    Goto(AlgorithmLabel.done)
                }
                Do(AlgorithmLabel.done) {
                    Stop()
                }
            })
        }

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        #expect(try value(named: "inbox", in: initial, compilation: compilation) == .function([
            .string("first"): .int(0),
            .string("second"): .int(0)
        ]))

        let advanced = try successor(named: "receive", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "inbox", in: advanced, compilation: compilation) == .function([
            .string("first"): .int(1),
            .string("second"): .int(0)
        ]))
    }

    @Test("local state can be initialized from its process identifier")
    func lowersProcessDependentLocalState() throws {
        let algorithm = Algorithm("ProcessDependentInitialState") {
            Each(Node.all, scoped: { selfID, scope in
                let _ = scope.localVar("leader", initial: selfID == .first)
                Do(AlgorithmLabel.done) { Stop() }
            })
        }

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        #expect(try value(named: "leader", in: initial, compilation: compilation) == .function([
            .string("first"): .bool(true),
            .string("second"): .bool(false)
        ]))
    }

    @Test("closed labels compile into process control locations")
    func compilesClosedLabels() throws {
        let algorithm = Algorithm("ClosedLabels", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(AlgorithmLabel.forward) {
                    Assign(value, to: value + 1)
                    Goto(AlgorithmLabel.done)
                }
                Do(AlgorithmLabel.done) { Stop() }
            }
        })

        #expect(algorithm.validate().isEmpty)
        #expect(try loweredSourceSpecification(algorithm).actions.map(\.name).contains("forward"))
    }

    @Test("the end of an Each machine reaches its builder-owned Done state")
    func eachMachineEndsInDone() throws {
        let algorithm = Algorithm("ImplicitStop", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.finish) {
                    Assign(value, to: value + 1)
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let terminal = try successor(named: "finish", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "pc", in: terminal, compilation: compilation) == .function([
            .string("first"): .string("Done"),
            .string("second"): .string("finish")
        ]))
    }

    @Test("an unlabeled transfer falls through to the next Do block")
    func intermediateDoFallsThrough() throws {
        let algorithm = Algorithm("Fallthrough", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.prepare) {
                    Assign(value, to: value + 1)
                }
                Do(TestControlLabel.finish) {
                    Assign(value, to: value + 1)
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let advanced = try successor(named: "prepare", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "pc", in: advanced, compilation: compilation) == .function([
            .string("first"): .string("finish"),
            .string("second"): .string("prepare")
        ]))
    }

    @Test("TLASpec accepts an algorithm component and lowers it before checking")
    func algorithmComposesIntoTLASpec() throws {
        let algorithm = Algorithm("Composed", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.finish) { Assign(value, to: value + 1) }
            }
            Invariant("nonNegative") { value >= 0 }
        })

        let spec = TLASpec("Composed") {
            algorithm
        }
        let compiled = try spec.loweredSourceModel()
        #expect(compiled.variables.map(\.name) == ["pc", "value"])
        #expect(compiled.actions.map(\.name) == ["finish", "Terminating"])
        #expect(compiled.invariants.map(\.name) == ["nonNegative"])
    }

    @Test("algorithm formal definitions lower and export exactly once")
    func algorithmFormalDefinitionsRemainTopLevelFormalOperators() throws {
        let algorithm = Algorithm("FormalOperators", scoped: { scope in
            FormalDefinition("same", taking: Int.self, Int.self) { left, right in
                left == right
            }
            let _ = scope.sharedVar("value", initial: 0)
            Do(TestControlLabel.stop) { Stop() }
        })

        let lowered = try loweredSourceSpecification(algorithm)
        #expect(lowered.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "same",
                parameters: [.value("value0"), .value("value1")],
                body: .equal(.variable("value0"), .variable("value1"))
            )
        ])
        let renderedPlusCal = try renderedSourceAlgorithmPlusCal(algorithm)
        #expect(renderedPlusCal.contains("same(") && renderedPlusCal.contains(" == ("))

        let spec = TLASpec("FormalOperators") { algorithm }
        #expect(try spec.loweredSourceModel().formalOperatorDefinitions == lowered.formalOperatorDefinitions)
        let rendered = try spec.compile().renderedTLAModuleBundle().tla
        #expect(rendered.components(separatedBy: "same(").count == 2)
    }

    @Test("When, Assert, With, and process fairness lower as formal semantics")
    func lowersMechanicalPlusCalStatements() throws {
        let algorithm = Algorithm("Mechanical", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            let selected = scope.sharedVar("selected", initial: 0)
            Each(Node.all, fairness: .weak) { node in
                Do(TestControlLabel.choose) {
                    When(count == 0)
                    With(SetExpr<Int>.literal(1, 2)) { choice in
                        Assert(choice > 0)
                        Assign(selected, to: choice)
                    }
                    Assign(count, to: count + 1)
                }
            }
        })

        #expect(algorithm.validate().isEmpty)
        let spec = try loweredSourceSpecification(algorithm)
        #expect(spec.invariants.map(\.name) == ["__pcal_assert_0", "__pcal_assert_1"])
        #expect(spec.fairness == [FairnessCondition.weakFairnessActionCall(.init(name: "choose", arguments: [.string("first")])),
            .weakFairnessActionCall(.init(name: "choose", arguments: [.string("second")]))
        ])
        let rendered = try spec.compile().renderedTLAModuleBundle().tla
        #expect(rendered.contains("WF_<<pc, count, selected>>(choose__0)"))
        #expect(rendered.contains("WF_<<pc, count, selected>>(choose__1)"))

        let (compilation, initial) = try initialState(of: spec)
        let states = try successors(named: "choose", arguments: [.string("first")], in: compilation, from: initial)
        #expect(states.count == 2)
        #expect(Set(try states.map { try value(named: "selected", in: $0, compilation: compilation) }) == Set([.int(1), .int(2)]))
    }

    @Test("a false While condition advances control and a true condition loops")
    func lowersWhileAsFormalControl() throws {
        let algorithm = Algorithm("Loop", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            Each(Node.all) { _ in
                While(TestControlLabel.`repeat`, count < 2) {
                    Assign(count, to: count + 1)
                }
                Do(TestControlLabel.finish) { Stop() }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let looped = try successor(named: "repeat", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "count", in: looped, compilation: compilation) == .int(1))
        #expect(try value(named: "pc", in: looped, compilation: compilation) == .function([
            .string("first"): .string("repeat"),
            .string("second"): .string("repeat")
        ]))

        let count = try #require(compilation.layout.variableID(named: "count"))
        let atLimit = try looped.updating(count, to: .integer(2))
        let exited = try successor(named: "repeat", arguments: [.string("first")], in: compilation, from: atLimit)
        #expect(try value(named: "pc", in: exited, compilation: compilation) == .function([
            .string("first"): .string("finish"),
            .string("second"): .string("repeat")
        ]))
    }

    @Test("a false outer guard does not evaluate a body-local LET")
    func shortCircuitsBoundedActionBindings() throws {
        let action = ActionExpr.and(
            .guard_(.value(.bool(false))),
            .define(
                "middle",
                .tupleDynamicAccess(.variable("sequence"), .value(.int(0))),
                .assign(.named("result"), .variable("middle"))
            )
        )

        let spec = TLASpec("ShortCircuitFixture") {
            Var("sequence", TupleExpr<Int>())
            Var("result", 0)
            SwiftTLA.Action("step") { action }
        }
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "step", in: compilation, from: initial)
        #expect(successors.isEmpty)
    }

    @Test("Assert is required only on the branch that reaches it")
    func scopesAssertToItsConditionalBranch() throws {
        let algorithm = Algorithm("ConditionalAssert", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.check) {
                    If(count == 0) {
                        Assert(count == 0)
                    } else: {
                        Assert(count == 1)
                    }
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let count = try #require(compilation.layout.variableID(named: "count"))
        #expect(try compilation.semantics.invariants.allSatisfy {
            try CompiledRuntime(compilation: compilation).invariantHolds($0, in: initial)
        })
        let alternate = try initial.updating(count, to: .integer(1))
        #expect(try compilation.semantics.invariants.allSatisfy {
            try CompiledRuntime(compilation: compilation).invariantHolds($0, in: alternate)
        })
    }

    @Test("Assert becomes a model-checker safety obligation")
    func checksAssertAsAnInvariant() throws {
        let algorithm = Algorithm("BrokenAssertion", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.check) {
                    Assert(count == 1)
                    Stop()
                }
            }
        })

        let result = try ModelChecker(compilation: try loweredSourceSpecification(algorithm).compile(), configuration: try .init(maximumStateLimit: 100_000, symmetryReduction: .disabled)).check()
        guard case .invariantViolated(let name, _, _) = result else {
            Issue.record("Expected Assert to produce an invariant violation, got \(result)")
            return
        }
        #expect(name == "__pcal_assert_0")
    }

    @Test("SharedVar range expands to the declared finite initial states")
    func lowersNondeterministicSharedInitialization() throws {
        let algorithm = Algorithm("HourClock", scoped: { scope in
            let hour = scope.sharedVar("hour", in: 1...3)
            Each(Node.all) { _ in
                Do(TestControlLabel.tick) {
                    When(hour < 3)
                    Assign(hour, to: hour + 1)
                    Stop()
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let compilation = try spec.compile()
        let hour = try #require(compilation.layout.variableID(named: "hour"))
        let states = try CompiledRuntime(compilation: compilation).initialStates()

        #expect(Set(try states.map { try $0.value(for: hour).rendered(using: compilation.layout) }) == [.int(1), .int(2), .int(3)])
        #expect(spec.variables.first { $0.name == "hour" }?.initialization == .memberOf(.setLiteral([
            .value(.int(1)), .value(.int(2)), .value(.int(3))
        ])))
    }

    @Test("SharedVar initial domains can depend on earlier formal state")
    func lowersDependentNondeterministicSharedInitialization() throws {
        let algorithm = Algorithm("DependentInitialDomain", scoped: { scope in
            let maximum = scope.sharedVar("maximum", initial: 2)
            let _ = scope.sharedVar(
                "candidate",
                in: Expr<SetExpr<Int>>(.integerRange(.int(0), maximum.stateExpr))
            )
            Do(TestControlLabel.stop) { Stop() }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let compilation = try spec.compile()
        let candidate = try #require(compilation.layout.variableID(named: "candidate"))
        let states = try CompiledRuntime(compilation: compilation).initialStates()
        #expect(Set(try states.map { try $0.value(for: candidate).rendered(using: compilation.layout) }) == [
            .int(0), .int(1), .int(2)
        ])
    }

    @Test("nested With statements keep independent lexical bindings")
    func lowersNestedWithScopes() throws {
        let algorithm = Algorithm("NestedWith", scoped: { scope in
            let selected = scope.sharedVar("selected", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.choose) {
                    With(SetExpr<Int>.literal(1, 2), SetExpr<Int>.literal(10, 20)) { outer, inner in
                        Assign(selected, to: outer.expr + inner.expr)
                    }
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "choose", in: compilation, from: initial)

        #expect(Set(try successors.map { try value(named: "selected", in: $0, compilation: compilation) }) == [.int(11), .int(12), .int(21), .int(22)])
    }

    @Test("With preserves ordered three-source bindings")
    func lowersThreeIndependentWithScopes() throws {
        let algorithm = Algorithm("ThreeWith", scoped: { scope in
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
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "choose", in: compilation, from: initial)

        #expect(Set(try successors.map { try value(named: "selected", in: $0, compilation: compilation) }) == [.int(111), .int(112), .int(211), .int(212)])
    }

    @Test("tuple patterns bind independently typed members")
    func lowersPairPatternBindings() throws {
        let algorithm = Algorithm("PairPattern", scoped: { scope in
            let selected = scope.sharedVar("selected", initial: 0)
            Do(TestControlLabel.choose) {
                With(SetExpr<Pair<Int, Bool>>.literal(
                    Pair(first: 1, second: true),
                    Pair(first: 2, second: false)
                )) { number, flag in
                    Assert((number.expr == 1) || !flag.expr)
                    Assign(selected, to: number.expr)
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "choose", in: compilation, from: initial)

        #expect(Set(try successors.map { try value(named: "selected", in: $0, compilation: compilation) }) == [.int(1), .int(2)])
    }

    @Test("Choose accepts a bounded Swift integer range")
    func lowersBoundedIntegerChoice() throws {
        let algorithm = Algorithm("BoundedChoice", scoped: { scope in
            let selected = scope.sharedVar("selected", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.choose) {
                    Choose(1...3) { choice in
                        Assign(selected, to: choice.expr)
                    }
                }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "choose", in: compilation, from: initial)
        #expect(Set(try successors.map { try value(named: "selected", in: $0, compilation: compilation) }) == [.int(1), .int(2), .int(3)])
    }

    @Test("dependent typed function initialization is evaluated after earlier initial state choices")
    func lowersDependentFunctionInitialization() throws {
        let algorithm = Algorithm("DependentInitial", scoped: { scope in
            let seed = scope.sharedVar("seed", in: SetExpr<Bool>.literal(false, true))
            let _ = scope.sharedVar("mirrors", initial: Function<Node, Bool>.mapping { _ in seed.expr })
            Each(Node.all) { _ in
                Do(TestControlLabel.stop) { Stop() }
            }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let compilation = try spec.compile()
        let seed = try #require(compilation.layout.variableID(named: "seed"))
        let mirrors = try #require(compilation.layout.variableID(named: "mirrors"))
        let states = try CompiledRuntime(compilation: compilation).initialStates()

        #expect(Set(try states.map { try $0.value(for: seed).rendered(using: compilation.layout) }) == [.bool(false), .bool(true)])
        #expect(Set(try states.map { try $0.value(for: mirrors).rendered(using: compilation.layout) }) == [
            .function([.string("first"): .bool(false), .string("second"): .bool(false)]),
            .function([.string("first"): .bool(true), .string("second"): .bool(true)])
        ])
    }

    @Test("process-local initialization reads the same process's earlier local state")
    func lowersDependentProcessLocalInitialization() throws {
        let algorithm = Algorithm("DependentProcessLocal") {
            Each(Node.all) { _, scope in
                let first = scope.localVar("first", initial: 1)
                let _ = scope.localVar("second", initial: first + 1)
                Do(TestControlLabel.stop) { Stop() }
            }
        }

        let compilation = try loweredSourceSpecification(algorithm).compile()
        let state = try firstCompiledState(in: compilation)

        #expect(try value(named: "first", in: state, compilation: compilation) == .function([
            .string("first"): .int(1), .string("second"): .int(1)
        ]))
        #expect(try value(named: "second", in: state, compilation: compilation) == .function([
            .string("first"): .int(2), .string("second"): .int(2)
        ]))
    }

    @Test("lowered process actions retain their generated parameter type")
    func preservesGeneratedProcessParameterType() throws {
        let algorithm = Algorithm("TypedProcess") {
            Each(Node.all) { _ in
                Do(TestControlLabel.mark) { Stop() }
                Do(TestControlLabel.done) { Stop() }
            }
        }

        let compilation = try loweredSourceSpecification(algorithm).compile()
        let action = try #require(compilation.machineSurfacePlan.actions.first { $0.swiftIdentifier == "mark" })
        #expect(action.bindings.map(\.swiftType) == ["Node"])
    }
}

private enum Node: String, FiniteTLAValueDomain, CaseIterable {
    case first
    case second

    static var defaultValue: Self { .first }
    static let finiteValues: [Node] = [.first, .second]

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum EmptyNode: String, FiniteTLAValueDomain {
    case none

    static var defaultValue: Self { .none }
    static let finiteValues: [EmptyNode] = []

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum OtherNode: String, FiniteTLAValueDomain {
    case one = "other"

    static var defaultValue: Self { .one }
    static let finiteValues: [OtherNode] = [.one]

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum AlgorithmLabel: String, CaseIterable {
    case receive
    case forward
    case done
}

private enum MissingAlgorithmLabel: String, CaseIterable {
    case missing
}

@TLAModel
private struct ProcedureGeneratedModel {
    enum Step: String, CaseIterable {
        case enter
        case start
        case finished
    }

    enum ProcedureName: String, CaseIterable {
        case work
    }

    static var spec: TLASpec {
        #spec("ProcedureGenerated") {
            Algorithm("ProcedureGenerated", scoped: { scope in
                let output = scope.sharedVar("output", initial: 0)
                Procedure(ProcedureName.work, parameters: Int.self, scoped: { value, scope in
                    let offset = scope.localVar("offset", initial: 1)
                    Do(Step.enter) {
                        Await(value.expr >= 0)
                        Assign(output, to: value.expr + offset.expr)
                        Return()
                    }
                })
                Do(Step.start) { Call(ProcedureName.work, with: 7) }
                Do(Step.finished) { Stop() }
            })
        }
    }
}

@TLAModel
private struct MacroProcessGeneratedModel {
    enum Step: String, CaseIterable {
        case mark
        case done
    }

    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case first
        case second

        static var defaultValue: Self { .first }
        static let finiteValues = allCases

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("MacroProcessGenerated") {
            Algorithm("MacroProcessGenerated", scoped: { scope in
                let marked = scope.sharedVar("marked", initial: Function<Node, Bool>.literal((.first, false), (.second, false)))
                let mark = Macro { (node: MacroParameter<Node>) in
                    Assign(marked, to: marked.updating(node, to: true))
                }

                Each(Node.all) { node in
                    Do(Step.mark) { mark(node) }
                    Do(Step.done) { Stop() }
                }
            })
        }
    }
}

@TLAModel
private struct FunctionDomainGeneratedModel {
    enum Step: String, CaseIterable { case done }

    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case first
        case second

        static var defaultValue: Self { .first }
        static let finiteValues = allCases

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("FunctionDomainGenerated") {
            Algorithm("FunctionDomainGenerated", scoped: { scope in
                let successors = scope.sharedVar("successors", in: Where(
                    Functions(from: Node.all, to: Subsets(of: SetExpr<Node>.literal(.first, .second)))
                ) { successor in
                    All(Node.all) { node in
                        successor[node].cardinality == 1
                    }
                })

                Do(Step.done) { Stop() }
                Invariant("OneSuccessorPerNode") {
                    All(Node.all) { node in
                        successors[node].cardinality == 1
                    }
                }
            })
        }
    }
}

@TLAModel
private struct StaticFormalSelectionModel {
    enum Step: String, CaseIterable { case done }

    static var spec: TLASpec {
        #spec("StaticFormalSelection") {
            Algorithm("StaticFormalSelection", scoped: { scope in
                let selected = Select(
                    from: SetExpr<Int>.literal(1, 2, 3),
                    matching: { value in value.expr % 2 == 0 }
                )
                let current: SharedVariable<Int> = scope.sharedVar("current", initial: selected)

                Do(Step.done) { Stop() }
                Invariant("SelectedEven") { current == 2 }
            })
        }
    }
}

@TLAModel
private struct StaticFilteredFunctionSelectionModel {
    enum Step: String, CaseIterable { case done }

    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case first
        case second
        case third
        case fourth

        static var defaultValue: Self { .first }
        static let finiteValues = allCases

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("StaticFilteredFunctionSelection") {
            Algorithm("StaticFilteredFunctionSelection", scoped: { scope in
                let successors = Select(
                    from: Where(Functions(
                        from: Node.all,
                        to: Subsets(of: SetExpr<Node>.literal(.first, .second, .third, .fourth))
                    )) { successor in
                        All(Node.all) { node in successor[node].cardinality == 2 }
                    },
                    matching: { successor in successor.expr == successor.expr }
                )
                let current: SharedVariable<Function<Node, SetExpr<Node>>> = scope.sharedVar(
                    "current",
                    initial: successors
                )

                Do(Step.done) { Stop() }
                Invariant("CurrentIsDefined") { current == current.expr }
            })
        }
    }
}
