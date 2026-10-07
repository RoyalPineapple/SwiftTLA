import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/ewd998/EWD998.tla, EWD998.cfg, and EWD998Small.cfg.
@TLAModel
package struct EWD998Model: Sendable {
    package enum Color: String, TLAValueType {
        case white, black

        package static var defaultValue: Self { .white }
    }

    package struct Token: Hashable, Sendable {
        package let pos: Int
        package let q: Int
        package let color: Color
    }

    private enum Step: String, CaseIterable {
        case InitiateProbe, PassToken, SendMsg, RecvMsg, Deactivate
    }

    package static var spec: TLASpec {
        #spec("EWD998") { scope in
            Extends(.integers, .finiteSets)
            Import(FunctionsModule.module)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = IntRange(0, through: N - 1)
            let Colors = SetExpr<Color>.literal(.white, .black)
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                in: Functions(from: Node, to: SetExpr<Bool>.literal(false, true)))
            let color: SharedVariable<[Int: Color]> = scope.sharedVar(
                in: Functions(from: Node, to: Colors))
            let counter = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: Node) { _ in 0 })
            let pending = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: Node) { _ in 0 })
            let token = scope.sharedVar(in: Node.mapping { position in
                Token.expression(pos: position, q: 0, color: Color.black)
            })

            let initiate = Do(Step.InitiateProbe) {
                When(token.pos == 0
                    && (token.color == Color.black || color[0] == Color.black
                        || counter[0] + token.q > 0))
                Assign(token, to: Token.expression(pos: N - 1, q: 0, color: Color.white))
                Assign(color[0], to: Color.white)
            }
            initiate
            let pass = Do(Step.PassToken, over: Node) { node in
                When(node != 0 && !active[node] && token.pos == node)
                Assign(token, to: Token.expression(
                    pos: token.pos - 1,
                    q: token.q + counter[node],
                    color: If(color[node] == Color.black, then: Color.black, else: token.color)))
                Assign(color[node], to: Color.white)
            }
            pass
            WeakFairness(anyOf: [initiate, pass])

            Do(Step.SendMsg, over: Node) { sender in
                When(active[sender])
                Assign(counter[sender], to: counter[sender] + 1)
                With(Node.removing(sender)) { receiver in
                    Assign(pending[receiver], to: pending[receiver] + 1)
                }
            }
            Do(Step.RecvMsg, over: Node) { node in
                When(pending[node] > 0)
                Assign(pending[node], to: pending[node] - 1)
                Assign(counter[node], to: counter[node] - 1)
                Assign(color[node], to: Color.black)
                Assign(active[node], to: true)
            }
            Do(Step.Deactivate, over: Node) { node in
                When(active[node])
                Assign(active[node], to: false)
            }

            let TypeOK = Invariant()
            let TerminationDetection = Invariant()
            let Inv = Invariant()
            let Liveness = Temporal()
            let B = Sum(pending, over: Node)
            let Termination = ForAll(in: Node) { node in !active[node] } && B == 0
            let terminationDetected = token.pos == 0 && token.color == Color.white
                && token.q + counter[0] == 0 && color[0] == Color.white && !active[0]
            let afterToken = IntRange(token.pos + 1, through: N - 1)
            let beforeToken = IntRange(0, through: token.pos)

            TypeOK {
                Functions(from: Node, to: SetExpr<Bool>.literal(false, true)).contains(active)
                    && Functions(from: Node, to: Colors).contains(color)
                    && Functions(from: Node, to: Int.all).contains(counter)
                    && ForAll(in: Node) { node in pending[node] >= 0 }
                    && Node.contains(token.pos) && Colors.contains(token.color)
            }
            TerminationDetection { !terminationDetected || Termination }
            Inv {
                B == Sum(counter, over: Node)
                    && (
                        (ForAll(in: afterToken) { node in !active[node] }
                            && If(token.pos == N - 1,
                                then: token.q == 0,
                                else: token.q == Sum(counter, over: afterToken)))
                        || Sum(counter, over: beforeToken) + token.q > 0
                        || Exists(in: beforeToken) { node in color[node] == Color.black }
                        || token.color == Color.black
                    )
            }
            Liveness(.leadsTo(Termination, terminationDetected))
            Constraint(ForAll(in: Node) { node in counter[node] <= 3 && pending[node] <= 3 }
                && token.q <= 9)

            let TD = Instance(of: EWD998TerminationModel.self) { Bind(\.N, to: N) }
            TD
            let TDSpec = Refinement(instance: TD) {
                Map(\.active, from: active)
                Map(\.pending, from: pending)
                Map(\.terminationDetected, from: terminationDetected)
            }
            TDSpec

            let EWD998 = Validation { Bind(N, to: 4) }
                .checking(only: [TypeOK, TerminationDetection, Inv, Liveness, TDSpec])
                .checkingDeadlock(false)
            EWD998
            let EWD998Small = Validation { Bind(N, to: 3) }
                .checking(only: [TypeOK, TerminationDetection, Inv])
                .checkingDeadlock(false)
            EWD998Small
        }
    }
}
