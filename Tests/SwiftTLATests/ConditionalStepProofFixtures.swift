import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConditionalStepProofModel {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("ConditionalStepProofModel") {
            let algorithm = Algorithm(label: "ConditionalStepProofModel", scoped: { scope in
                let chooseFirst = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
                let value = scope.sharedVar(initial: 0)
                Do(Step.choose) {
                    If(chooseFirst) {
                        Assign(value, to: 1)
                    } else: {
                        Assign(value, to: 2)
                    }
                }
            })
            algorithm
        }
    }
}
