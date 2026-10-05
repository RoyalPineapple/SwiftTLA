import SwiftTLA
import SwiftTLAMacros

/// Dijkstra's termination detector from EWD 840.
@TLAModel
package struct EWD840Model: Sendable {
    package enum Color: String, TLAValueType {
        case white
        case black

        package static var defaultValue: Self { .white }
    }

    private enum Step: String, CaseIterable {
        case InitiateProbe, PassToken, SendMsg, Deactivate
    }

    package static var spec: TLASpec {
        #spec("EWD840") { scope in
            Extends(.naturals)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = IntRange(0, through: N - 1)
            let colors = SetExpr<Color>.literal(.white, .black)
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                in: Functions(from: Node, to: SetExpr<Bool>.literal(false, true)))
            let color: SharedVariable<[Int: Color]> = scope.sharedVar(in: Functions(from: Node, to: colors))
            let tpos = scope.sharedVar(in: Node)
            let tcolor = scope.sharedVar(initial: Color.black)

            let initiate = Do(Step.InitiateProbe, when: tpos == 0
                && (tcolor == Color.black || color[0] == Color.black)) {
                Assign(tpos, to: N - 1)
                Assign(tcolor, to: Color.white)
                Assign(color[0], to: Color.white)
            }
            initiate

            let pass = Do(Step.PassToken, over: Node) { i in
                When(i != 0 && tpos == i
                    && (!active[i] || color[i] == Color.black || tcolor == Color.black))
                Assign(tpos, to: i - 1)
                Assign(tcolor, to: If(color[i] == Color.black, then: Color.black, else: tcolor))
                Assign(color[i], to: Color.white)
            }
            pass
            WeakFairness(anyOf: [initiate, pass])

            Do(Step.SendMsg, over: Node) { i in
                When(active[i])
                With(Node) { j in
                    When(j != i)
                    Assign(active[j], to: true)
                    If(j > i) {
                        Assign(color[i], to: Color.black)
                    }
                }
            }

            Do(Step.Deactivate, over: Node) { i in
                When(active[i])
                Assign(active[i], to: false)
            }

            let TypeOK = Invariant()
            let TerminationDetection = Invariant()
            let Inv = Invariant()
            let Liveness = Temporal()
            let terminated = ForAll(in: Node) { i in !active[i] }
            let terminationDetected = tpos == 0 && tcolor == Color.white
                && color[0] == Color.white && !active[0]
            TypeOK {
                Functions(from: Node, to: SetExpr<Bool>.literal(false, true)).contains(active)
                    && Functions(from: Node, to: colors).contains(color)
                    && Node.contains(tpos) && colors.contains(tcolor)
            }
            TerminationDetection { !terminationDetected || terminated }
            Inv {
                ForAll(in: Node) { i in tpos >= i || !active[i] }
                    || Exists(in: IntRange(0, through: tpos)) { i in color[i] == Color.black }
                    || tcolor == Color.black
            }
            Liveness(.leadsTo(terminated, terminationDetected))

            let EWD840 = Validation { Bind(N, to: 3) }.checkingDeadlock(false)
            EWD840
        }
    }
}
