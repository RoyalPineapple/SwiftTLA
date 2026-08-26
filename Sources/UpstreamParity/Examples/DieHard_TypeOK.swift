import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DieHardModel: Sendable {
    package static var spec: TLASpec {
        #spec("DieHard") { scope in
            Extends(.naturals)
            let big = scope.sharedVar("big", initial: 0)
            let small = scope.sharedVar("small", initial: 0)
            Invariant("TypeOK") { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
            SwiftTLA.Action("FillSmallJug") { small.becomes(3) }
            SwiftTLA.Action("FillBigJug") { big.becomes(5) }
            SwiftTLA.Action("EmptySmallJug") { small.becomes(0) }
            SwiftTLA.Action("EmptyBigJug") { big.becomes(0) }
            SwiftTLA.Action("SmallToBig") {
                (big + small <= 5) && big.becomes(big + small) && small.becomes(0) ||
                (big + small > 5) && big.becomes(5) && small.becomes(small - (5 - big))
            }
            SwiftTLA.Action("BigToSmall") {
                (big + small <= 3) && small.becomes(big + small) && big.becomes(0) ||
                (big + small > 3) && small.becomes(3) && big.becomes(big - (3 - small))
            }
        }
    }
}

extension Example {
    package static let dieHardTypeOK = Entry(
        id: "DieHard/TypeOK",
        upstreamSpec: "DieHard",
        upstreamModule: "specifications/DieHard/DieHard.tla",
        upstreamCfg: nil,
        expectedDistinct: 16,
        maximumStateLimit: 50_000,
        spec: DieHardModel.spec,
        notes: "Upstream cfg adds NotSolved (intentional fail). TypeOK-only = 16 both sides.",
    )
}
