import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/ewd998/EWD998Chan.tla and EWD998Chan.cfg.
@TLAModel
package struct EWD998ChanModel: Sendable {
    package enum Color: String, CaseIterable, FiniteTLAValueDomain {
        case white, black

        package static var defaultValue: Self { .white }
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
        case InitiateProbe, PassToken, SendMsg, RecvMsg, Deactivate
    }

    package static var spec: TLASpec {
        #spec("EWD998Chan") { scope in
            Extends(.integers, .sequences, .finiteSets)
            Import(FunctionsModule.module)
            let N = scope.parameter(as: Int.self, in: Int.all)
            let TraceMode = scope.parameter(as: Bool.self, in: Set<Bool>([false, true]))
            Assume(N > 0)
            let Node = IntRange(0, through: N - 1)
            let Colors = SetExpr<Color>.literal(.white, .black)
            let payload = Message.second(PayloadMessage.expression(type: PayloadKind.payload))
            let initialToken = Message.first(TokenMessage.expression(
                type: TokenKind.token, q: 0, color: Color.black))

            let counter = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: Node) { _ in 0 })
            let inbox = scope.sharedVar(in: Node.mapping { position in
                Dictionary<Int, [Message]>.mapping(over: Node) { node in
                    SequenceMapping(length: If(node == position, then: 1, else: 0)) { _ in initialToken }
                }
            })
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                in: Functions(from: Node, to: If(TraceMode,
                    then: SetExpr<Bool>.literal(true), else: SetExpr<Bool>.literal(false, true))))
            let color: SharedVariable<[Int: Color]> = scope.sharedVar(in: Functions(from: Node,
                to: If(TraceMode, then: SetExpr<Color>.literal(.white), else: Colors)))

            let initiate = Do(Step.InitiateProbe) {
                With(IntRange(1, through: inbox[0].count)) { index in
                    When(inbox[0][index] != payload)
                    When(inbox[0][index].assuming(TokenMessage.self).color == Color.black
                        || color[0] == Color.black
                        || counter[0] + inbox[0][index].assuming(TokenMessage.self).q != 0)
                    Assign(inbox[N - 1], to: inbox[N - 1].appending(Message.first(
                        TokenMessage.expression(type: TokenKind.token, q: 0, color: Color.white))))
                    Assign(inbox[0], to: inbox[0].removing(at: index))
                    Assign(color[0], to: Color.white)
                }
            }
            initiate

            let pass = Do(Step.PassToken, over: Node) { node in
                When(node != 0 && !active[node])
                With(IntRange(1, through: inbox[node].count)) { index in
                    When(inbox[node][index] != payload)
                    Assign(inbox[node - 1], to: inbox[node - 1].appending(Message.first(
                        TokenMessage.expression(type: TokenKind.token,
                            q: inbox[node][index].assuming(TokenMessage.self).q + counter[node],
                            color: If(color[node] == Color.black, then: Color.black,
                                else: inbox[node][index].assuming(TokenMessage.self).color)))))
                    Assign(inbox[node], to: inbox[node].removing(at: index))
                    Assign(color[node], to: Color.white)
                }
            }
            pass
            WeakFairness(anyOf: [initiate, pass])

            Do(Step.SendMsg, over: Node) { sender in
                When(active[sender])
                With(Node.removing(sender)) { receiver in
                    Assign(counter[sender], to: counter[sender] + 1)
                    Assign(inbox[receiver], to: inbox[receiver].appending(payload))
                }
            }
            Do(Step.RecvMsg, over: Node) { node in
                With(IntRange(1, through: inbox[node].count)) { index in
                    When(inbox[node][index] == payload)
                    Assign(counter[node], to: counter[node] - 1)
                    Assign(color[node], to: Color.black)
                    Assign(active[node], to: true)
                    Assign(inbox[node], to: inbox[node].removing(at: index))
                }
            }
            Do(Step.Deactivate, over: Node) { node in
                When(active[node])
                Assign(active[node], to: false)
            }

            let TypeOK = Invariant()
            let tokenCounts = Dictionary<Int, Int>.mapping(over: Node) { node in
                inbox[node].selecting { message in message != payload }.count
            }
            TypeOK {
                Functions(from: Node, to: Int.all).contains(counter)
                    && Functions(from: Node, to: SetExpr<Bool>.literal(false, true)).contains(active)
                    && Functions(from: Node, to: Colors).contains(color)
                    && inbox.keys == Node
                    && Sum(tokenCounts, over: Node) == 1
            }
            Constraint(ForAll(in: Node) { node in
                inbox[node].selecting { message in message == payload }.count < 3
                    && counter[node] <= 3
            })

            let tokenPosition = Select(from: Node) { node in tokenCounts[node.expr] == 1 }
            let tokenIndex = Select(from: IntRange(1, through: inbox[tokenPosition].count)) { index in
                inbox[tokenPosition][index.expr] != payload
            }
            let token = inbox[tokenPosition][tokenIndex].assuming(TokenMessage.self)
            let pending = Dictionary<Int, Int>.mapping(over: Node) { node in
                inbox[node].selecting { message in message == payload }.count
            }
            let abstract = Instance(of: EWD998Model.self) { Bind(\.N, to: N) }
            abstract
            let EWD998Spec = Refinement(instance: abstract) {
                Map(\.active, from: active)
                Map(\.color, from: color, projecting: [Int: EWD998Model.Color].self)
                Map(\.counter, from: counter)
                Map(\.pending, from: pending)
                Map(\.token, from: ProjectedToken.expression(
                    pos: tokenPosition, q: token.q, color: token.color),
                    projecting: EWD998Model.Token.self)
            }
            EWD998Spec

            let EWD998Chan = Validation {
                Bind(N, to: 3)
                Bind(TraceMode, to: false)
            }
                .checking(only: [TypeOK, EWD998Spec])
                .checkingDeadlock(false)
            EWD998Chan
        }
    }
}
