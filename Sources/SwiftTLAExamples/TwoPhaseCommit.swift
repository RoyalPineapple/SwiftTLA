import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct TwoPhaseCommit {
    static var spec: TLASpec {
        TLASpec("TwoPhaseCommit") {
            let phase = Var(0)
            let votes = Var(0)
            Action("propose") { phase.becomes(1).when(phase == 0) }
            Action("voteYes") { votes.becomes(votes + 1).when(phase == 1) }
            Action("abort")   { phase.becomes(3).when(phase == 1) }
            Action("commit")  { phase.becomes(2).when(phase == 1) }
            Action("reset")   { phase.becomes(0).when(phase >= 2) && votes.becomes(0) }
        }
    }
}
