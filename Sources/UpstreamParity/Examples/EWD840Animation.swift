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
        case animInitiateProbe = "AnimInitiateProbe"
        case animPassToken = "AnimPassToken"
        case animSendMsg = "AnimSendMsg"
        case animDeactivate = "AnimDeactivate"
    }

    package static var spec: TLASpec {
        #spec("EWD840_anim") { scope in
            Extends(.naturals, .tlc)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = IntRange(0, through: N - 1)
            let colors = SetExpr<Color>.literal(.white, .black)
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                initiallyIn: Functions(from: Node, to: Bool.all))
            let color: SharedVariable<[Int: Color]> = scope.sharedVar(initiallyIn: Functions(from: Node, to: colors))
            let tpos = scope.sharedVar(initial: N - 1)
            let tcolor = scope.sharedVar(initial: Color.black)
            let history = scope.sharedVar(initial: Triple(first: 0, second: 0, third: "init"))

            let initiate = Do(Step.animInitiateProbe, when: tpos == 0
                && (tcolor == Color.black || color[0] == Color.black)) {
                tpos.set(N - 1)
                tcolor.set(Color.white)
                color[0].set(Color.white)
                history.set(Triple.literal(history.first(), history.second(), "InitiateProbe"))
            }
            initiate

            let pass = Do(Step.animPassToken, over: Node) { i in
                When(i != 0 && tpos == i
                    && (!active[i] || color[i] == Color.black || tcolor == Color.black))
                tpos.set(i - 1)
                tcolor.set(If(color[i] == Color.black, then: Color.black, else: tcolor))
                color[i].set(Color.white)
                history.set(Triple.literal(history.first(), history.second(), "PassToken"))
            }
            pass
            WeakFairness(anyOf: [initiate, pass])

            Do(Step.animSendMsg, over: Node) { i in
                When(active[i])
                With(Node) { j in
                    When(j != i)
                    active[j].set(true)
                    If(j > i) {
                        color[i].set(Color.black)
                    }
                    history.set(Triple.literal(i, j, "SendMsg"))
                }
            }

            Do(Step.animDeactivate, over: Node) { i in
                When(active[i])
                active[i].set(false)
                history.set(Triple.literal(history.first(), history.second(), "Deactivate"))
            }

            let terminationDetected = tpos == 0 && tcolor == Color.white
                && color[0] == Color.white && !active[0]
            let animInv = Invariant("AnimInv") { !terminationDetected || scope.checkingLevel < 20 }
            animInv

            Validation("EWD840_anim") { Bind(N, to: 9) }
                .checking(only: [animInv])
                .checkingDeadlock(false)
                .simulating(traces: 100)
                .expect(animInv, .violated)
        }
    }
}
