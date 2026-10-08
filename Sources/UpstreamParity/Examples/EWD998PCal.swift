import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/ewd998/EWD998PCal.tla and EWD998PCal.cfg.
@TLAModel
package struct EWD998PCalModel: Sendable {
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
    }

    package struct PayloadMessage: Hashable, Sendable {
        package let type: PayloadKind
    }

    package struct ProjectedToken: Hashable, Sendable {
        package let pos: Int
        package let q: Int
        package let color: Color
    }

    package typealias Message = OneOf<TokenMessage, PayloadMessage>

    private enum Step: String, CaseIterable {
        case l, node
    }

    package static var spec: TLASpec {
        #spec("EWD998PCal") { scope in
            Extends(.integers)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node: Expr<Set<Int>> = IntRange(0, through: N - 1)
            let payload: Expr<Message> = Message.second(PayloadMessage.expression(type: PayloadKind.payload))
            let initialToken: Expr<Message> = Message.first(TokenMessage.expression(
                type: TokenKind.token, q: 0, color: Color.black))
            let network: SharedVariable<[Int: [Message: Int]]> = scope.sharedVar(
                initial: Dictionary<Int, [Message: Int]>.mapping(over: Node) { node in
                If(node == 0,
                    then: Dictionary<Message, Int>.mapping(over: SetExpr<Message>.literal(initialToken)) { _ in 1 },
                    else: Dictionary<Message, Int>.mapping(over: SetExpr<Message>.literal()) { _ in 0 })
            })

            let Safra: Algorithm = Algorithm(scoped: { _ in
                Each(Node, named: Step.node, fairness: .weak, scoped: { node, process in
                    let active = process.localVar(in: SetExpr<Bool>.literal(false, true), exposed: true)
                    let color = process.localVar(initial: Color.black, exposed: true)
                    let counter = process.localVar(initial: 0, exposed: true)

                    let sendPayload: StatementMacro<Void> = Macro {
                        When(active)
                        With(Node.removing(node)) { destination in
                            Assign(network[destination], to: Dictionary<Message, Int>.mapping(
                                over: network[destination].keys.inserting(payload)) { message in
                                If(message == payload,
                                    then: If(network[destination].keys.contains(payload),
                                        then: network[destination][payload] + 1, else: 1),
                                    else: network[destination][message])
                            })
                        }
                        Assign(counter, to: counter + 1)
                    }
                    let receivePayload: StatementMacro<Void> = Macro {
                        With(network[node].keys) { message in
                            When(message == payload)
                            Assign(counter, to: counter - 1)
                            Assign(active, to: true)
                            Assign(color, to: Color.black)
                            Assign(network[node], to: Dictionary<Message, Int>.mapping(
                                over: If(network[node][message] == 1,
                                    then: network[node].keys.removing(message),
                                    else: network[node].keys)) { key in
                                If(key == message, then: network[node][key] - 1,
                                    else: network[node][key])
                            })
                        }
                    }
                    let deactivate: StatementMacro<Void> = Macro { Assign(active, to: false) }
                    let passToken: StatementMacro<Void> = Macro {
                        When(node != 0)
                        With(network[node].keys) { token in
                            When(token != payload && !active)
                            let old = token.assuming(TokenMessage.self)
                            let next = Message.first(TokenMessage.expression(
                                type: TokenKind.token,
                                q: old.q + counter,
                                color: If(color == Color.black,
                                    then: Color.black, else: old.color)))
                            Assign(network[node], to: Dictionary<Message, Int>.mapping(
                                over: If(network[node][token] == 1,
                                    then: network[node].keys.removing(token),
                                    else: network[node].keys)) { key in
                                If(key == token, then: network[node][key] - 1,
                                    else: network[node][key])
                            })
                            Assign(network[node - 1], to: Dictionary<Message, Int>.mapping(
                                over: network[node - 1].keys.inserting(next)) { key in
                                If(key == next,
                                    then: If(network[node - 1].keys.contains(next),
                                        then: network[node - 1][next] + 1, else: 1),
                                    else: network[node - 1][key])
                            })
                            Assign(color, to: Color.white)
                        }
                    }
                    let initiateToken: StatementMacro<Void> = Macro {
                        When(node == 0)
                        With(network[node].keys) { token in
                            When(token != payload)
                            let old = token.assuming(TokenMessage.self)
                            When(color == Color.black || old.q + counter != 0
                                || old.color == Color.black)
                            let next = Message.first(TokenMessage.expression(
                                type: TokenKind.token, q: 0, color: Color.white))
                            Assign(network[node], to: Dictionary<Message, Int>.mapping(
                                over: If(network[node][token] == 1,
                                    then: network[node].keys.removing(token),
                                    else: network[node].keys)) { key in
                                If(key == token, then: network[node][key] - 1,
                                    else: network[node][key])
                            })
                            Assign(network[N - 1], to: Dictionary<Message, Int>.mapping(
                                over: network[N - 1].keys.inserting(next)) { key in
                                If(key == next,
                                    then: If(network[N - 1].keys.contains(next),
                                        then: network[N - 1][next] + 1, else: 1),
                                    else: network[N - 1][key])
                            })
                            Assign(color, to: Color.white)
                        }
                    }

                    While(Step.l, true) {
                        Either { sendPayload() } or: {
                            Either { receivePayload() } or: {
                                Either { deactivate() } or: {
                                    Either { passToken() } or: { initiateToken() }
                                }
                            }
                        }
                    }

                    StateConstraint(counter < 3)
                })
            })
            Safra

            let tokenPosition: Expr<Int> = Select(from: Node) { node in
                Exists(in: network[node.expr].keys) { message in message != payload }
            }
            let tokenMessage: Expr<TokenMessage> = Select(from: network[tokenPosition].keys) { message in
                message != payload
            }.assuming(TokenMessage.self)
            let pending: Expr<[Int: Int]> = Dictionary<Int, Int>.mapping(over: Node) { node in
                If(network[node].keys.contains(payload), then: network[node][payload], else: 0)
            }
            let abstract = Instance(of: EWD998Model.self) { Bind(\.N, to: N) }
            abstract
            let EWD998Spec = Refinement(instance: abstract, behavior: .initialAndNext) {
                Map(\.active, from: \EWD998PCalModel.State.active)
                Map(\.color, from: \EWD998PCalModel.State.color,
                    projecting: [Int: EWD998Model.Color].self)
                Map(\.counter, from: \EWD998PCalModel.State.counter)
                Map(\.pending, from: pending)
                Map(\.token, from: ProjectedToken.expression(
                    pos: tokenPosition, q: tokenMessage.q, color: tokenMessage.color),
                    projecting: EWD998Model.Token.self)
            }
            EWD998Spec

            let EWD998PCal = Validation { Bind(N, to: 3) }
                .checking(only: [EWD998Spec])
            EWD998PCal
        }
    }
}
