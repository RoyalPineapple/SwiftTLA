import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct TwoPhaseCommit {
    public static var spec = TLASpec("TwoPhaseCommit") {
        let phase = Var(0)
        let votes = Var(0)
        let total = 3

        Action("propose") { phase.becomes(1).when(phase == 0) }
        Action("voteYes") { votes.becomes(votes + 1).when(phase == 1) }
        Action("abort")     { phase.becomes(3).when(phase == 1 && votes < total) }
        Action("commit")    { phase.becomes(2).when(phase == 1 && votes == total) }
        Action("reset")     { phase.becomes(0).when(phase >= 2) && votes.becomes(0) }

        Invariant("finality") { !(phase == 2 && votes < total) }
    }
}
