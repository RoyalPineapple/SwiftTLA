import SwiftTLA

/// The checker's own control flow as a verified state machine.
/// Explores a spec by maintaining queue, visited, and stepping through states.
@TLAModel
public struct CheckerMachine {
    static var spec: TLASpec {
        TLASpec("CheckerMachine") {
            // Abstract: we model the checker's progress through states 0..N-1
            let processed = Var<Int>("processed", value: 0)   // states explored so far
            let discovered = Var<Int>("discovered", value: 1) // states in queue+visited
            let phase = Var<Int>("phase", value: 0)           // 0=running, 1=ok, 2=violation, 3=deadlock

            Variable(processed, 0)
            Variable(discovered, 1)
            Variable(phase, 0)

            // Process one state: advance head, optionally discover successor
            Action("Explore") {
                (phase == 0) && (processed < discovered) &&
                processed.becomes(processed + 1) &&
                discovered.becomes(discovered + 1)  // simplified: always discovers successor
            }

            // Queue empty: checker terminates with OK
            Action("Finish") {
                (phase == 0) && (processed >= discovered) &&
                phase.becomes(1)
            }

            // Invariant violation detected (modeled as processed exceeding bound)
            Action("Violate") {
                (phase == 0) && (processed > 5) &&
                phase.becomes(2)
            }

            Invariant("TypeOK") { processed >= 0 && discovered >= 0 && phase >= 0 && phase <= 3 }
            Invariant("ExploredWithinDiscovered") { processed <= discovered }
            Invariant("PhaseValid") { phase >= 0 && phase <= 3 }
        }
    }
}
