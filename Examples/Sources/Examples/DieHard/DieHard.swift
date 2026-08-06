import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct DieHard {
    static var spec: TLASpec {
        TLASpec("DieHard") {
            Extends("Naturals")
            let big = Var("big", value: 0)
            let small = Var("small", value: 0)
            Variable(big, 0)
            Variable(small, 0)
            Definition("Min(m,n) == IF m < n THEN m ELSE n")
            Invariant("TypeOK") { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
            Action("FillSmallJug")  { small.becomes(3) }
            Action("FillBigJug")    { big.becomes(5) }
            Action("EmptySmallJug") { small.becomes(0) }
            Action("EmptyBigJug")   { big.becomes(0) }
            Action("SmallToBig") {
                (big + small <= 5) && big.becomes(big + small) && small.becomes(0) ||
                (big + small > 5)  && big.becomes(5) && small.becomes(small - (5 - big))
            }
            Action("BigToSmall") {
                (big + small <= 3) && small.becomes(big + small) && big.becomes(0) ||
                (big + small > 3)  && small.becomes(3) && big.becomes(big - (3 - small))
            }
        }
    }
}
