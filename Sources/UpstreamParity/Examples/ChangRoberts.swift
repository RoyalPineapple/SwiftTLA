import SwiftTLA
import SwiftTLAMacros

/// Chang–Roberts leader election, translated from the upstream PlusCal model.
///
/// The three nodes own a generated program counter. `initiator` is the only
/// nondeterministic initial value; `processState` is derived from it in the
/// formal initial state. Every message is explicitly delivered clockwise.
@TLAModel
public struct ChangRobertsModel {
    public enum Node: Int, FiniteDomainKey {
        case one = 1
        case two = 2
        case three = 3

        public static let formalDomain: [Self] = [.one, .two, .three]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.chang-roberts.node")

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    public enum ProcessState: String, TLAValueType {
        case candidate = "cand"
        case lost
        case won
    }

    private enum Step: String, PlusCalLabel {
        case n0
        case n1
    }

    public static var spec: TLASpec {
        #spec("ChangRoberts") {
            Algorithm("ChangRoberts") {
                let initiator = SharedVar(in: SetExpr<Function<Node, Bool>>.literal(
                    Function<Node, Bool>.literal((.one, false), (.two, false), (.three, false)),
                    Function<Node, Bool>.literal((.one, false), (.two, false), (.three, true)),
                    Function<Node, Bool>.literal((.one, false), (.two, true), (.three, false)),
                    Function<Node, Bool>.literal((.one, false), (.two, true), (.three, true)),
                    Function<Node, Bool>.literal((.one, true), (.two, false), (.three, false)),
                    Function<Node, Bool>.literal((.one, true), (.two, false), (.three, true)),
                    Function<Node, Bool>.literal((.one, true), (.two, true), (.three, false)),
                    Function<Node, Bool>.literal((.one, true), (.two, true), (.three, true))
                ))
                let processState = SharedVar(initial: Function<Node, ProcessState>.mapping { node in
                    Expr<ProcessState>.ifThenElse(
                        initiator[node] == true,
                        then: .candidate,
                        else: .lost
                    )
                })
                let successor = SharedVar(initial: Function<Node, Node>.literal(
                    (.one, .two), (.two, .three), (.three, .one)
                ))
                let messages = SharedVar(initial: Function<Node, SetExpr<Node>>.literal(
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
            }
        }
    }
}

extension Example {
    public static let changRobertsN3 = Entry(
        id: "ChangRoberts/ChangRoberts_N3",
        upstreamSpec: "chang_roberts",
        upstreamModule: "specifications/chang_roberts/ChangRoberts.tla",
        upstreamCfg: "specifications/chang_roberts/MCChangRoberts.cfg",
        expectedDistinct: 137,
        spec: ChangRobertsModel.spec,
        notes: "N=3, Id=i. 137 states matching upstream. Generated PlusCal-shaped processes.",
    )
}
