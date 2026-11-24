import SwiftTLA
import SwiftTLAMacros

/// The bounded three-node Echo spanning-tree algorithm from the upstream
/// TLA+ Examples repository.
///
/// A record is the message on the network. The `inbox` finite function gives
/// every node its own set of messages, while each `Each(Node)` body is an
/// independently scheduled PlusCal process.
@TLAModel
package struct EchoModel: Sendable {
    package enum NodeID: String, CaseIterable {
        case a, b, c
    }

    package enum MessageKind: String, CaseIterable {
        case message = "m"
        case acknowledgement = "c"
    }

    package struct Message: Hashable, Sendable {
        package let kind: MessageKind
        package let sndr: NodeID
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
            let Node = spec.parameter(as: Set<NodeID>.self, in: Subsets(of: NodeID.all.assuming(Set<NodeID>.self)))
            let initiator = spec.parameter(as: NodeID.self, in: Node)
            let pairs = Node.flatMapping { (from: WithValue<NodeID>) in
                Node.mapping { (to: WithValue<NodeID>) in Pair<NodeID, NodeID>.literal(from, to) }
            }
            let R = spec.parameter(as: Set<Pair<NodeID, NodeID>>.self, in: Subsets(of: pairs))
            Assume(Node.contains(initiator))
            Assume(Node.allSatisfy { node in !R.contains(Pair<NodeID, NodeID>.literal(node, node)) })
            Assume(pairs.allSatisfy { edge in
                R.contains(edge) == R.contains(Pair<NodeID, NodeID>.literal(edge.second(), edge.first()))
            })
            Assume(LetRec("echoConnectedPath", taking: Triple<NodeID, NodeID, Int>.self,
                { (path: LocalRecursion<Triple<NodeID, NodeID, Int>, Bool>,
                   endpoints: WithValue<Triple<NodeID, NodeID, Int>>) in
                    endpoints.first() == endpoints.second()
                        || (endpoints.third() > 0 && Exists(in: Node) { next in
                            R.contains(Pair<NodeID, NodeID>.literal(endpoints.first(), next))
                                && path(Triple<NodeID, NodeID, Int>.literal(
                                    next, endpoints.second(), endpoints.third() - 1))
                        })
                }, in: { path in
                    Node.allSatisfy { from in
                        Node.allSatisfy { to in
                            path(Triple<NodeID, NodeID, Int>.literal(from, to, Node.count))
                        }
                    }
                }))
            let TypeOK = Invariant()
            let AncestorProperties = Invariant()
            let Echo = Algorithm { (scope: AlgorithmScope) in
                let inbox: SharedVariable<[NodeID: Set<Message>]> = scope.sharedVar(initial:
                    Dictionary<NodeID, Set<Message>>.mapping(over: Node) { _ in Set<Message>() })

                Each(Node) { (selfID: ProcessIdentifier<NodeID>, scope: ProcessScope) in
                    let parent: LocalVariable<OneOf<NodeID, NoNode>> = scope.localVar(
                        initial: OneOf<NodeID, NoNode>.second(NoNode.value)
                    )
                    let children: LocalVariable<Set<NodeID>> = scope.localVar(initial: Set<NodeID>())
                    let rcvd: LocalVariable<Int> = scope.localVar(initial: 0)
                    let nbrs: LocalVariable<Set<NodeID>> = scope.localVar(
                        initial: Node.filter { neighbor in
                            R.contains(Pair<NodeID, NodeID>.literal(neighbor, selfID))
                        }
                    )

                    Do(Step.n0) {
                        If(selfID == initiator) {
                            inbox.set(Dictionary<NodeID, Set<Message>>.mapping(over: Node) { (destination: WithValue<NodeID>) -> Expr<Set<Message>> in
                                If(nbrs.expr.contains(destination),
                                   then: inbox[destination].inserting(Message.expression(kind: MessageKind.message, sndr: selfID)),
                                   else: inbox[destination])
                            })
                        }
                    }

                    While(Step.n1, rcvd.expr < nbrs.expr.count) {
                        With(inbox[selfID]) { (message: WithValue<Message>) in
                            Let(inbox.updating(selfID, to: inbox[selfID].removing(message))) { (networkAfterReceive: WithValue<[NodeID: Set<Message>]>) in
                                If(selfID != initiator && rcvd.expr == 0) {
                                    Assert(message.kind == .message)
                                    parent.set(OneOf<NodeID, NoNode>.first(message.sndr))
                                    inbox.set(Dictionary<NodeID, Set<Message>>.mapping(over: Node) { (destination: WithValue<NodeID>) -> Expr<Set<Message>> in
                                        If(nbrs.expr.removing(message.sndr).contains(destination),
                                           then: networkAfterReceive[destination].inserting(Message.expression(kind: MessageKind.message, sndr: selfID)),
                                           else: networkAfterReceive[destination])
                                    })
                                } else: {
                                    inbox.set(networkAfterReceive.expr)
                                }
                                rcvd += 1
                                If(message.kind == .acknowledgement) {
                                    children.insert(message.sndr)
                                }
                            }
                        }
                    }

                    Do(Step.n2) {
                        If(selfID != initiator) {
                            let destination = parent.expr.assuming(NodeID.self)
                            Assert(nbrs.expr.contains(destination))
                            inbox.set(inbox.updating(destination, to: inbox[destination].inserting(
                                Message.expression(kind: MessageKind.acknowledgement, sndr: selfID)
                            )))
                        }
                    }

                    TypeOK {
                        parent == OneOf<NodeID, NoNode>.second(NoNode.value)
                            || Exists(in: Node) { node in
                                parent == OneOf<NodeID, NoNode>.first(node)
                            }
                        children.isSubset(of: Node)
                        rcvd >= 0 && rcvd <= nbrs.count
                        nbrs == Node.filter { neighbor in
                            R.contains(Pair<NodeID, NodeID>.literal(neighbor, selfID))
                        }
                        inbox.keys == Node.assuming(Set<NodeID>.self)
                        inbox[selfID].allSatisfy { message in
                            (message.kind == .message || message.kind == .acknowledgement)
                                && Node.contains(message.sndr)
                                && nbrs.contains(message.sndr)
                        }
                    }

                    let parents = parent.family(for: NodeID.self)
                    AncestorProperties {
                        !Node.allSatisfy { node in Finished(node) }
                            || LetRec("ancestor", taking: Triple<NodeID, NodeID, Int>.self,
                                { (ancestor: LocalRecursion<Triple<NodeID, NodeID, Int>, Bool>,
                                   path: WithValue<Triple<NodeID, NodeID, Int>>) in
                                    If(path.third() == 0, then: false, else:
                                        parents[path.first()] == OneOf<NodeID, NoNode>.first(path.second())
                                            || Exists(in: Node) { next in
                                                parents[path.first()] == OneOf<NodeID, NoNode>.first(next)
                                                    && ancestor(Triple<NodeID, NodeID, Int>.literal(
                                                        next, path.second(), path.third() - 1))
                                            })
                                }, in: { ancestor in
                                    Node.allSatisfy { node in
                                        node == initiator || ancestor(Triple<NodeID, NodeID, Int>.literal(
                                            node, initiator, Node.count))
                                    }
                                        && Node.allSatisfy { node in
                                            !ancestor(Triple<NodeID, NodeID, Int>.literal(
                                                node, node, Node.count))
                                        }
                                })
                    }
                }
            }
            Echo
            let MCEcho = Validation {
                Bind(Node, to: Set<NodeID>([.a, .b, .c]))
                Bind(initiator, to: NodeID.a)
                Bind(R, to: Set<Pair<NodeID, NodeID>>([
                    Pair(first: .a, second: .b), Pair(first: .b, second: .a),
                    Pair(first: .a, second: .c), Pair(first: .c, second: .a),
                    Pair(first: .b, second: .c), Pair(first: .c, second: .b)
                ]))
            }
                .expect(TypeOK, .satisfied)
                .expect(AncestorProperties, .satisfied)
                .expectDeadlock(.satisfied)
            MCEcho
        }
    }
}
