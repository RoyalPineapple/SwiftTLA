import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct CoffeeCanModel: Sendable {
    package struct Can: Hashable, Sendable {
        package let black: Int
        package let white: Int
    }
    package enum Step: String, CaseIterable {
        case PickSameColorWhite, PickSameColorBlack, PickDifferentColor, Termination
    }

    package static var spec: TLASpec {
        #spec("CoffeeCan") { scope in
            Extends(.naturals)
            let MaxBeanCount = scope.parameter(as: Int.self, in: 1...3000)
            Assume(MaxBeanCount >= 1)
            let cans = IntRange(0, through: MaxBeanCount).flatMapping { black in
                IntRange(0, through: MaxBeanCount).mapping { white in
                    Can.expression(black: black, white: white)
                }
            }
            let can = scope.sharedVar(in: cans.filtering { value in
                IntRange(1, through: MaxBeanCount).contains(value.black + value.white)
            })
            let beanCount = can.black + can.white

            Do(Step.PickSameColorWhite) {
                When(beanCount > 1 && can.white >= 2)
                Assign(can.black, to: can.black + 1)
                Assign(can.white, to: can.white - 2)
            }
            Do(Step.PickSameColorBlack) {
                When(beanCount > 1 && can.black >= 2)
                Assign(can.black, to: can.black - 1)
            }
            Do(Step.PickDifferentColor) {
                When(beanCount > 1 && can.black >= 1 && can.white >= 1)
                Assign(can.black, to: can.black - 1)
            }
            let Termination = Do(Step.Termination, when: beanCount == 1) { Skip() }
            Termination
            WeakFairnessNext()

            let TypeInvariant = Invariant()
            TypeInvariant {
                can.black >= 0 && can.black <= MaxBeanCount
                    && can.white >= 0 && can.white <= MaxBeanCount
            }
            let MonotonicDecrease = Temporal()
            let EventuallyTerminates = Temporal()
            let LoopInvariant = Temporal()
            let TerminationHypothesis = Temporal()
            MonotonicDecrease(.alwaysStep(on: can) { before, after in
                after.black + after.white < before.black + before.white
            })
            EventuallyTerminates(.eventually(Termination.enabled))
            LoopInvariant(.alwaysStep(on: can) { before, after in
                (before.white % 2 == 0) == (after.white % 2 == 0)
            })
            TerminationHypothesis(.conditional(can.white % 2 == 0,
                then: .eventually(can.black == 1 && can.white == 0),
                else: .eventually(can.black == 0 && can.white == 1)))

            Validation("CoffeeCan100Beans") { Bind(MaxBeanCount, to: 100) }
            Validation("CoffeeCan1000Beans") { Bind(MaxBeanCount, to: 1000) }
            Validation("CoffeeCan3000Beans") { Bind(MaxBeanCount, to: 3000) }
            Validation("APCoffeeCan") { Bind(MaxBeanCount, to: 5) }.checking(only: [TypeInvariant])
        }
    }
}
