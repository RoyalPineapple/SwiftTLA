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
            Do(Step.FillSmallJug) { Assign(small, to: 3) }
            Do(Step.FillBigJug) { Assign(big, to: 5) }
            Do(Step.EmptySmallJug) { Assign(small, to: 0) }
            Do(Step.EmptyBigJug) { Assign(big, to: 0) }
            Do(Step.SmallToBig) {
                If(big + small <= 5) {
                    Assign(big, to: big + small)
                    Assign(small, to: 0)
                } else: {
                    Assign(small, to: small - (5 - big))
                    Assign(big, to: 5)
                }
            }
            Do(Step.BigToSmall) {
                If(big + small <= 3) {
                    Assign(small, to: big + small)
                    Assign(big, to: 0)
                } else: {
                    Assign(big, to: big - (3 - small))
                    Assign(small, to: 3)
                }
            }
            TypeOK { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
            NotSolved { big != 4 }
            Validation("Upstream") {}.expect(NotSolved, .violated)
        }
    }
}
