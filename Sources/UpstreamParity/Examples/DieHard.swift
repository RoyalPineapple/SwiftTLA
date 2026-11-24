import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DieHardModel: Sendable {
    package enum Step: String, CaseIterable {
        case FillSmallJug, FillBigJug, EmptySmallJug, EmptyBigJug, SmallToBig, BigToSmall
    }

    package static var spec: TLASpec {
        #spec("DieHard") { scope in
            Extends(.naturals)
            let big = scope.sharedVar(initial: 0)
            let small = scope.sharedVar(initial: 0)
            let TypeOK = Invariant()
            let NotSolved = Invariant()
            Do(Step.FillSmallJug) { small.set(3) }
            Do(Step.FillBigJug) { big.set(5) }
            Do(Step.EmptySmallJug) { small.set(0) }
            Do(Step.EmptyBigJug) { big.set(0) }
            Do(Step.SmallToBig) {
                If(big + small <= 5) {
                    big += small
                    small.set(0)
                } else: {
                    small.set(small - (5 - big))
                    big.set(5)
                }
            }
            Do(Step.BigToSmall) {
                If(big + small <= 3) {
                    small.set(big + small)
                    big.set(0)
                } else: {
                    big.set(big - (3 - small))
                    small.set(3)
                }
            }
            TypeOK { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
            NotSolved { big != 4 }
            let Upstream = Validation {}.expect(NotSolved, .violated)
            Upstream
        }
    }
}
