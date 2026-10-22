import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct DependentInitializationOutputProofModel {
    enum Step: String, CaseIterable { case finish }

    static var spec: TLASpec {
        #spec("DependentInitializationOutputProofModel") { scope in
            let proof = Algorithm(label: "DependentInitializationOutputProofModel", scoped: { scope in
                let seed = scope.sharedVar(in: 0...1)
                let choice = scope.sharedVar(in: If(seed == 0,
                    then: SetExpr<Int>.literal(0),
                    else: SetExpr<Int>.literal(0, 1)))
                Do(Step.finish) {
                    Assign(choice, to: choice)
                    Stop()
                }
            })
            proof
        }
    }
}
