import SwiftTLA

extension Example {
    public static let dieHardTypeOK = Entry(
        id: "DieHard/TypeOK",
        upstreamSpec: "DieHard",
        upstreamModule: "specifications/DieHard/DieHard.tla",
        upstreamCfg: nil,
        expectedDistinct: 16,
        expectedResult: "success",
        spec: {
            let big = Var<Int>("big", value: 0)
            let small = Var<Int>("small", value: 0)
            return TLASpec("DieHard") {
                Extends("Naturals")
                Variable(big, 0)
                Variable(small, 0)
                Invariant("TypeOK") { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
                Action("FillSmallJug") { small.becomes(3) }
                Action("FillBigJug") { big.becomes(5) }
                Action("EmptySmallJug") { small.becomes(0) }
                Action("EmptyBigJug") { big.becomes(0) }
                Action("SmallToBig") {
                    (big + small <= 5) && big.becomes(big + small) && small.becomes(0) ||
                    (big + small > 5) && big.becomes(5) && small.becomes(small - (5 - big))
                }
                Action("BigToSmall") {
                    (big + small <= 3) && small.becomes(big + small) && big.becomes(0) ||
                    (big + small > 3) && small.becomes(3) && big.becomes(big - (3 - small))
                }
            }
        }(),
        notes: "Upstream cfg adds NotSolved (intentional fail). TypeOK-only = 16 both sides.",
        matchesUpstreamTLC: true
    )

}
