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
        #expect(spec.tlaModule.contains("({\"first\", \"second\"} \\cup {\"other\"})"))
        #expect(spec.tlaModule.contains("__pcal_initial_process =") == false)
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
        }

        #expect(algorithm.validate().isEmpty)
        let spec = try algorithm.lower()
        #expect(spec.invariants.map(\.name) == ["NonNegative"])
        #expect(spec.temporalProperties.map(\.name) == ["EventuallyPositive"])
        #expect(spec.fairness.contains(.weakFairness("receive")))
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
        let rendered = spec.tlaModule
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
        let states = computeInitialStates(spec)

        #expect(Set(states.compactMap { $0["hour"] }) == [.int(1), .int(2), .int(3)])
        #expect(spec.variables.first { $0.name == "hour" }?.initialSet == .setLiteral([
            .value(.int(1)), .value(.int(2)), .value(.int(3))
        ]))
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
        let states = computeInitialStates(spec)

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
