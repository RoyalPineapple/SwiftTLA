import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedGuardedChoiceProofModel {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("GeneratedGuardedChoiceProofModel") { scope in
            let selected = scope.sharedVar(initial: 0)
            let choose = Do(Step.choose) {
                When(selected == 0)
                Choose(1...2) { value in
                    Assign(selected, to: value.expr)
                }
            }
            choose
        }
    }
}
