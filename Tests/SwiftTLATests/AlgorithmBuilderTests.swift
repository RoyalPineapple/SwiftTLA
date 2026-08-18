import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@Suite("PlusCal algorithm builders")
struct AlgorithmBuilderTests {
    @Test("statement macros expand into their surrounding atomic block")
    func expandsTypedStatementMacro() throws {
        let algorithm = Algorithm("MacroLock") {
            let lock = SharedVar("lock", initial: 1)
            lock
            let acquire = Macro { (value: MacroParameter<Int>) in
                Await(value == 1)
                Assign(value, to: 0)
            }
            let release = Macro { (value: MacroParameter<Int>) in
                Assign(value, to: 1)
            }

            Each(Node.all) { _ in
                Do("acquire") { acquire(lock) }
                Do("release") { release(lock) }
            }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let acquire = try #require(spec.actions.first { $0.name == "acquire" })
        let invocation = try #require(actionInvocations(acquire).first)
        let successor = try #require(
            ActionEnumerator.enumerate(invocation.body, from: initial, varNames: spec.variables.map(\.name)).first
        )
        #expect(successor["lock"] == .int(0))
    }

    @Test("two-parameter statement macros bind each argument in caller scope")
    func expandsTwoParameterStatementMacro() throws {
        let algorithm = Algorithm("CopyValue") {
            let destination = SharedVar("destination", initial: 0)
            let source = SharedVar("source", initial: 7)
            destination
            source
            let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                Assign(target, to: value.expr)
            }

            Do("copy") { copy(destination, source) }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let copy = try #require(spec.actions.first { $0.name == "copy" })
        let successor = try #require(
            ActionEnumerator.enumerate(copy.body, from: initial, varNames: spec.variables.map(\.name)).first
        )
        #expect(successor["destination"] == .int(7))
        #expect(successor["source"] == .int(7))
    }

    @Test("statement macros retain formal expression arguments in read positions")
    func expandsExpressionMacroArguments() throws {
        let algorithm = Algorithm("OffsetValue") {
            let destination = SharedVar("destination", initial: 0)
            let source = SharedVar("source", initial: 7)
            destination
            source
            let copy = Macro { (target: MacroParameter<Int>, value: MacroParameter<Int>) in
                Assign(target, to: value.expr)
            }

            Do("copy") { copy(destination, source.expr + 1) }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let copy = try #require(spec.actions.first { $0.name == "copy" })
        let successor = try #require(
            ActionEnumerator.enumerate(copy.body, from: initial, varNames: spec.variables.map(\.name)).first
        )
        #expect(successor["destination"] == .int(8))
    }

    @Test("typed procedure builders use deterministic formal parameter slots")
    func buildsTypedProcedure() throws {
        let algorithm = Algorithm("ProcedureBuilder") {
            let output = SharedVar("output", initial: 0)
            output
            Procedure("work", parameters: Int.self) { value in
                let offset = LocalVar("offset", initial: 1)
                offset
                Do("enter") {
                    Assign(output, to: value.expr + offset.expr)
                    Return()
                }
            }
            Do("start") { Call("work", with: 7) }
            Do("finished") { Stop() }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let start = try #require(spec.actions.first { $0.name == "start" })
        let afterCall = try #require(
            ActionEnumerator.enumerate(
                start.body,
                from: initial,
                varNames: spec.variables.map(\.name)
            ).first
        )
        #expect(afterCall["parameter0"] == .int(7))
        #expect(afterCall["pc"] == .string("procedure.work.enter"))
    }

    @Test("procedure source bindings normalize to builder formal slots")
    func generatedProcedureKeepsParserFidelity() {
        ProcedureGeneratedModel._checkParserTree()
    }

    @Test("parameterless statement macros expand into their surrounding atomic block")
    func expandsParameterlessStatementMacro() throws {
        let algorithm = Algorithm("ParameterlessMacro") {
            let count = SharedVar("count", initial: 0)
            count
            let increment = Macro {
                Assign(count, to: count + 1)
            }

            Do("increment") { increment() }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let increment = try #require(spec.actions.first { $0.name == "increment" })
        let successor = try #require(
            ActionEnumerator.enumerate(
                increment.body,
                from: initial,
                varNames: spec.variables.map(\.name)
            ).first
        )
        #expect(successor["count"] == .int(1))
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
        let algorithm = Algorithm("ReachableGraph") {
            let successors = SharedVar("successors", in: choices)
            successors
            Do("done") { Stop() }
        }

        let spec = try algorithm.lower()
        #expect(try computeInitialStates(spec).count == 4)
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

        #expect((try? selected.raw.evaluate(in: [:])) != nil)
    }

    @Test("generated models retain typed filtered function domains")
    func generatedModelRetainsFilteredFunctionDomain() throws {
        FunctionDomainGeneratedModel._checkParserTree()
        #expect(try computeInitialStates(FunctionDomainGeneratedModel.spec).count == 4)
    }

    @Test("generated models retain static formal selections")
    func generatedModelRetainsStaticFormalSelection() {
        StaticFormalSelectionModel._checkParserTree()
        #expect(try computeInitialStates(StaticFormalSelectionModel.spec).first?["current"] == .int(2))
    }

    @Test("generated models retain static filtered function selections")
    func generatedModelRetainsStaticFilteredFunctionSelection() {
        StaticFilteredFunctionSelectionModel._checkParserTree()
        #expect(try computeInitialStates(StaticFilteredFunctionSelectionModel.spec).count == 1)
    }

    @Test("statement macros accept the current typed process identifier")
    func expandsMacroWithProcessIdentifier() throws {
        let algorithm = Algorithm("MacroProcess") {
            let marked = SharedVar(
                "marked",
                initial: Function<Node, Bool>.literal((.first, false), (.second, false))
            )
            marked
            let mark = Macro { (node: MacroParameter<Node>) in
                Assign(marked, to: marked.updating(node, to: true))
            }

            Each(Node.all) { node in
                Do("mark") { mark(node) }
                Do("done") { Stop() }
            }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let mark = try #require(spec.actions.first { $0.name == "mark" })
        let invocation = try #require(actionInvocations(mark).first {
            $0.invocation.arguments == [.string("first")]
        })
        let successor = try #require(
            ActionEnumerator.enumerate(
                invocation.body,
                from: initial,
                varNames: spec.variables.map(\.name)
            ).first
        )
        #expect(successor["marked"] == .function([.string("first"): .bool(true), .string("second"): .bool(false)]))
    }

    @Test("generated models compare macro process identifiers through both construction paths")
    func generatedMacroProcessModelKeepsParserFidelity() {
        MacroProcessGeneratedModel._checkParserTree()
    }

    @Test("process control initialization joins typed process domains")
    func initializesControlAcrossProcessDomains() throws {
        let algorithm = Algorithm("MixedProcesses") {
            Each(Node.all) { _ in
                Do("stringProcess") { Stop() }
            }
            Each(OtherNode.all) { _ in
                Do("otherProcess") { Stop() }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        #expect(initial["pc"] == .function([
            .string("first"): .string("stringProcess"),
            .string("second"): .string("stringProcess"),
            .string("other"): .string("otherProcess")
        ]))
        #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("({\"first\", \"second\"} \\cup {\"other\"})"))
        #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("__pcal_initial_process =") == false)
    }

    @Test("a begin-style algorithm keeps a scalar program counter")
    func lowersSequentialAlgorithmWithoutInventingAProcess() throws {
        let algorithm = Algorithm("SequentialCounter") {
            let value = SharedVar("value", initial: 0)
            value
            Do("increment") {
                Let(value + 1) { nextValue in
                    Assign(value, to: nextValue.expr)
                }
            }
            Do("finish") {
                Stop()
            }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        #expect(spec.variables.map(\.name) == ["value", "pc"])
        #expect(spec.actions.map(\.name) == ["increment", "finish", "Terminating"])
        #expect(spec.actions.allSatisfy { $0.bindings.isEmpty })

        let initial = try #require(computeInitialStates(spec).first)
        #expect(initial["pc"] == .string("increment"))
        let increment = try #require(spec.actions.first { $0.name == "increment" })
        let successor = try #require(
            ActionEnumerator.enumerate(increment.body, from: initial, varNames: spec.variables.map(\.name)).first
        )
        #expect(successor["value"] == .int(1))
        #expect(successor["pc"] == .string("finish"))
    }

    @Test("typed first-slice builders preserve ordered process steps")
    func buildsBoundedAlgorithm() throws {
        let algorithm = Algorithm("ChangRoberts") {
            let maximum = SharedVar("maximum", initial: 0)
            maximum
            Each(Node.all) { node in
                let inbox = LocalVar("inbox", initial: 0)
                inbox
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
        let algorithm = Algorithm("Properties") {
            let value = SharedVar("value", initial: 0)
            value
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
        let spec = try algorithm.lower()
        #expect(spec.invariants.map(\.name) == ["NonNegative"])
        #expect(spec.temporalProperties.map(\.name) == ["EventuallyPositive"])
        #expect(spec.fairness.contains(.weakFairness("receive")))
        #expect(spec.constraint == .lessThan(.variable("value"), .value(.int(3))))
    }

    @Test("a process-local invariant lowers over its process family")
    func lowersProcessLocalInvariant() throws {
        let algorithm = Algorithm("LocalProperty") {
            Each(Node.all) { selfID in
                let count = LocalVar("count", initial: 0)
                // Direct builders register declarations as expressions. `#spec`
                // supplies this registration automatically for source `let`s.
                count
                Do(AlgorithmLabel.receive) { Skip() }
                Invariant("LocalCount") { count == 0 }
                Invariant("ControlLocation") {
                    At(AlgorithmLabel.receive, selfID) || Finished(selfID)
                }
            }
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
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
            .equal(.functionApply(.variable("pc"), .variable("process")), .value(.string("receive"))),
            .equal(.functionApply(.variable("pc"), .variable("process")), .value(.string("Done")))
        ))
    }

    @Test("validation fails closed for invalid bounded algorithms")
    func rejectsInvalidAlgorithms() {
        let invalid = Algorithm("__pcal_invalid") {
            let value = SharedVar("value", initial: 0)
            value
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
        let algorithm = Algorithm("BoundedCounter") {
            let value = SharedVar("value", initial: 0)
            value
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

        let spec = try algorithm.lower()

        #expect(spec.variables.map(\.name) == ["value", "pc"])
        #expect(spec.actions.map(\.name) == ["receive", "done", "Terminating"])
        for action in spec.actions where action.name != "Terminating" {
            #expect(action.bindings == [ActionBinding(name: "process", values: Node.formalDomain.map(\.tlaValue))])
        }

        let initial = try #require(computeInitialStates(spec).first)
        #expect(initial["pc"] == .function([
            .string("first"): .string("receive"),
            .string("second"): .string("receive")
        ]))
    }

    @Test("an unconditional single-loop process does not invent a program counter")
    func elidesRedundantProgramCounter() throws {
        let algorithm = Algorithm("SingleLoop") {
            let value = SharedVar("value", initial: 0)
            value
            Each(Node.all) { _ in
                While("advance", true) {
                    Assign(value, to: value + 1)
                }
            }
        }

        let spec = try algorithm.lower()
        #expect(spec.variables.map(\.name) == ["value"])
        #expect(spec.actions.map(\.name) == ["advance"])
        #expect(spec.tlaModule.contains("pc") == false)

        let initial = try #require(computeInitialStates(spec).first)
        let advance = try #require(spec.actions.first)
        let successor = try #require(
            ActionEnumerator.enumerate(
                advance.body,
                from: initial,
                varNames: spec.variables.map(\.name)
            ).first
        )
        #expect(successor["value"] == .int(1))
    }

    @Test("lowered atomic actions advance pc and stop before the explicit terminating self loop")
    func lowersAtomicSemantics() throws {
        let algorithm = Algorithm("BoundedCounter") {
            let value = SharedVar("value", initial: 0)
            value
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

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let receive = try #require(spec.actions.first { $0.name == "receive" })
        let firstReceive = try #require(actionInvocations(receive).first { $0.invocation.arguments == [.string("first")] })
        let advanced = try #require(
            ActionEnumerator.enumerate(firstReceive.body, from: initial, varNames: spec.variables.map(\.name)).first)

        #expect(advanced["value"] == .int(1))
        #expect(advanced["pc"] == .function([
            .string("first"): .string("done"),
            .string("second"): .string("receive")
        ]))

        let done = try #require(spec.actions.first { $0.name == "done" })
        let firstDone = try #require(actionInvocations(done).first { $0.invocation.arguments == [.string("first")] })
        let stopped = try #require(
            ActionEnumerator.enumerate(firstDone.body, from: advanced, varNames: spec.variables.map(\.name)).first)
        #expect(stopped["pc"] == .function([
            .string("first"): .string("Done"),
            .string("second"): .string("receive")
        ]))

        let secondReceive = try #require(actionInvocations(receive).first { $0.invocation.arguments == [.string("second")] })
        let secondAdvanced = try #require(
            ActionEnumerator.enumerate(secondReceive.body, from: stopped, varNames: spec.variables.map(\.name)).first)
        let secondDone = try #require(actionInvocations(done).first { $0.invocation.arguments == [.string("second")] })
        let allDone = try #require(
            ActionEnumerator.enumerate(secondDone.body, from: secondAdvanced, varNames: spec.variables.map(\.name)).first)
        let terminating = try #require(spec.actions.first { $0.name == "Terminating" })
        let terminal = try #require(
            ActionEnumerator.enumerate(terminating.body, from: allDone, varNames: spec.variables.map(\.name)).first)
        #expect(terminal == allDone)
    }

    @Test("lowering represents process-local state as a function of self")
    func lowersLocalState() throws {
        let algorithm = Algorithm("LocalCounter") {
            Each(Node.all) { _ in
                let inbox = LocalVar("inbox", initial: 0)
                inbox
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

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        #expect(initial["inbox"] == .function([
            .string("first"): .int(0),
            .string("second"): .int(0)
        ]))

        let receive = try #require(spec.actions.first { $0.name == "receive" })
        let firstReceive = try #require(actionInvocations(receive).first { $0.invocation.arguments == [.string("first")] })
        let advanced = try #require(
            ActionEnumerator.enumerate(firstReceive.body, from: initial, varNames: spec.variables.map(\.name)).first)
        #expect(advanced["inbox"] == .function([
            .string("first"): .int(1),
            .string("second"): .int(0)
        ]))
    }

    @Test("local state can be initialized from its process identifier")
    func lowersProcessDependentLocalState() throws {
        let algorithm = Algorithm("ProcessDependentInitialState") {
            Each(Node.all) { selfID in
                let leader = LocalVar("leader", initial: selfID == .first)
                leader
                Do(AlgorithmLabel.done) { Stop() }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        #expect(initial["leader"] == .function([
            .string("first"): .bool(true),
            .string("second"): .bool(false)
        ]))
    }

    @Test("string labels are contained by ProgramLabel and validated before lowering")
    func validatesStringLabels() throws {
        let algorithm = Algorithm("StringLabels") {
            let value = SharedVar("value", initial: 0)
            value
            Each(Node.all) { _ in
                Do("move") {
                    Assign(value, to: value + 1)
                    Goto("done")
                }
                Do("done") { Stop() }
            }
        }

        #expect(algorithm.validate().isEmpty)
        #expect(try algorithm.lower().actions.map(\.name).contains("move"))

        let invalid = Algorithm("InvalidStringLabel") {
            Each(Node.all) { _ in
                Do("bad label") { Stop() }
            }
        }
        #expect(invalid.validate().contains { $0.code == .invalidName })
    }

    @Test("the end of an Each machine reaches its builder-owned Done state")
    func eachMachineEndsInDone() throws {
        let algorithm = Algorithm("ImplicitStop") {
            let value = SharedVar("value", initial: 0)
            value
            Each(Node.all) { _ in
                Do("finish") {
                    Assign(value, to: value + 1)
                }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let finish = try #require(spec.actions.first { $0.name == "finish" })
        let invocation = try #require(actionInvocations(finish).first { $0.invocation.arguments == [.string("first")] })
        let terminal = try #require(
            ActionEnumerator.enumerate(invocation.body, from: initial, varNames: spec.variables.map(\.name)).first)
        #expect(terminal["pc"] == .function([
            .string("first"): .string("Done"),
            .string("second"): .string("finish")
        ]))
    }

    @Test("an unlabeled transfer falls through to the next Do block")
    func intermediateDoFallsThrough() throws {
        let algorithm = Algorithm("Fallthrough") {
            let value = SharedVar("value", initial: 0)
            value
            Each(Node.all) { _ in
                Do("prepare") {
                    Assign(value, to: value + 1)
                }
                Do("finish") {
                    Assign(value, to: value + 1)
                }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let prepare = try #require(spec.actions.first { $0.name == "prepare" })
        let invocation = try #require(actionInvocations(prepare).first { $0.invocation.arguments == [.string("first")] })
        let advanced = try #require(
            ActionEnumerator.enumerate(invocation.body, from: initial, varNames: spec.variables.map(\.name)).first)
        #expect(advanced["pc"] == .function([
            .string("first"): .string("finish"),
            .string("second"): .string("prepare")
        ]))
    }

    @Test("TLASpec accepts an algorithm component and lowers it before checking")
    func algorithmComposesIntoTLASpec() throws {
        let value = SharedVar("value", initial: 0)
        let algorithm = Algorithm("Composed") {
            value
            Each(Node.all) { _ in
                Do("finish") { Assign(value, to: value + 1) }
            }
        }

        let spec = TLASpec("Composed") {
            algorithm
            Invariant("nonNegative") { value >= 0 }
        }
        #expect(spec.variables.map(\.name) == ["value", "pc"])
        #expect(spec.actions.map(\.name) == ["finish", "Terminating"])
        #expect(spec.invariants.map(\.name) == ["nonNegative"])
    }

    @Test("algorithm formal definitions lower and export exactly once")
    func algorithmFormalDefinitionsRemainTopLevelFormalOperators() throws {
        let algorithm = Algorithm("Formal Operators") {
            FormalDefinition("same", taking: Int.self, Int.self) { left, right in
                left == right
            }
            let value = SharedVar("value", initial: 0)
            value
            Do("stop") { Stop() }
        }

        let lowered = try algorithm.lower()
        #expect(lowered.formalOperatorDefinitions == [
            FormalOperatorDefinition(
                name: "same",
                parameters: [.value("value0"), .value("value1")],
                body: .equal(.variable("value0"), .variable("value1"))
            )
        ])
        #expect(lowered.definitions == ["same(value0, value1) == (value0 = value1)"])
        #expect(try algorithm.renderPlusCalModule().contains("same(value0, value1) == (value0 = value1)"))

        let spec = TLASpec("Formal Operators") { algorithm }
        #expect(spec.formalOperatorDefinitions == lowered.formalOperatorDefinitions)
        #expect(spec.definitions.filter { $0.hasPrefix("same(") }.count == 1)
        #expect(try spec.compile().renderedTLAModuleBundle().tla.components(separatedBy: "same(value0, value1)").count == 2)
    }

    @Test("When, Assert, With, and process fairness lower as formal semantics")
    func lowersMechanicalPlusCalStatements() throws {
        let algorithm = Algorithm("Mechanical") {
            let count = SharedVar("count", initial: 0)
            let selected = SharedVar("selected", initial: 0)
            count
            selected
            Each(Node.all, fairness: .weak) { node in
                Do("choose") {
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
        let spec = try algorithm.lower()
        #expect(spec.invariants.map(\.name) == ["__pcal_assert_choose_0_0", "__pcal_assert_choose_0_1"])
        #expect(spec.fairness == [FairnessCondition.weakFairnessInvocation(.init(name: "choose", arguments: [.string("first")])),
            .weakFairnessInvocation(.init(name: "choose", arguments: [.string("second")]))
        ])
        let rendered = try spec.compile().renderedTLAModuleBundle().tla
        #expect(rendered.contains("WF_<<count, selected, pc>>(choose__0)"))
        #expect(rendered.contains("WF_<<count, selected, pc>>(choose__1)"))

        let initial = try #require(computeInitialStates(spec).first)
        let choose = try #require(spec.actions.first { $0.name == "choose" })
        let first = try #require(actionInvocations(choose).first { $0.invocation.arguments == [.string("first")] })
        let states = try ActionEnumerator.enumerate(first.body, from: initial, varNames: spec.variables.map(\.name))
        #expect(states.count == 2)
        #expect(Set(states.compactMap { $0["selected"] }) == Set([.int(1), .int(2)]))
    }

    @Test("a false While condition advances control and a true condition loops")
    func lowersWhileAsFormalControl() throws {
        let algorithm = Algorithm("Loop") {
            let count = SharedVar("count", initial: 0)
            count
            Each(Node.all) { _ in
                While("repeat", count < 2) {
                    Assign(count, to: count + 1)
                }
                Do("finish") { Stop() }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let repeatAction = try #require(spec.actions.first { $0.name == "repeat" })
        let first = try #require(actionInvocations(repeatAction).first { $0.invocation.arguments == [.string("first")] })
        let looped = try #require(ActionEnumerator.enumerate(first.body, from: initial, varNames: spec.variables.map(\.name)).first)
        #expect(looped["count"] == .int(1))
        #expect(looped["pc"] == .function([
            .string("first"): .string("repeat"),
            .string("second"): .string("repeat")
        ]))

        let atLimit = looped.merging(["count": .int(2)]) { _, replacement in replacement }
        let exited = try #require(ActionEnumerator.enumerate(first.body, from: atLimit, varNames: spec.variables.map(\.name)).first)
        #expect(exited["pc"] == .function([
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
                .assign("result", .variable("middle"))
            )
        )

        let successors = try ActionEnumerator.enumerate(
            action,
            from: ["sequence": .tuple([]), "result": .int(0)],
            varNames: ["sequence", "result"]
        )
        #expect(successors.isEmpty)
    }

    @Test("Assert is required only on the branch that reaches it")
    func scopesAssertToItsConditionalBranch() throws {
        let algorithm = Algorithm("ConditionalAssert") {
            let count = SharedVar("count", initial: 0)
            count
            Each(Node.all) { _ in
                Do("check") {
                    If(count == 0) {
                        Assert(count == 0)
                    } else: {
                        Assert(count == 1)
                    }
                }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        #expect(try spec.invariants.allSatisfy { try $0.body.evaluateBool(in: initial) })
        let alternate = initial.merging(["count": .int(1)]) { _, replacement in replacement }
        #expect(try spec.invariants.allSatisfy { try $0.body.evaluateBool(in: alternate) })
    }

    @Test("Assert becomes a model-checker safety obligation")
    func checksAssertAsAnInvariant() throws {
        let algorithm = Algorithm("BrokenAssertion") {
            let count = SharedVar("count", initial: 0)
            count
            Each(Node.all) { _ in
                Do("check") {
                    Assert(count == 1)
                    Stop()
                }
            }
        }

        let result = try ModelChecker(spec: algorithm.lower()).check().underlyingOutcome
        guard case .invariantViolated(let name, _, _) = result else {
            Issue.record("Expected Assert to produce an invariant violation, got \(result)")
            return
        }
        #expect(name == "__pcal_assert_check_0_0")
    }

    @Test("SharedVar range expands to the declared finite initial states")
    func lowersNondeterministicSharedInitialization() throws {
        let algorithm = Algorithm("HourClock") {
            let hour = SharedVar("hour", in: 1...3)
            hour
            Each(Node.all) { _ in
                Do("tick") {
                    When(hour < 3)
                    Assign(hour, to: hour + 1)
                    Stop()
                }
            }
        }

        let spec = try algorithm.lower()
        let states = try computeInitialStates(spec)

        #expect(Set(states.compactMap { $0["hour"] }) == [.int(1), .int(2), .int(3)])
        #expect(spec.variables.first { $0.name == "hour" }?.initialSet == .setLiteral([
            .value(.int(1)), .value(.int(2)), .value(.int(3))
        ]))
    }

    @Test("SharedVar initial domains can depend on earlier formal state")
    func lowersDependentNondeterministicSharedInitialization() throws {
        let algorithm = Algorithm("DependentInitialDomain") {
            let maximum = SharedVar("maximum", initial: 2)
            maximum
            let candidate = SharedVar(
                "candidate",
                in: Expr<SetExpr<Int>>(.integerRange(.int(0), maximum.stateExpr))
            )
            candidate
            Do("stop") { Stop() }
        }

        let spec = try algorithm.lower()
        #expect(Set(try computeInitialStates(spec).compactMap { $0["candidate"] }) == [
            .int(0), .int(1), .int(2)
        ])
    }

    @Test("nested With statements keep independent lexical bindings")
    func lowersNestedWithScopes() throws {
        let algorithm = Algorithm("NestedWith") {
            let selected = SharedVar("selected", initial: 0)
            selected
            Each(Node.all) { _ in
                Do("choose") {
                    With(SetExpr<Int>.literal(1, 2), SetExpr<Int>.literal(10, 20)) { outer, inner in
                        Assign(selected, to: outer.expr + inner.expr)
                    }
                }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let action = try #require(spec.actions.first { $0.name == "choose" })
        let successors = try actionInvocations(action).flatMap {
            try ActionEnumerator.enumerate($0.body, from: initial, varNames: spec.variables.map(\.name))
        }

        #expect(Set(successors.compactMap { $0["selected"] }) == [.int(11), .int(12), .int(21), .int(22)])
    }

    @Test("With preserves ordered three-source bindings")
    func lowersThreeIndependentWithScopes() throws {
        let algorithm = Algorithm("ThreeWith") {
            let selected = SharedVar("selected", initial: 0)
            selected
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

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let action = try #require(spec.actions.first { $0.name == "choose" })
        let successors = try ActionEnumerator.enumerate(
            action.body,
            from: initial,
            varNames: spec.variables.map(\.name)
        )

        #expect(Set(successors.compactMap { $0["selected"] }) == [.int(111), .int(112), .int(211), .int(212)])
    }

    @Test("tuple patterns bind independently typed members")
    func lowersPairPatternBindings() throws {
        let algorithm = Algorithm("PairPattern") {
            let selected = SharedVar("selected", initial: 0)
            selected
            Do("choose") {
                With(SetExpr<Pair<Int, Bool>>.literal(
                    Pair(first: 1, second: true),
                    Pair(first: 2, second: false)
                )) { number, flag in
                    Assert((number.expr == 1) || !flag.expr)
                    Assign(selected, to: number.expr)
                }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let action = try #require(spec.actions.first { $0.name == "choose" })
        let successors = try ActionEnumerator.enumerate(
            action.body,
            from: initial,
            varNames: spec.variables.map(\.name)
        )

        #expect(Set(successors.compactMap { $0["selected"] }) == [.int(1), .int(2)])
    }

    @Test("Choose accepts a bounded Swift integer range")
    func lowersBoundedIntegerChoice() throws {
        let algorithm = Algorithm("BoundedChoice") {
            let selected = SharedVar("selected", initial: 0)
            selected
            Each(Node.all) { _ in
                Do("choose") {
                    Choose(1...3) { choice in
                        Assign(selected, to: choice.expr)
                    }
                }
            }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)
        let action = try #require(spec.actions.first { $0.name == "choose" })
        let successors = try actionInvocations(action).flatMap {
            try ActionEnumerator.enumerate($0.body, from: initial, varNames: spec.variables.map(\.name))
        }
        #expect(Set(successors.compactMap { $0["selected"] }) == [.int(1), .int(2), .int(3)])
    }

    @Test("dependent typed function initialization is evaluated after earlier initial state choices")
    func lowersDependentFunctionInitialization() throws {
        let algorithm = Algorithm("DependentInitial") {
            let seed = SharedVar("seed", in: SetExpr<Bool>.literal(false, true))
            seed
            let mirrors = SharedVar("mirrors", initial: Function<Node, Bool>.mapping { _ in seed.expr })
            mirrors
            Each(Node.all) { _ in
                Do("stop") { Stop() }
            }
        }

        let spec = try algorithm.lower()
        let states = try computeInitialStates(spec)

        #expect(Set(states.compactMap { $0["seed"] }) == [.bool(false), .bool(true)])
        #expect(Set(states.compactMap { $0["mirrors"] }) == [
            .function([.string("first"): .bool(false), .string("second"): .bool(false)]),
            .function([.string("first"): .bool(true), .string("second"): .bool(true)])
        ])
    }
}

private enum Node: String, FiniteDomainKey, PlusCalLabel {
    case first
    case second

    static let formalDomain: [Node] = [.first, .second]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.node")

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum EmptyNode: String, FiniteDomainKey {
    case none

    static let formalDomain: [EmptyNode] = []
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.empty-node")

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum OtherNode: String, FiniteDomainKey {
    case one = "other"

    static let formalDomain: [OtherNode] = [.one]
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.other-node")

    var tlaValue: TLAValue { .string(rawValue) }
}

private enum AlgorithmLabel: String, PlusCalLabel {
    case receive
    case forward
    case done
}

@TLAModel
private struct ProcedureGeneratedModel {
    static var spec: TLASpec {
        #spec("ProcedureGenerated") {
            Algorithm("ProcedureGenerated") {
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
    }
}

@TLAModel
private struct MacroProcessGeneratedModel {
    enum Node: String, CaseIterable, FiniteDomainKey {
        case first
        case second

        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.macro-process-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("MacroProcessGenerated") {
            Algorithm("MacroProcessGenerated") {
                let marked = SharedVar(initial: Function<Node, Bool>.literal((.first, false), (.second, false)))
                let mark = Macro { (node: MacroParameter<Node>) in
                    Assign(marked, to: marked.updating(node, to: true))
                }

                Each(Node.all) { node in
                    Do("mark") { mark(node) }
                    Do("done") { Stop() }
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

        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.function-domain-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("FunctionDomainGenerated") {
            Algorithm("FunctionDomainGenerated") {
                let successors = SharedVar(in: Where(
                    Functions(from: Node.all, to: Subsets(of: SetExpr<Node>.literal(.first, .second)))
                ) { successor in
                    All(Node.all) { node in
                        successor[node].cardinality == 1
                    }
                })

                Do("done") { Stop() }
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
            Algorithm("StaticFormalSelection") {
                let selected = Select(
                    from: SetExpr<Int>.literal(1, 2, 3),
                    matching: { value in value.expr % 2 == 0 }
                )
                let current = SharedVar(initial: selected)

                Do("done") { Stop() }
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

        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal.static-function-selection-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("StaticFilteredFunctionSelection") {
            Algorithm("StaticFilteredFunctionSelection") {
                let successors = Select(
                    from: Where(Functions(
                        from: Node.all,
                        to: Subsets(of: SetExpr<Node>.literal(.first, .second, .third, .fourth))
                    )) { successor in
                        All(Node.all) { node in successor[node].cardinality == 2 }
                    },
                    matching: { successor in successor.expr == successor.expr }
                )
                let current = SharedVar(initial: successors)

                Do("done") { Stop() }
                Invariant("CurrentIsDefined") { current == current.expr }
            }
        }
    }
}
