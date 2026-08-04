import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct DieHard {
    static var spec: TLASpec {
        TLASpec("DieHard") {
            let big = Var(0)
            let small = Var(0)

            Action("FillSmallJug")  { small.becomes(3) && big.stays }
            Action("FillBigJug")    { big.becomes(5) && small.stays }
            Action("EmptySmallJug") { small.becomes(0) && big.stays }
            Action("EmptyBigJug")   { big.becomes(0) && small.stays }
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
