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

@TLAModel
struct RandomSubsetCountModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            Extends(.randomization)
            let randomSubsetCountModel = Algorithm(label: "RandomSubsetCountModel", scoped: { scope in
                let limit = scope.sharedVar(in: SetExpr<Int>.literal(-1, 0))
                let chosen = scope.sharedVar(in: RandomSubset(
                    upTo: limit, from: SetExpr<Int>.literal(1)
                ))
                Do(Step.stay) {
                    Assign(limit, to: limit)
                    Assign(chosen, to: chosen)
                }
            })
            randomSubsetCountModel
        }
    }
}
