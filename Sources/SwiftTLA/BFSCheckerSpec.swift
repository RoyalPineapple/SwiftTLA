/// Canonical BFS checker lifecycle model (bootstrap source of truth).
///
/// Compose with a user spec via `extending` / `ModelChecker.checkComposed`
/// to model-check "checker ⋊ user". Production exploration uses plain BFS
/// in `ModelChecker`; this spec is for self-proof and composition.
extension TLASpec {
    /// Bounded BFS lifecycle: phase, processed, queued.
    /// - phase 0 = exploring, 1 = complete, 2 = violated, 3 = deadlocked
    public static func bfsChecker(maxStates: Int = 20) -> TLASpec {
        let phase = Var<Int>("phase")
        let processed = Var<Int>("processed")
        let queued = Var<Int>("queued")

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

            Action("Violate") {
                (phase == 0) && (queued == 0)
                    && phase.becomes(2)
            }

            Action("Deadlock") {
                (phase == 0) && (processed >= queued) && (queued > 0) && (processed < maxStates)
                    && phase.becomes(3)
            }

            Invariant("PhaseValid") { phase >= 0 && phase <= 3 }
            Invariant("ProcessedWithinLimit") { processed <= maxStates }
        }
    }
}

/// Types produced by `@TLAModel` conform so composition can take the type.
public protocol TLAModelType {
    static var spec: TLASpec { get }
}
