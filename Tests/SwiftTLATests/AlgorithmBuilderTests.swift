import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@Suite("PlusCal algorithm builders")
struct AlgorithmBuilderTests {
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
            .filter { arguments == nil || try $0.arguments.map { try $0.rendered(using: compilation.layout) } == arguments }
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
        let algorithm = Algorithm("CompileAtGate") { scope in
            let count = scope.sharedVar("count", initial: 0)
            Do(TestControlLabel.advance) { Assign(count, to: count + 1) }
        }
        let source = TLASpec("CompileAtGate") { algorithm }

        #expect(source.variables.isEmpty)
        let compilation = try source.compile()
        #expect(compilation.spec.variables.map(\.name) == ["pc", "count"])
        #expect(compilation.spec.actions.map(\.name).contains("advance"))
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
            "self",
            .int(1),
            [.assert(.equal(.currentProcess, .variable("self")))]
        )
        #expect(statement.replacingCurrentProcess(with: .variable("self")) == .letBinding(
            "self_1",
            .int(1),
            [.assert(.equal(.variable("self"), .variable("self_1")))]
        ))
    }

    @Test("process-local family references preserve lexical bindings")
    func processLocalFamilyReplacementPreservesLexicalBindings() {
        var scope = ProcessScope()
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
            "count",
            .int(1),
            [.assert(.equal(.processLocalFamily("count"), .variable("count")))]
        )
        #expect(statement.replacingProcessLocalFamily(named: "count", with: .variable("count")) == .letBinding(
            "count_1",
            .int(1),
            [.assert(.equal(.variable("count"), .variable("count_1")))]
        ))
    }

    @Test("statement macros expand into their surrounding atomic block")
    func expandsTypedStatementMacro() throws {
        let algorithm = Algorithm("MacroLock") { scope in
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
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "acquire", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "lock", in: next, compilation: compilation) == .int(0))
    }

    @Test("two-parameter statement macros bind each argument in caller scope")
    func expandsTwoParameterStatementMacro() throws {
        let algorithm = Algorithm("CopyValue") { scope in
            let destination = scope.sharedVar("destination", initial: 0)
            let source = scope.sharedVar("source", initial: 7)
            let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                Assign(target, to: value.expr)
            }

            Do(TestControlLabel.copy) { copy(destination, source) }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "copy", in: compilation, from: initial)
        #expect(try value(named: "destination", in: next, compilation: compilation) == .int(7))
        #expect(try value(named: "source", in: next, compilation: compilation) == .int(7))
    }

    @Test("statement macros retain formal expression arguments in read positions")
    func expandsExpressionMacroArguments() throws {
        let algorithm = Algorithm("OffsetValue") { scope in
            let destination = scope.sharedVar("destination", initial: 0)
            let source = scope.sharedVar("source", initial: 7)
            let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                Assign(target, to: value.expr)
            }

            Do(TestControlLabel.copy) { copy(destination, source.expr + 1) }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "copy", in: compilation, from: initial)
        #expect(try value(named: "destination", in: next, compilation: compilation) == .int(8))
    }

    @Test("statement macros report expression assignment targets during validation")
    func rejectsExpressionMacroAssignmentTarget() {
        let algorithm = Algorithm("RejectedMacroTarget") { scope in
            let destination = scope.sharedVar("destination", initial: 0)
            let write = Macro { (target: MacroParameter<Int>) in
                Assign(target, to: 0)
            }

            Do(TestControlLabel.write) { write(destination.expr + 1) }
        }

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

        guard case .letBinding(let binder, _, let body) = substituted,
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

        guard case .letBinding(let shadowBinder, let definition, let shadowBody) = shadowed,
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
        let algorithm = Algorithm("ProcedureBuilder") { scope in
            let output = scope.sharedVar("output", initial: 0)
            Procedure("work", parameters: Int.self) { value in
                let offset = LocalVar("offset", initial: 1)
                offset
                Do(TestControlLabel.enter) {
                    Assign(output, to: value.expr + offset.expr)
                    Return()
                }
            }
            Do(TestControlLabel.start) { Call("work", with: 7) }
            Do(TestControlLabel.finished) { Stop() }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
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
        let algorithm = Algorithm("ParameterlessMacro") { scope in
            let count = scope.sharedVar("count", initial: 0)
            let increment = Macro {
                Assign(count, to: count + 1)
            }

            Do(TestControlLabel.increment) { increment() }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
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
        let algorithm = Algorithm("ReachableGraph") { scope in
            let successors = scope.sharedVar("successors", in: choices)
            Do(TestControlLabel.done) { Stop() }
        }

        let spec = try compiledSourceSpecification(algorithm)
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

        guard case .value(.function(let _)) = selected.raw else {
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
    func generatedModelRetainsStaticFormalSelection() {
        let (compilation, state) = try initialState(of: StaticFormalSelectionModel.spec)
        #expect(try value(named: "current", in: state, compilation: compilation) == .int(2))
    }

    @Test("generated models retain static filtered function selections")
    func generatedModelRetainsStaticFilteredFunctionSelection() {
        let compilation = try StaticFilteredFunctionSelectionModel.spec.compile()
        #expect(try CompiledRuntime(compilation: compilation).initialStates().count == 1)
    }

    @Test("statement macros accept the current typed process identifier")
    func expandsMacroWithProcessIdentifier() throws {
        let algorithm = Algorithm("MacroProcess") { scope in
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
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
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

        let spec = try compiledSourceSpecification(algorithm)
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
        let algorithm = Algorithm("SequentialCounter") { scope in
            let value = scope.sharedVar("value", initial: 0)
            Do(TestControlLabel.increment) {
                Let(value + 1) { nextValue in
                    Assign(value, to: nextValue.expr)
                }
            }
            Do(TestControlLabel.finish) {
                Stop()
            }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
        #expect(spec.variables.map(\.name) == ["value", "pc"])
        #expect(spec.actions.map(\.name) == ["increment", "finish", "Terminating"])
        #expect(spec.actions.allSatisfy { $0.bindings.isEmpty })

        let (compilation, initial) = try initialState(of: spec)
        let programCounter = try #require(compilation.layout.programCounterID())
        #expect(compilation.layout.variables.first { $0.id == programCounter }?.declaration.origin == .programCounter)
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

    @Test("typed first-slice builders preserve ordered process steps")
    func buildsBoundedAlgorithm() throws {
        let algorithm = Algorithm("ChangRoberts") { scope in
            let maximum = scope.sharedVar("maximum", initial: 0)
            Each(Node.all) { node, scope in
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
            }
        }

        #expect(algorithm.validate().isEmpty)
        #expect(algorithm.model.components.count == 2)
        #expect(algorithm.model.processes.count == 1)
        #expect(algorithm.model.processes[0].steps.map(\.label.name) == ["receive", "forward", "done"])
    }

    @Test("algorithm-level properties lower with the executable process")
    func lowersAlgorithmProperties() throws {
        let algorithm = Algorithm("Properties") { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(AlgorithmLabel.receive) {
                    Assign(value, to: value + 1)
                    Goto(AlgorithmLabel.receive)
                }
            }
            Invariant("NonNegative") { value >= 0 }
            LeadsTo("EventuallyPositive", value == 0, value > 0)
            WeakFairness("receive")
            StateConstraint(value < 3)
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
        #expect(spec.invariants.map(\.name) == ["NonNegative"])
        #expect(spec.temporalProperties.map(\.name) == ["EventuallyPositive"])
        #expect(spec.fairness.contains(.weakFairness("receive")))
        #expect(spec.constraint == .lessThan(.variable("value"), .value(.int(3))))
    }

    @Test("a process-local invariant lowers over its process family")
    func lowersProcessLocalInvariant() throws {
        let algorithm = Algorithm("LocalProperty") {
            Each(Node.all) { selfID, scope in
                let count = scope.localVar("count", initial: 0)
                Do(AlgorithmLabel.receive) { Skip() }
                Invariant("LocalCount") { count == 0 }
                Invariant("ControlLocation") {
                    At(AlgorithmLabel.receive, selfID) || Finished(selfID)
                }
            }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
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

    @Test("validation fails closed for invalid bounded algorithms")
    func rejectsInvalidAlgorithms() {
        let invalid = Algorithm("__pcal_invalid") { scope in
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
        }

        let codes = Set(invalid.validate().map(\.code))
        #expect(codes.contains(.reservedName))
        #expect(codes.contains(.emptyDomain))
        #expect(codes.contains(.duplicateLabel))
        #expect(codes.contains(.invalidTarget))
        #expect(codes.contains(.duplicateRootWrite))
        #expect(!codes.contains(.propertyBoundary))
        #expect(throws: AlgorithmValidationError.self) {
            try invalid.requireValid()
        }
    }

    @Test("lowering initializes pc and binds every atomic action to a process")
    func lowersControlStateAndActionBindings() throws {
        let algorithm = Algorithm("BoundedCounter") { scope in
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
        }

        let spec = try compiledSourceSpecification(algorithm)

        #expect(spec.variables.map(\.name) == ["value", "pc"])
        #expect(spec.actions.map(\.name) == ["receive", "done", "Terminating"])
        for action in spec.actions where action.name != "Terminating" {
            #expect(action.bindings == [ActionBinding(name: "process", values: Node.formalDomain.map(\.tlaValue))])
        }

        let (compilation, initial) = try initialState(of: spec)
        #expect(try value(named: "pc", in: initial, compilation: compilation) == .function([
            .string("first"): .string("receive"),
            .string("second"): .string("receive")
        ]))
    }

    @Test("an unconditional single-loop process does not invent a program counter")
    func elidesRedundantProgramCounter() throws {
        let algorithm = Algorithm("SingleLoop") { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                While(TestControlLabel.advance, true) {
                    Assign(value, to: value + 1)
                }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
        #expect(spec.variables.map(\.name) == ["value"])
        #expect(spec.actions.map(\.name) == ["pcalProcess1"])
        #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("pc") == false)

        let (compilation, initial) = try initialState(of: spec)
        let next = try successor(named: "pcalProcess1", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "value", in: next, compilation: compilation) == .int(1))
    }

    @Test("lowered atomic actions advance pc and stop before the explicit terminating self loop")
    func lowersAtomicSemantics() throws {
        let algorithm = Algorithm("BoundedCounter") { scope in
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
        }

        let spec = try compiledSourceSpecification(algorithm)
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
            Each(Node.all) { _, scope in
                let inbox = scope.localVar("inbox", initial: 0)
                Do(AlgorithmLabel.receive) {
                    Await(inbox == 0)
                    Assign(inbox, to: inbox + 1)
                    Goto(AlgorithmLabel.done)
                }
                Do(AlgorithmLabel.done) {
                    Stop()
                }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
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
            Each(Node.all) { selfID, scope in
                let leader = scope.localVar("leader", initial: selfID == .first)
                Do(AlgorithmLabel.done) { Stop() }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        #expect(try value(named: "leader", in: initial, compilation: compilation) == .function([
            .string("first"): .bool(true),
            .string("second"): .bool(false)
        ]))
    }

    @Test("closed labels compile into process control locations")
    func compilesClosedLabels() throws {
        let algorithm = Algorithm("ClosedLabels") { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(AlgorithmLabel.forward) {
                    Assign(value, to: value + 1)
                    Goto(AlgorithmLabel.done)
                }
                Do(AlgorithmLabel.done) { Stop() }
            }
        }

        #expect(algorithm.validate().isEmpty)
        #expect(try compiledSourceSpecification(algorithm).actions.map(\.name).contains("forward"))
    }

    @Test("the end of an Each machine reaches its builder-owned Done state")
    func eachMachineEndsInDone() throws {
        let algorithm = Algorithm("ImplicitStop") { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.finish) {
                    Assign(value, to: value + 1)
                }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let terminal = try successor(named: "finish", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "pc", in: terminal, compilation: compilation) == .function([
            .string("first"): .string("Done"),
            .string("second"): .string("finish")
        ]))
    }

    @Test("an unlabeled transfer falls through to the next Do block")
    func intermediateDoFallsThrough() throws {
        let algorithm = Algorithm("Fallthrough") { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.prepare) {
                    Assign(value, to: value + 1)
                }
                Do(TestControlLabel.finish) {
                    Assign(value, to: value + 1)
                }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let advanced = try successor(named: "prepare", arguments: [.string("first")], in: compilation, from: initial)
        #expect(try value(named: "pc", in: advanced, compilation: compilation) == .function([
            .string("first"): .string("finish"),
            .string("second"): .string("prepare")
        ]))
    }

    @Test("TLASpec accepts an algorithm component and lowers it before checking")
    func algorithmComposesIntoTLASpec() throws {
        let algorithm = Algorithm("Composed") { scope in
            let value = scope.sharedVar("value", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.finish) { Assign(value, to: value + 1) }
            }
            Invariant("nonNegative") { value >= 0 }
        }

        let spec = TLASpec("Composed") {
            algorithm
        }
        #expect(spec.variables.map(\.name) == ["value", "pc"])
        #expect(spec.actions.map(\.name) == ["finish", "Terminating"])
        #expect(spec.invariants.map(\.name) == ["nonNegative"])
    }

    @Test("algorithm formal definitions lower and export exactly once")
    func algorithmFormalDefinitionsRemainTopLevelFormalOperators() throws {
        let algorithm = Algorithm("FormalOperators") { scope in
            FormalDefinition("same", taking: Int.self, Int.self) { left, right in
                left == right
            }
            let value = scope.sharedVar("value", initial: 0)
            Do(TestControlLabel.stop) { Stop() }
        }

        let lowered = try compiledSourceSpecification(algorithm)
        #expect(lowered.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "same",
                parameters: [.value("value0"), .value("value1")],
                body: .equal(.variable("value0"), .variable("value1"))
            )
        ])
        #expect(try renderedSourceAlgorithmPlusCal(algorithm).contains("same(value0, value1) == (value0 = value1)"))

        let spec = TLASpec("FormalOperators") { algorithm }
        #expect(spec.formalOperatorDefinitions == lowered.formalOperatorDefinitions)
        #expect(try spec.compile().renderedTLAModuleBundle().tla.components(separatedBy: "same(value0, value1)").count == 2)
    }

    @Test("When, Assert, With, and process fairness lower as formal semantics")
    func lowersMechanicalPlusCalStatements() throws {
        let algorithm = Algorithm("Mechanical") { scope in
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
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try compiledSourceSpecification(algorithm)
        #expect(spec.invariants.map(\.name) == ["__pcal_assert_choose_0_0", "__pcal_assert_choose_0_1"])
        #expect(spec.fairness == [FairnessCondition.weakFairnessActionCall(.init(name: "choose", arguments: [.string("first")])),
            .weakFairnessActionCall(.init(name: "choose", arguments: [.string("second")]))
        ])
        let rendered = try spec.compile().renderedTLAModuleBundle().tla
        #expect(rendered.contains("WF_<<count, selected, pc>>(choose__0)"))
        #expect(rendered.contains("WF_<<count, selected, pc>>(choose__1)"))

        let (compilation, initial) = try initialState(of: spec)
        let states = try successors(named: "choose", arguments: [.string("first")], in: compilation, from: initial)
        #expect(states.count == 2)
        #expect(Set(try states.map { try value(named: "selected", in: $0, compilation: compilation) }) == Set([.int(1), .int(2)]))
    }

    @Test("a false While condition advances control and a true condition loops")
    func lowersWhileAsFormalControl() throws {
        let algorithm = Algorithm("Loop") { scope in
            let count = scope.sharedVar("count", initial: 0)
            Each(Node.all) { _ in
                While(TestControlLabel.`repeat`, count < 2) {
                    Assign(count, to: count + 1)
                }
                Do(TestControlLabel.finish) { Stop() }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
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

        let spec = TLASpec(
            name: "ShortCircuitFixture",
            variables: [
                NamedVar(name: "sequence", initial: .tuple([])),
                NamedVar(name: "result", initial: .int(0))
            ],
            actions: [NamedAction(name: "step", body: action)],
            invariants: []
        )
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "step", in: compilation, from: initial)
        #expect(successors.isEmpty)
    }

    @Test("Assert is required only on the branch that reaches it")
    func scopesAssertToItsConditionalBranch() throws {
        let algorithm = Algorithm("ConditionalAssert") { scope in
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
        }

        let spec = try compiledSourceSpecification(algorithm)
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
        let algorithm = Algorithm("BrokenAssertion") { scope in
            let count = scope.sharedVar("count", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.check) {
                    Assert(count == 1)
                    Stop()
                }
            }
        }

        let result = try ModelChecker(compilation: try compiledSourceSpecification(algorithm).compile(), configuration: .standard).check().underlyingOutcome
        guard case .invariantViolated(let name, _, _) = result else {
            Issue.record("Expected Assert to produce an invariant violation, got \(result)")
            return
        }
        #expect(name == "__pcal_assert_check_0_0")
    }

    @Test("SharedVar range expands to the declared finite initial states")
    func lowersNondeterministicSharedInitialization() throws {
        let algorithm = Algorithm("HourClock") { scope in
            let hour = scope.sharedVar("hour", in: 1...3)
            Each(Node.all) { _ in
                Do(TestControlLabel.tick) {
                    When(hour < 3)
                    Assign(hour, to: hour + 1)
                    Stop()
                }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
        let compilation = try spec.compile()
        let hour = try #require(compilation.layout.variableID(named: "hour"))
        let states = try CompiledRuntime(compilation: compilation).initialStates()

        #expect(Set(try states.map { try $0.value(for: hour).rendered(using: compilation.layout) }) == [.int(1), .int(2), .int(3)])
        #expect(spec.variables.first { $0.name == "hour" }?.initialSet == .setLiteral([
            .value(.int(1)), .value(.int(2)), .value(.int(3))
        ]))
    }

    @Test("SharedVar initial domains can depend on earlier formal state")
    func lowersDependentNondeterministicSharedInitialization() throws {
        let algorithm = Algorithm("DependentInitialDomain") { scope in
            let maximum = scope.sharedVar("maximum", initial: 2)
            let candidate = scope.sharedVar(
                "candidate",
                in: Expr<SetExpr<Int>>(.integerRange(.int(0), maximum.stateExpr))
            )
            Do(TestControlLabel.stop) { Stop() }
        }

        let spec = try compiledSourceSpecification(algorithm)
        let compilation = try spec.compile()
        let candidate = try #require(compilation.layout.variableID(named: "candidate"))
        let states = try CompiledRuntime(compilation: compilation).initialStates()
        #expect(Set(try states.map { try $0.value(for: candidate).rendered(using: compilation.layout) }) == [
            .int(0), .int(1), .int(2)
        ])
    }

    @Test("nested With statements keep independent lexical bindings")
    func lowersNestedWithScopes() throws {
        let algorithm = Algorithm("NestedWith") { scope in
            let selected = scope.sharedVar("selected", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.choose) {
                    With(SetExpr<Int>.literal(1, 2), SetExpr<Int>.literal(10, 20)) { outer, inner in
                        Assign(selected, to: outer.expr + inner.expr)
                    }
                }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "choose", in: compilation, from: initial)

        #expect(Set(try successors.map { try value(named: "selected", in: $0, compilation: compilation) }) == [.int(11), .int(12), .int(21), .int(22)])
    }

    @Test("With preserves ordered three-source bindings")
    func lowersThreeIndependentWithScopes() throws {
        let algorithm = Algorithm("ThreeWith") { scope in
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

        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "choose", in: compilation, from: initial)

        #expect(Set(try successors.map { try value(named: "selected", in: $0, compilation: compilation) }) == [.int(111), .int(112), .int(211), .int(212)])
    }

    @Test("tuple patterns bind independently typed members")
    func lowersPairPatternBindings() throws {
        let algorithm = Algorithm("PairPattern") { scope in
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
        }

        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "choose", in: compilation, from: initial)

        #expect(Set(try successors.map { try value(named: "selected", in: $0, compilation: compilation) }) == [.int(1), .int(2)])
    }

    @Test("Choose accepts a bounded Swift integer range")
    func lowersBoundedIntegerChoice() throws {
        let algorithm = Algorithm("BoundedChoice") { scope in
            let selected = scope.sharedVar("selected", initial: 0)
            Each(Node.all) { _ in
                Do(TestControlLabel.choose) {
                    Choose(1...3) { choice in
                        Assign(selected, to: choice.expr)
                    }
                }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
        let (compilation, initial) = try initialState(of: spec)
        let successors = try successors(named: "choose", in: compilation, from: initial)
        #expect(Set(try successors.map { try value(named: "selected", in: $0, compilation: compilation) }) == [.int(1), .int(2), .int(3)])
    }

    @Test("dependent typed function initialization is evaluated after earlier initial state choices")
    func lowersDependentFunctionInitialization() throws {
        let algorithm = Algorithm("DependentInitial") { scope in
            let seed = scope.sharedVar("seed", in: SetExpr<Bool>.literal(false, true))
            let mirrors = scope.sharedVar("mirrors", initial: Function<Node, Bool>.mapping { _ in seed.expr })
            Each(Node.all) { _ in
                Do(TestControlLabel.stop) { Stop() }
            }
        }

        let spec = try compiledSourceSpecification(algorithm)
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
}

private enum Node: String, FiniteDomainKey, PlusCalLabel, CaseIterable {
    case first
    case second

    static var defaultValue: Self { .first }
    static let formalDomain: [Node] = [.first, .second]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.node")

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum EmptyNode: String, FiniteDomainKey {
    case none

    static var defaultValue: Self { .none }
    static let formalDomain: [EmptyNode] = []
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.empty-node")

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum OtherNode: String, FiniteDomainKey {
    case one = "other"

    static var defaultValue: Self { .one }
    static let formalDomain: [OtherNode] = [.one]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.other-node")

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum AlgorithmLabel: String, PlusCalLabel, CaseIterable {
    case receive
    case forward
    case done
}

private enum MissingAlgorithmLabel: String, PlusCalLabel, CaseIterable {
    case missing
}

@TLAModel
private struct ProcedureGeneratedModel {
    static var spec: TLASpec {
        #spec("ProcedureGenerated") {
            Algorithm("ProcedureGenerated") { scope in
                let output = scope.sharedVar("output", initial: 0)
                Procedure("work", parameters: Int.self) { value in
                    let offset = LocalVar("offset", initial: 1)
                    Do(TestControlLabel.enter) {
                        Await(value.expr >= 0)
                        Assign(output, to: value.expr + offset.expr)
                        Return()
                    }
                }
                Do(TestControlLabel.start) { Call("work", with: 7) }
                Do(TestControlLabel.finished) { Stop() }
            }
        }
    }
}

@TLAModel
private struct MacroProcessGeneratedModel {
    enum Node: String, CaseIterable, FiniteDomainKey {
        case first
        case second

        static var defaultValue: Self { .first }
        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.macro-process-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("MacroProcessGenerated") {
            Algorithm("MacroProcessGenerated") { scope in
                let marked = scope.sharedVar("marked", initial: Function<Node, Bool>.literal((.first, false), (.second, false)))
                let mark = Macro { (node: MacroParameter<Node>) in
                    Assign(marked, to: marked.updating(node, to: true))
                }

                Each(Node.all) { node in
                    Do(TestControlLabel.mark) { mark(node) }
                    Do(TestControlLabel.done) { Stop() }
                }
            }
        }
    }
}

@TLAModel
private struct FunctionDomainGeneratedModel {
    enum Node: String, CaseIterable, FiniteDomainKey {
        case first
        case second

        static var defaultValue: Self { .first }
        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.function-domain-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("FunctionDomainGenerated") {
            Algorithm("FunctionDomainGenerated") { scope in
                let successors = scope.sharedVar("successors", in: Where(
                    Functions(from: Node.all, to: Subsets(of: SetExpr<Node>.literal(.first, .second)))
                ) { successor in
                    All(Node.all) { node in
                        successor[node].cardinality == 1
                    }
                })

                Do(TestControlLabel.done) { Stop() }
                Invariant("OneSuccessorPerNode") {
                    All(Node.all) { node in
                        successors[node].cardinality == 1
                    }
                }
            }
        }
    }
}

@TLAModel
private struct StaticFormalSelectionModel {
    static var spec: TLASpec {
        #spec("StaticFormalSelection") {
            Algorithm("StaticFormalSelection") { scope in
                let selected = Select(
                    from: SetExpr<Int>.literal(1, 2, 3),
                    matching: { value in value.expr % 2 == 0 }
                )
                let current = scope.sharedVar("current", initial: selected)

                Do(TestControlLabel.done) { Stop() }
                Invariant("SelectedEven") { current == 2 }
            }
        }
    }
}

@TLAModel
private struct StaticFilteredFunctionSelectionModel {
    enum Node: String, CaseIterable, FiniteDomainKey {
        case first
        case second
        case third
        case fourth

        static var defaultValue: Self { .first }
        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.static-function-selection-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("StaticFilteredFunctionSelection") {
            Algorithm("StaticFilteredFunctionSelection") { scope in
                let successors = Select(
                    from: Where(Functions(
                        from: Node.all,
                        to: Subsets(of: SetExpr<Node>.literal(.first, .second, .third, .fourth))
                    )) { successor in
                        All(Node.all) { node in successor[node].cardinality == 2 }
                    },
                    matching: { successor in successor.expr == successor.expr }
                )
                let current = scope.sharedVar("current", initial: successors)

                Do(TestControlLabel.done) { Stop() }
                Invariant("CurrentIsDefined") { current == current.expr }
            }
        }
    }
}
