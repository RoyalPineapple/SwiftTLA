import SwiftTLA
import SwiftTLAMacros

// The pinned VIEW configuration remains to be added before parity registration.
// Upstream: specifications/ewd998/EWD998ChanID.tla and EWD998ChanID.cfg.
@TLAModel
package struct EWD998ChanIDModel: Sendable {
    package enum NodeID: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, n4, n5

        package static var defaultValue: Self { .n1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Color: String, CaseIterable, FiniteTLAValueDomain {
        case white, black

        package static var defaultValue: Self { .black }
        package static let finiteValues = allCases
    }

    package enum TokenKind: String, CaseIterable, FiniteTLAValueDomain {
        case token = "tok"

        package static var defaultValue: Self { .token }
        package static let finiteValues = allCases
    }

    package enum PayloadKind: String, CaseIterable, FiniteTLAValueDomain {
        case payload = "pl"

        package static var defaultValue: Self { .payload }
        package static let finiteValues = allCases
    }

    package struct TokenMessage: Hashable, Sendable {
        package let type: TokenKind
        package let q: Int
        package let color: Color
        package let vc: [NodeID: Int]
    }

    package struct PayloadMessage: Hashable, Sendable {
        package let type: PayloadKind
        package let src: NodeID
        package let vc: [NodeID: Int]
    }

    package typealias Message = OneOf<TokenMessage, PayloadMessage>

    package struct AbstractTokenMessage: Hashable, Sendable {
        package let type: TokenKind
        package let q: Int
        package let color: Color
    }

    package struct AbstractPayloadMessage: Hashable, Sendable {
        package let type: PayloadKind
    }

    package typealias AbstractMessage = OneOf<AbstractTokenMessage, AbstractPayloadMessage>

    private enum Step: String, CaseIterable {
        case InitiateProbe, PassToken, SendMsg, RecvMsg, Deactivate
    }

    package static var spec: TLASpec {
        #spec("EWD998ChanID") { scope in
            Extends(.integers, .sequences, .finiteSets)
            let Node = scope.parameter(as: Set<NodeID>.self,
                in: Subsets(of: NodeID.all.assuming(Set<NodeID>.self)))
            Assume(!Node.isEmpty)
            let N = Node.cardinality
            let Initiator = Select(from: Node) { _ in true }
            let RingOfNodes = Select(from: Functions(from: Node, to: Node)) { ring in
                LetRec("CycleReach", taking: Pair<NodeID, Int>.self,
                    { (reach: LocalRecursion<Pair<NodeID, Int>, NodeID>,
                       input: WithValue<Pair<NodeID, Int>>) in
                        If(input.second() == 0,
                            then: input.first(),
                            else: ring[reach(Pair.literal(input.first(), input.second() - 1))])
                    }, in: { reach in
                        IntRange(0, through: N - 1).mapping { depth in
                            reach(Pair.literal(Initiator, depth))
                        } == Node
                    })
            }
            let nat2node = LetRec("Nat2Node", over: IntRange(0, through: N - 1), taking: Int.self,
                { (position: LocalRecursion<Int, NodeID>, index: WithValue<Int>) in
                    If(index == 0, then: Initiator,
                        else: Select(from: Node) { node in
                            RingOfNodes[node] == position(index.expr - 1)
                        })
                }, in: { position in
                    Dictionary<Int, NodeID>.mapping(over: IntRange(0, through: N - 1)) { index in
                        position(index.expr)
                    }
                })

            let counter = scope.sharedVar(initial: Dictionary<NodeID, Int>.mapping(over: Node) { _ in 0 })
            let clock = scope.sharedVar(initial: Dictionary<NodeID, [NodeID: Int]>.mapping(over: Node) { node in
                Dictionary<NodeID, Int>.mapping(over: Node) { member in
                    If(node == Initiator && member == Initiator, then: 1, else: 0)
                }
            })
            let initialToken = Message.first(TokenMessage.expression(
                type: TokenKind.token, q: 0, color: Color.black,
                vc: Dictionary<NodeID, Int>.mapping(over: Node) { member in
                    If(nat2node[N - 2] == Initiator && member == Initiator, then: 1, else: 0)
                }))
            let inbox = scope.sharedVar(initial: Dictionary<NodeID, [Message]>.mapping(over: Node) { node in
                SequenceMapping(length: If(node == nat2node[N - 2], then: 1, else: 0)) { _ in
                    initialToken
                }
            })
            let active = scope.sharedVar(initial: Dictionary<NodeID, Bool>.mapping(over: Node) { _ in false })
            let color = scope.sharedVar(initial: Dictionary<NodeID, Color>.mapping(over: Node) { _ in Color.black })
            let passes = scope.sharedVar(initial: 0)

            let initiate = Do(Step.InitiateProbe, over: Node) { node in
                When(node == Initiator)
                With(IntRange(1, through: inbox[node].count)) { index in
                    When(inbox[node][index].recordFields.contains("q"))
                    let token = inbox[node][index].assuming(TokenMessage.self)
                    When(token.color == Color.black || color[node] == Color.black
                        || counter[node] + token.q != 0)
                    Assign(clock[node], to: Dictionary<NodeID, Int>.mapping(over: Node) { member in
                        If(member == node, then: clock[node][member] + 1,
                            else: If(token.vc[member] > clock[node][member],
                                then: token.vc[member], else: clock[node][member]))
                    })
                    Assign(inbox[RingOfNodes[node]], to: inbox[RingOfNodes[node]].appending(
                        Message.first(TokenMessage.expression(
                            type: TokenKind.token, q: 0, color: Color.white, vc: clock[node]))))
                    Assign(inbox[node], to: inbox[node].removing(at: index))
                    Assign(color[node], to: Color.white)
                    Assign(passes, to: If(passes >= 0, then: passes + 1, else: passes))
                }
            }
            initiate

            let pass = Do(Step.PassToken, over: Node) { node in
                When(node != Initiator && !active[node])
                With(IntRange(1, through: inbox[node].count)) { index in
                    When(inbox[node][index].recordFields.contains("q"))
                    let token = inbox[node][index].assuming(TokenMessage.self)
                    Assign(clock[node], to: Dictionary<NodeID, Int>.mapping(over: Node) { member in
                        If(member == node, then: clock[node][member] + 1,
                            else: If(token.vc[member] > clock[node][member],
                                then: token.vc[member], else: clock[node][member]))
                    })
                    Assign(inbox[RingOfNodes[node]], to: inbox[RingOfNodes[node]].appending(
                        Message.first(TokenMessage.expression(
                            type: TokenKind.token, q: token.q + counter[node],
                            color: If(color[node] == Color.black, then: Color.black, else: token.color),
                            vc: clock[node]))))
                    Assign(inbox[node], to: inbox[node].removing(at: index))
                    Assign(color[node], to: Color.white)
                    Assign(passes, to: If(passes >= 0, then: passes + 1, else: passes))
                }
            }
            pass
            WeakFairness(eachOf: [initiate, pass])

            Do(Step.SendMsg, over: Node) { node in
                When(active[node])
                Assign(counter[node], to: counter[node] + 1)
                Assign(clock[node][node], to: clock[node][node] + 1)
                With(Node.removing(node)) { receiver in
                    Assign(inbox[receiver], to: inbox[receiver].appending(
                        Message.second(PayloadMessage.expression(
                            type: PayloadKind.payload, src: node, vc: clock[node]))))
                }
            }
            Do(Step.RecvMsg, over: Node) { node in
                With(IntRange(1, through: inbox[node].count)) { index in
                    When(inbox[node][index].recordFields.contains("src"))
                    let payload = inbox[node][index].assuming(PayloadMessage.self)
                    Assign(counter[node], to: counter[node] - 1)
                    Assign(color[node], to: Color.black)
                    Assign(active[node], to: true)
                    Assign(clock[node], to: Dictionary<NodeID, Int>.mapping(over: Node) { member in
                        If(member == node, then: clock[node][member] + 1,
                            else: If(payload.vc[member] > clock[node][member],
                                then: payload.vc[member], else: clock[node][member]))
                    })
                    Assign(inbox[node], to: inbox[node].removing(at: index))
                }
            }
            let terminated = ForAll(in: Node) { node in
                !active[node] && inbox[node].selecting(where: { message in
                    message.recordFields.contains("src")
                }).count == 0
            }
            Do(Step.Deactivate, over: Node) { node in
                When(active[node])
                Assign(active[node], to: false)
                Assign(clock[node][node], to: clock[node][node] + 1)
                Assign(passes, to: If(terminated, then: 0, else: passes))
            }

            let terminationDetected = Exists(in: IntRange(1, through: inbox[Initiator].count)) { index in
                If(inbox[Initiator][index].recordFields.contains("q"),
                    then: inbox[Initiator][index].assuming(TokenMessage.self).color == Color.white
                        && inbox[Initiator][index].assuming(TokenMessage.self).q + counter[Initiator] == 0,
                    else: false)
            } && color[Initiator] == Color.white && !active[Initiator]

            let Max3TokenRounds = Invariant()
            Max3TokenRounds { passes <= 3 * N }
            let EWD998Safe = Invariant()
            EWD998Safe { !terminationDetected || terminated }
            let EWD998Live = Temporal()
            EWD998Live(.leadsTo(terminated, terminationDetected))
            Constraint(ForAll(in: Node) { node in
                inbox[node].selecting(where: { message in
                    message.recordFields.contains("src")
                }).count < 3 && counter[node] <= 3
            })

            let abstractInbox = Dictionary<Int, [AbstractMessage]>.mapping(over: IntRange(0, through: N - 1)) { position in
                SequenceMapping(length: inbox[nat2node[position]].count) { index in
                    If(inbox[nat2node[position]][index].recordFields.contains("q"),
                        then: AbstractMessage.first(AbstractTokenMessage.expression(
                            type: TokenKind.token,
                            q: inbox[nat2node[position]][index].assuming(TokenMessage.self).q,
                            color: inbox[nat2node[position]][index].assuming(TokenMessage.self).color)),
                        else: AbstractMessage.second(AbstractPayloadMessage.expression(type: PayloadKind.payload)))
                }
            }
            let abstract = Instance(of: EWD998ChanModel.self) { Bind(\.N, to: N) }
            abstract
            let EWD998ChanSpec = Refinement(instance: abstract) {
                Map(\.counter, from: Dictionary<Int, Int>.mapping(over: IntRange(0, through: N - 1)) { position in
                    counter[nat2node[position]]
                })
                Map(\.inbox, from: abstractInbox, projecting: [Int: [EWD998ChanModel.Message]].self)
                Map(\.active, from: Dictionary<Int, Bool>.mapping(over: IntRange(0, through: N - 1)) { position in
                    active[nat2node[position]]
                })
                Map(\.color, from: Dictionary<Int, Color>.mapping(over: IntRange(0, through: N - 1)) { position in
                    color[nat2node[position]]
                }, projecting: [Int: EWD998ChanModel.Color].self)
            }
            EWD998ChanSpec
        }
    }
}
