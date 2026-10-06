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
        package let sndr: Node
    }

    package enum NoNode: String, TLAValueType {
        case value = "NoNode"

        package static var defaultValue: Self { .value }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case n0, n1, n2
    }

    package static var spec: TLASpec {
        #spec("Echo") { (spec: SpecificationScope) in
            Extends(.finiteSets)
            let initiator = spec.parameter(as: Node.self, in: Node.all)
            let TypeOK = Invariant()
            let AncestorProperties = Invariant()
            let Echo = Algorithm(scoped: { (scope: AlgorithmScope) in
                let inbox: SharedVariable<[Node: Set<Message>]> = scope.sharedVar(initial: [
                    .a: Set<Message>(), .b: Set<Message>(), .c: Set<Message>()
                ])

                Each(Node.all, scoped: { (selfID: ProcessIdentifier<Node>, scope: ProcessScope) in
                    let parent: LocalVariable<OneOf<Node, NoNode>> = scope.localVar(
                        initial: OneOf<Node, NoNode>.second(NoNode.value)
                    )
                    let children: LocalVariable<Set<Node>> = scope.localVar(initial: Set<Node>())
                    let rcvd: LocalVariable<Int> = scope.localVar(initial: 0)
                    let nbrs: LocalVariable<Set<Node>> = scope.localVar(
                        initial: Node.all.removing(selfID).assuming(Set<Node>.self)
                    )

                    Do(Step.n0) {
                        If(selfID == initiator) {
                            Assign(inbox, to: Dictionary<Node, Set<Message>>.mapping(over: Node.all) { (destination: WithValue<Node>) -> Expr<Set<Message>> in
                                If(nbrs.expr.contains(destination),
                                   then: inbox[destination].inserting(Message.expression(kind: MessageKind.message, sndr: selfID)),
                                   else: inbox[destination])
                            })
                        }
                    }

                    While(Step.n1, rcvd.expr < nbrs.expr.cardinality) {
                        With(inbox[selfID]) { (message: WithValue<Message>) in
                            Let(inbox.updating(selfID, to: inbox[selfID].removing(message))) { (networkAfterReceive: WithValue<[Node: Set<Message>]>) in
                                If(selfID != initiator && rcvd.expr == 0) {
                                    Assert(message.kind == .message)
                                    Assign(parent, to: OneOf<Node, NoNode>.first(message.sndr))
                                    Assign(inbox, to: Dictionary<Node, Set<Message>>.mapping(over: Node.all) { (destination: WithValue<Node>) -> Expr<Set<Message>> in
                                        If(nbrs.expr.removing(message.sndr).contains(destination),
                                           then: networkAfterReceive[destination].inserting(Message.expression(kind: MessageKind.message, sndr: selfID)),
                                           else: networkAfterReceive[destination])
                                    })
                                } else: {
                                    Assign(inbox, to: networkAfterReceive.expr)
                                }
                                Assign(rcvd, to: rcvd.expr + 1)
                                If(message.kind == .acknowledgement) {
                                    Assign(children, to: children.expr.inserting(message.sndr))
                                }
                            }
                        }
                    }

                    Do(Step.n2) {
                        If(selfID != initiator) {
                            let destination = parent.expr.assuming(Node.self)
                            Assert(nbrs.expr.contains(destination))
                            Assign(inbox, to: inbox.updating(destination, to: inbox[destination].inserting(
                                Message.expression(kind: MessageKind.acknowledgement, sndr: selfID)
                            )))
                        }
                    }

                    TypeOK {
                        parent == OneOf<Node, NoNode>.second(NoNode.value)
                            || Exists(in: Node.all) { node in
                                parent == OneOf<Node, NoNode>.first(node)
                            }
                        children.isSubset(of: Node.all)
                        rcvd >= 0 && rcvd <= nbrs.cardinality
                        nbrs == Node.all.removing(selfID).assuming(Set<Node>.self)
                        inbox.keys == Node.all.assuming(Set<Node>.self)
                        ForAll(in: inbox[selfID]) { message in
                            (message.kind == .message || message.kind == .acknowledgement)
                                && Node.all.contains(message.sndr)
                                && nbrs.contains(message.sndr)
                        }
                    }

                    let parents = parent.family(for: Node.self)
                    AncestorProperties {
                        !ForAll(in: Node.all) { node in Finished(node) }
                            || LetRec("ancestor", taking: Triple<Node, Node, Int>.self,
                                { (ancestor: LocalRecursion<Triple<Node, Node, Int>, Bool>,
                                   path: WithValue<Triple<Node, Node, Int>>) in
                                    If(path.third() == 0, then: false, else:
                                        parents[path.first()] == OneOf<Node, NoNode>.first(path.second())
                                            || Exists(in: Node.all) { next in
                                                parents[path.first()] == OneOf<Node, NoNode>.first(next)
                                                    && ancestor(Triple<Node, Node, Int>.literal(
                                                        next, path.second(), path.third() - 1))
                                            })
                                }, in: { ancestor in
                                    ForAll(in: Node.all) { node in
                                        node == initiator || ancestor(Triple<Node, Node, Int>.literal(
                                            node, initiator, Node.all.cardinality))
                                    }
                                        && ForAll(in: Node.all) { node in
                                            !ancestor(Triple<Node, Node, Int>.literal(
                                                node, node, Node.all.cardinality))
                                        }
                                })
                    }
                })
            })
            Echo
            let MCEcho = Validation { Bind(initiator, to: Node.a) }
                .expect(TypeOK, .satisfied)
                .expect(AncestorProperties, .satisfied)
                .expectDeadlock(.satisfied)
            MCEcho
        }
    }
}
