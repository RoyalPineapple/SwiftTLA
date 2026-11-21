import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct GeneratedScalarConditionalProofModel {
    enum Step: String, CaseIterable { case choose }

    package static var spec: TLASpec {
        #spec("GeneratedScalarConditionalProofModel") { scope in
            let left = scope.sharedVar(in: SetExpr<Int>.literal(2, 4))
            let right = scope.sharedVar(initial: 3)
            let selected = scope.sharedVar(initial: false)
            Do(Step.choose) {
                If(left < right) {
                    Assign(selected, to: true)
                } else: {
                    Assign(selected, to: false)
                }
            }
        }
    }
}
