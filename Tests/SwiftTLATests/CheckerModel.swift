import SwiftTLA

/// Creates a bounded BFS checker spec.  Compose with any user spec via
/// `extending()` to model "checker checking that spec".
///
/// Variables: phase (0=exploring,1=complete,3=deadlocked),
///            processed (states finished), queued (states discovered).
/// Bounded by the maxStates parameter — the checker stops when
/// processed >= maxStates.
public func createCheckerSpec(maxStates: Int = 20) -> TLASpec {
    let phase = Var("phase", value: 0)
    let processed = Var("processed", value: 0)
    let queued = Var("queued", value: 1)

    return TLASpec("BFSChecker") {
        Variable(phase, 0)
        Variable(processed, 0)
        Variable(queued, 1)

        Action("StepDiscover") {
            (phase == 0) && (processed < queued) && (processed < maxStates)
            && processed.becomes(processed + 1)
            && queued.becomes(queued + 1)
        }

        Action("StepNoNew") {
            (phase == 0) && (processed < queued) && (processed < maxStates)
            && processed.becomes(processed + 1)
            && queued.stays
        }

        Action("Complete") {
            (phase == 0) && ((processed >= queued) || (processed >= maxStates))
            && phase.becomes(1)
        }

        Action("Deadlock") {
            (phase == 0) && (processed >= queued) && (queued > 0)
            && phase.becomes(3)
        }

        Invariant("PhaseValid") { phase >= 0 && phase <= 3 }
        Invariant("ProcessedWithinLimit") { processed <= maxStates }
    }
}
