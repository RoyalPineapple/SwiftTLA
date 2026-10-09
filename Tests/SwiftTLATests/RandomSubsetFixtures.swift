import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RandomSubsetFunctionModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            Extends(.randomization)
            let randomSubsetFunctionModel = Algorithm(label: "RandomSubsetFunctionModel", scoped: { scope in
                let samples = scope.sharedVar(in: RandomSubset(
                    upTo: 100,
                    from: Functions(from: IntRange(1, through: 30), to: SetExpr<Bool>.literal(false, true))
                ))
                Do(Step.stay) { Assign(samples, to: samples) }
            })
            randomSubsetFunctionModel
        }
    }
}
