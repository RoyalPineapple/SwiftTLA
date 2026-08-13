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
            Process(Node.all) { node in
                Local(inbox, initial: 0)
                Atomic(Label.receive) {
                    Await(inbox > 0)
                    Choose(Node.all) { candidate in
                        If(candidate > node) {
                            Assign(maximum, to: candidate)
                            Goto(Label.forward)
                        } else: {
                            Goto(Label.receive)
                        }
                    }
                }
                Atomic(Label.forward) {
                    Either {
                        Assign(maximum, to: maximum + 1)
                        Goto(Label.receive)
                    } or: {
                        Goto(Label.done)
                    }
                }
                Atomic(Label.done) {
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
            Process(EmptyNode.all) { _ in
                Atomic(Label.receive) {
                    Assign(value, to: 1)
                    Assign(value, to: 2)
                    Goto(Label.forward)
                }
                Atomic(Label.receive) {
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

private enum Label: String, PlusCalLabel {
    case receive
    case forward
    case done
}
