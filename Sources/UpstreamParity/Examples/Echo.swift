import SwiftTLA
import SwiftTLAMacros

/// The bounded three-node Echo spanning-tree algorithm from the upstream
/// TLA+ Examples repository.
///
/// A record is the message on the network. The `inbox` finite function gives
/// every node its own set of messages, while each `Each(Node.all)` body is an
/// independently scheduled PlusCal process.
@TLAModel
package struct EchoModel: Sendable {
    package enum Node: String, CaseIterable {
        case a, b, c
    }

    package enum MessageKind: String, CaseIterable {
        case message = "m"
        case acknowledgement = "c"
    }

    package struct Message: Hashable, Sendable {
        package let kind: MessageKind
        package let sender: Node
    }

    private enum Step: String, CaseIterable {
        case n0, n1, n2
    }

    package static var spec: TLASpec {
        #spec("Echo") {
            Extends(.finiteSets)
            Algorithm("Echo", scoped: { (scope: AlgorithmScope) in
                let inbox: SharedVariable<[Node: Set<Message>]> = scope.sharedVar(initial: [
                    .a: Set<Message>(), .b: Set<Message>(), .c: Set<Message>()
                ])

                Each(Node.all, scoped: { (selfID: ProcessIdentifier<Node>, scope: ProcessScope) in
                    // This bounded port uses a concrete parent default; upstream uses NoNode.
                    let parent: LocalVariable<Node> = scope.localVar(initial: .a)
                    let children: LocalVariable<Set<Node>> = scope.localVar(initial: Set<Node>())
                    let received: LocalVariable<Int> = scope.localVar(initial: 0)

                    Do(Step.n0) {
                        If(selfID == .a) {
                            Assign(inbox, to: Dictionary<Node, Set<Message>>.mapping(over: Node.all) { (destination: WithValue<Node>) -> Expr<Set<Message>> in
                                If(Node.all.removing(selfID).contains(destination),
                                   then: inbox[destination].inserting(Message.expression(kind: MessageKind.message, sender: selfID)),
                                   else: inbox[destination])
                            })
                        }
                    }

                    While(Step.n1, received.expr < Node.all.removing(selfID).cardinality) {
                        With(inbox[selfID]) { (message: WithValue<Message>) in
                            Let(inbox.updating(selfID, to: inbox[selfID].removing(message))) { (networkAfterReceive: WithValue<[Node: Set<Message>]>) in
                                If(selfID != .a && received.expr == 0) {
                                    Assert(message.kind == .message)
                                    Assign(parent, to: message.sender)
                                    Assign(inbox, to: Dictionary<Node, Set<Message>>.mapping(over: Node.all) { (destination: WithValue<Node>) -> Expr<Set<Message>> in
                                        If(Node.all.removing(selfID).removing(message.sender).contains(destination),
                                           then: networkAfterReceive[destination].inserting(Message.expression(kind: MessageKind.message, sender: selfID)),
                                           else: networkAfterReceive[destination])
                                    })
                                } else: {
                                    Assign(inbox, to: networkAfterReceive.expr)
                                }
                                Assign(received, to: received.expr + 1)
                                If(message.kind == .acknowledgement) {
                                    Assign(children, to: children.expr.inserting(message.sender))
                                }
                            }
                        }
                    }

                    Do(Step.n2) {
                        If(selfID != .a) {
                            Assert(Node.all.removing(selfID).contains(parent.expr))
                            Assign(inbox, to: inbox.updating(parent, to: inbox[parent].inserting(
                                Message.expression(kind: MessageKind.acknowledgement, sender: selfID)
                            )))
                        }
                    }
                })
            })
        }
    }
}

extension Example {
    /// A bounded source port of MCEcho: three fully connected nodes and `a`
    /// as TLC's deterministic choice of initiator. The typed record spells
    /// the upstream `sndr` field as the clearer Swift name `sender`.
    package static let echo = FiniteModelFixture(
        expectedDistinct: 75,
        maximumStateLimit: 50_000,
        spec: EchoModel.spec,
    )
}
