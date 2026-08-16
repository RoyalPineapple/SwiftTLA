import SwiftTLA
import SwiftTLAMacros

/// Bounded external-admission witness for PlusCal simultaneous assignment.
/// Both right-hand sides must read the pre-state before either update commits.
@TLAModel
public struct K3SimultaneousAssignmentWitness {
    public static var spec: TLASpec {
        #spec("K3SimultaneousAssignmentWitness") {
            Algorithm("K3SimultaneousAssignmentWitness") {
                let left = SharedVar(initial: 1)
                let right = SharedVar(initial: 2)

                Do("swap") {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            }
        }
    }
}
