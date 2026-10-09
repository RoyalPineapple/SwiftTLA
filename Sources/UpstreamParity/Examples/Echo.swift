import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/echo/Echo.tla and MCEcho.cfg.
@TLAModel
package struct EchoModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case a, b, c

        package static var defaultValue: Self { .a }
        package static let finiteValues = allCases
    }

    package enum NoNode: String, CaseIterable, FiniteTLAValueDomain {
        case noNode = "NoNode"

        package static var defaultValue: Self { .noNode }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum MessageKind: String, CaseIterable {
        case message = "m"
        case acknowledgement = "c"
    }

    package struct Message: Hashable, Sendable {
        package let kind: MessageKind
        package let sndr: Node
    }

    private enum Step: String, CaseIterable {
        case n0, n1, n2
    }

    package static var spec: TLASpec {
        #spec("Echo") {
            Extends(.finiteSets)
            let node = Set<Node>([.a, .b, .c]).expr
            let initiator = Select(from: node) { _ in true }
            let TypeOK = Invariant()
            let AncestorProperties = Invariant()
            let Echo = Algorithm(scoped: { (scope: AlgorithmScope) in
                let inbox: SharedVariable<[Node: Set<Message>]> = scope.sharedVar(initial: [
                    .a: Set<Message>(), .b: Set<Message>(), .c: Set<Message>()
                ])

                Each(node, scoped: { (selfID: ProcessIdentifier<Node>, scope: ProcessScope) in
                    let parent: LocalVariable<OneOf<Node, NoNode>> = scope.localVar(initial: .second(.noNode))
                    let children: LocalVariable<Set<Node>> = scope.localVar(initial: Set<Node>())
                    let rcvd: LocalVariable<Int> = scope.localVar(initial: 0)
                    let nbrs: LocalVariable<Set<Node>> = scope.localVar(initial: node.removing(selfID))

                    Do(Step.n0) {
                        If(selfID == initiator) {
                            Assign(inbox, to: Dictionary<Node, Set<Message>>.mapping(over: node) { (destination: WithValue<Node>) -> Expr<Set<Message>> in
                                If(nbrs.contains(destination),
                                   then: inbox[destination].inserting(Message.expression(kind: MessageKind.message, sndr: selfID)),
                                   else: inbox[destination])
                            })
                        }
                    }

                    While(Step.n1, rcvd.expr < nbrs.cardinality) {
                        With(inbox[selfID]) { (message: WithValue<Message>) in
                            Let(inbox.updating(selfID, to: inbox[selfID].removing(message))) { (networkAfterReceive: WithValue<[Node: Set<Message>]>) in
                                If(selfID != initiator && rcvd.expr == 0) {
                                    Assert(message.kind == .message)
                                    Assign(parent, to: OneOf<Node, NoNode>.first(message.sndr))
                                    Assign(inbox, to: Dictionary<Node, Set<Message>>.mapping(over: node) { (destination: WithValue<Node>) -> Expr<Set<Message>> in
                                        If(nbrs.removing(message.sndr).contains(destination),
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
                            let parentNode = parent.expr.assuming(Node.self)
                            Assert(nbrs.contains(parentNode))
                            Assign(inbox, to: inbox.updating(parentNode, to: inbox[parentNode].inserting(
                                Message.expression(kind: MessageKind.acknowledgement, sndr: selfID)
                            )))
                        }
                    }

                    let parents = parent.family(for: Node.self)
                    let childSets = children.family(for: Node.self)
                    let received = rcvd.family(for: Node.self)
                    let neighbors = nbrs.family(for: Node.self)
                    let validMessages = ForAll(in: node) { n in
                        ForAll(in: inbox[n]) { message in
                            SetExpr<MessageKind>.literal(.message, .acknowledgement).contains(message.kind)
                                && node.contains(message.sndr)
                                && neighbors[n].contains(message.sndr)
                        }
                    }
                    TypeOK {
                        inbox.keys == node
                        parents.keys == node
                        childSets.keys == node
                        received.keys == node
                        neighbors.keys == node
                        ForAll(in: node) { n in childSets[n].isSubset(of: node) }
                        ForAll(in: node) { n in received[n] >= 0 && received[n] <= neighbors[n].cardinality }
                        ForAll(in: node) { n in neighbors[n] == node.removing(n) }
                        validMessages
                    }
                    let finished = ForAll(in: node) { n in Finished(n) }
                    let reachesRoot = ForAll(in: node.removing(initiator)) { n in
                        parents[n] == OneOf<Node, NoNode>.first(initiator)
                            || Exists(in: node) { m in
                                parents[n] == OneOf<Node, NoNode>.first(m)
                                    && parents[m] == OneOf<Node, NoNode>.first(initiator)
                            }
                    }
                    let hasAncestorCycle = Exists(in: node) { n in
                        parents[n] == OneOf<Node, NoNode>.first(n)
                            || Exists(in: node) { m in
                                parents[n] == OneOf<Node, NoNode>.first(m)
                                    && (parents[m] == OneOf<Node, NoNode>.first(n)
                                        || Exists(in: node) { k in
                                            parents[m] == OneOf<Node, NoNode>.first(k)
                                                && parents[k] == OneOf<Node, NoNode>.first(n)
                                        })
                            }
                    }
                    AncestorProperties {
                        !finished || (reachesRoot && !hasAncestorCycle)
                    }
                })
            })
            Echo

            let MCEcho = Validation {}.checking(only: [TypeOK, AncestorProperties])
            MCEcho
        }
    }
}
