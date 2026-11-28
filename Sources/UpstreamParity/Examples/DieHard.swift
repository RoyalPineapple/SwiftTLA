// Two water jugs can be filled, emptied, or poured into each other to measure a target quantity.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/DieHard/DieHard.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DieHardModel: Sendable {
    package enum Step: String, CaseIterable {
        case fillSmallJug = "FillSmallJug"
        case fillBigJug = "FillBigJug"
        case emptySmallJug = "EmptySmallJug"
        case emptyBigJug = "EmptyBigJug"
        case smallToBig = "SmallToBig"
        case bigToSmall = "BigToSmall"
    }

    package static var spec: TLASpec {
        #spec("DieHard") { scope in
            Extends(.naturals)
            let big = scope.sharedVar(initial: 0)
            let small = scope.sharedVar(initial: 0)
            Do(Step.fillSmallJug) { small.set(3) }
            Do(Step.fillBigJug) { big.set(5) }
            Do(Step.emptySmallJug) { small.set(0) }
            Do(Step.emptyBigJug) { big.set(0) }
            Do(Step.smallToBig) {
                If(big + small <= 5) {
                    big += small
                    small.set(0)
                } else: {
                    small.set(small - (5 - big))
                    big.set(5)
                }
            }
            Do(Step.bigToSmall) {
                If(big + small <= 3) {
                    small.set(big + small)
                    big.set(0)
                } else: {
                    big.set(big - (3 - small))
                    small.set(3)
                }
            }
            Invariant("TypeOK") {
                (0...5).contains(big)
                (0...3).contains(small)
            }
            let notSolved = Invariant("NotSolved")
            notSolved { big != 4 }
            Validation("Upstream") {}.expect(notSolved, .violated)
        }
    }
}
