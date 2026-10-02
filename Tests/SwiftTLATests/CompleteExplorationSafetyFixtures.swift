import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CompleteExplorationSafetyModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("CompleteSafety") { scope in
            let value = scope.sharedVar(in: Set<Int>([0, 10]))
            Do(Step.advance, when: value >= 10 && value < 13) {
                Assign(value, to: value + 1)
            }
            let belowEleven = Invariant()
            belowEleven { value < 11 }
            let belowThirteen = Invariant()
            belowThirteen { value < 13 }
            let completeSafety = Validation(label: "Complete safety") {}
            completeSafety
        }
    }
}
