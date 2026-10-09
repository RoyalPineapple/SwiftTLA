import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CheckingLevelInvariantModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("CheckingLevelInvariantModel") { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.advance) {
                When(value < 2)
                Assign(value, to: value + 1)
            }
            Invariant("BeforeThirdState") { scope.checkingLevel < 3 }
        }
    }
}
