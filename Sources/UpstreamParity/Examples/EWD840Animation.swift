import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct EWD840AnimationModel: Sendable {
    package enum Color: String, TLAValueType {
        case white
        case black

        package static var defaultValue: Self { .white }
    }

    private enum Step: String, CaseIterable {
        case AnimInitiateProbe, AnimPassToken, AnimSendMsg, AnimDeactivate
    }

    package static var spec: TLASpec {
        #spec("EWD840_anim") { scope in
            Extends(.naturals, .tlc)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = IntRange(0, through: N - 1)
            let colors = SetExpr<Color>.literal(.white, .black)
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                in: Functions(from: Node, to: SetExpr<Bool>.literal(false, true)))
            let color: SharedVariable<[Int: Color]> = scope.sharedVar(in: Functions(from: Node, to: colors))
            let tpos = scope.sharedVar(initial: N - 1)
            let tcolor = scope.sharedVar(initial: Color.black)
            let history = scope.sharedVar(initial: Triple(first: 0, second: 0, third: "init"))

            let initiate = Do(Step.AnimInitiateProbe, when: tpos == 0
                && (tcolor == Color.black || color[0] == Color.black)) {
                Assign(tpos, to: N - 1)
                Assign(tcolor, to: Color.white)
                Assign(color[0], to: Color.white)
                Assign(history, to: Triple.literal(history.first(), history.second(), "InitiateProbe"))
            }
            initiate

            let pass = Do(Step.AnimPassToken, over: Node) { i in
                When(i != 0 && tpos == i
                    && (!active[i] || color[i] == Color.black || tcolor == Color.black))
                Assign(tpos, to: i - 1)
                Assign(tcolor, to: If(color[i] == Color.black, then: Color.black, else: tcolor))
                Assign(color[i], to: Color.white)
                Assign(history, to: Triple.literal(history.first(), history.second(), "PassToken"))
            }
            pass
            WeakFairness(anyOf: [initiate, pass])

            Do(Step.AnimSendMsg, over: Node) { i in
                When(active[i])
                With(Node) { j in
                    When(j != i)
                    Assign(active[j], to: true)
                    If(j > i) {
                        Assign(color[i], to: Color.black)
                    }
                    Assign(history, to: Triple.literal(i, j, "SendMsg"))
                }
            }

            Do(Step.AnimDeactivate, over: Node) { i in
                When(active[i])
                Assign(active[i], to: false)
                Assign(history, to: Triple.literal(history.first(), history.second(), "Deactivate"))
            }

            let AnimInv = Invariant()
            let terminationDetected = tpos == 0 && tcolor == Color.white
                && color[0] == Color.white && !active[0]
            AnimInv { !terminationDetected || scope.checkingLevel < 20 }
        }
    }
}
