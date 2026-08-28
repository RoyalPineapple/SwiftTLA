import SwiftTLA
import SwiftTLAMacros

/// Chang–Roberts leader election, translated from the upstream PlusCal model.
///
/// The three nodes own a generated program counter. `initiator` is the only
/// nondeterministic initial value; `processState` is derived from it in the
/// formal initial state. Every message is explicitly delivered clockwise.
package struct ChangRobertsModel: Sendable {
    package enum Node: Int, FiniteTLAValueDomain {
        case one = 1
        case two = 2
        case three = 3

        package static var defaultValue: Self { .one }
        package static let finiteValues: [Self] = [.one, .two, .three]

        package var tlaValue: TLAValue { .int(rawValue) }
    }

    package enum ProcessState: String, TLAValueType {
        case candidate = "cand"
        case lost
        case won

        package static var defaultValue: Self { .candidate }
    }

    private enum Step: String, CaseIterable {
        case n0
        case n1
    }

    package static var spec: TLASpec {
        #spec("ChangRoberts") {
            Algorithm("ChangRoberts", scoped: { scope in
                let initiator = scope.sharedVar("initiator", in: SetExpr<Function<Node, Bool>>.literal(
                    Function<Node, Bool>.literal((.one, false), (.two, false), (.three, false)),
                    Function<Node, Bool>.literal((.one, false), (.two, false), (.three, true)),
                    Function<Node, Bool>.literal((.one, false), (.two, true), (.three, false)),
                    Function<Node, Bool>.literal((.one, false), (.two, true), (.three, true)),
                    Function<Node, Bool>.literal((.one, true), (.two, false), (.three, false)),
                    Function<Node, Bool>.literal((.one, true), (.two, false), (.three, true)),
                    Function<Node, Bool>.literal((.one, true), (.two, true), (.three, false)),
                    Function<Node, Bool>.literal((.one, true), (.two, true), (.three, true))
                ))
                let processState = scope.sharedVar("processState", initial: Function<Node, ProcessState>.mapping { node in
                    If(
                        initiator[node] == true,
                        then: .candidate,
                        else: .lost
                    )
                })
                let successor = scope.sharedVar("successor", initial: Function<Node, Node>.literal(
                    (.one, .two), (.two, .three), (.three, .one)
                ))
                let messages = scope.sharedVar("messages", initial: Function<Node, SetExpr<Node>>.literal(
                    (.one, SetExpr<Node>()),
                    (.two, SetExpr<Node>()),
                    (.three, SetExpr<Node>())
                ))

                Each(Node.all, fairness: .weak) { node in
                    Do(Step.n0) {
                        Either {
                            When(initiator[node] == true)
                            Assign(messages, to: messages.updating(
                                successor[node],
                                to: messages[successor[node]].inserting(node)
                            ))
                        } or: {
                            When(initiator[node] == false)
                        }
                    }

                    Do(Step.n1) {
                        With(messages[node]) { candidate in
                            Either {
                                When(processState[node] == .lost)
                                Assign(messages, to: messages
                                    .updating(node, to: messages[node].removing(candidate))
                                    .updating(
                                        successor[node],
                                        to: messages[successor[node]].inserting(candidate)
                                    ))
                            } or: {
                                Either {
                                    When(
                                        processState[node] == .candidate
                                            && candidate < node
                                    )
                                    Assign(messages, to: messages
                                        .updating(node, to: messages[node].removing(candidate))
                                        .updating(
                                            successor[node],
                                            to: messages[successor[node]].inserting(candidate)
                                        ))
                                    Assign(processState, to: processState.updating(node, to: .lost))
                                } or: {
                                    Either {
                                    When(
                                        processState[node] == .candidate
                                            && candidate > node
                                    )
                                    Assign(messages, to: messages.updating(
                                        node,
                                        to: messages[node].removing(candidate)
                                    ))
                                    } or: {
                                        When(
                                            processState[node] == .candidate
                                                && candidate == node
                                        )
                                        Assign(messages, to: messages.updating(
                                            node,
                                            to: messages[node].removing(candidate)
                                        ))
                                        Assign(processState, to: processState.updating(node, to: .won))
                                    }
                                }
                            }
                        }
                        Goto(Step.n1)
                    }
                }

                Invariant("NoFalseWinner") {
                    processState[.one] != .won || initiator[.one] == true
                    processState[.two] != .won || initiator[.two] == true
                    processState[.three] != .won || initiator[.three] == true
                }
                LeadsTo(
                    "Liveness",
                    processState[.one] == .candidate
                        || processState[.two] == .candidate
                        || processState[.three] == .candidate,
                    processState[.one] == .won
                        || processState[.two] == .won
                        || processState[.three] == .won
                )
            })
        }
    }
}

extension Example {
    package static let changRobertsN3 = FiniteModelFixture(
        expectedDistinct: 137,
        maximumStateLimit: 50_000,
        spec: ChangRobertsModel.spec,
    )
}
