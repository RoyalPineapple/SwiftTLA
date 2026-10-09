import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct CheckingPostconditionModel: Sendable {
    private enum Step: String, CaseIterable { case advance }

    package static var spec: TLASpec {
        #spec { scope in
            let count = scope.sharedVar(initial: 0)
            Do(Step.advance, when: count < 2) {
                Assign(count, to: count + 1)
            }
            let Complete = Validation {}.checkingDeadlock(false)
                .postcondition(scope.checkingDiameter == 3, name: "ExpectedDiameter")
            Complete
            let Rejected = Validation {}.checkingDeadlock(false)
                .postcondition(scope.checkingDiameter == 4, name: "RejectedDiameter", expecting: .violated)
            Rejected
        }
    }
}
