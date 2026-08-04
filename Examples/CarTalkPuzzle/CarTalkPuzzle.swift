import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct CarTalkPuzzle {
    static var spec: TLASpec {
        TLASpec("CarTalkPuzzle") {
            let stones = Var(0)
            Action("pickTwo") { stones.becomes(stones - 2).when(stones > 1) }
            Invariant("even") { stones % 2 == 0 }
        }
    }
}
