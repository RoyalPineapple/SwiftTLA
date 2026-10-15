import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SignedDivisionOutputModel: Sendable {
    enum Step: String, CaseIterable { case divide }

    static var spec: TLASpec {
        #spec("SignedDivisionOutputModel") { scope in
            let quotient = scope.sharedVar(initial: 0)
            Do(Step.divide) {
                Assign(quotient, to: 5 / -2)
            }
        }
    }
}
