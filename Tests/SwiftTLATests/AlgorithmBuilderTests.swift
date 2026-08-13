import Testing
@testable import SwiftTLA

@Suite("PlusCal algorithm builders")
struct AlgorithmBuilderTests {
    @Test("typed first-slice builders preserve ordered process steps")
    func buildsBoundedAlgorithm() throws {
        let maximum = Var<Int>("maximum", 0)
        let inbox = Var<Int>("inbox", 0)

        let algorithm = Algorithm("ChangRoberts") {
            Shared(maximum, initial: 0)
            Each(Node.all) { node in
                Local(inbox, initial: 0)
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

    @Test("validation fails closed for invalid bounded algorithms")
    func rejectsInvalidAlgorithms() {
        let value = Var<Int>("value", 0)
        let invalid = Algorithm("__pcal_invalid") {
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
        #expect(codes.contains(.propertyBoundary))
        #expect(throws: AlgorithmValidationError.self) {
            try invalid.requireValid()
        }
    }

    @Test("lowering initializes pc and binds every atomic action to a process")
    func lowersControlStateAndActionBindings() throws {
        let value = Var<Int>("value", 0)
        let algorithm = Algorithm("BoundedCounter") {
            Shared(value, initial: 0)
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
        let value = Var<Int>("value", 0)
        let algorithm = Algorithm("BoundedCounter") {
            Shared(value, initial: 0)
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
        let inbox = Var<Int>("inbox", 0)
        let algorithm = Algorithm("LocalCounter") {
            Each(Node.all) { _ in
                Local(inbox, initial: 0)
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
        let value = Var<Int>("value", 0)
        let algorithm = Algorithm("StringLabels") {
            Shared(value, initial: 0)
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
        let value = Var<Int>("value", 0)
        let algorithm = Algorithm("ImplicitStop") {
            Shared(value, initial: 0)
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
        let value = Var<Int>("value", 0)
        let algorithm = Algorithm("Fallthrough") {
            Shared(value, initial: 0)
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
        let value = Var<Int>("value", 0)
        let algorithm = Algorithm("Composed") {
            Shared(value, initial: 0)
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

private enum AlgorithmLabel: String, PlusCalLabel {
    case receive
    case forward
    case done
}
