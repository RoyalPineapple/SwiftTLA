import SwiftTLA
import SwiftTLAMacros

/// Checked lifecycle model for the BFS checker (bootstrap).
/// Bound `maxStates = 20` baked in so `@TLAModel` can parse literals.
/// For dynamic bounds use `TLASpec.bfsChecker(maxStates:)`.
@TLAModel
public struct BFSChecker {
    public static var spec: TLASpec {
        TLASpec("BFSChecker") {
            let phase = Var<Int>("phase")
            let processed = Var<Int>("processed")
            let queued = Var<Int>("queued", value: 1)
            Variable(phase, 0)
            Variable(processed, 0)
            Variable(queued, 1)

            Action("StepDiscover") {
                (phase == 0) && (processed < queued) && (processed < 20)
                    && processed.becomes(processed + 1)
                    && queued.becomes(queued + 1)
            }

            Action("StepNoNew") {
                (phase == 0) && (processed < queued) && (processed < 20)
                    && processed.becomes(processed + 1)
                    && queued.stays
            }

            Action("Complete") {
                (phase == 0) && ((processed >= queued) || (processed >= 20))
                    && phase.becomes(1)
            }

            Action("Violate") {
                (phase == 0) && (queued == 0)
                    && phase.becomes(2)
            }

            Action("Deadlock") {
                (phase == 0) && (processed >= queued) && (queued > 0) && (processed < 20)
                    && phase.becomes(3)
            }

            Invariant("PhaseValid") { phase >= 0 && phase <= 3 }
            Invariant("ProcessedWithinLimit") { processed <= 20 }
        }
    }
}
