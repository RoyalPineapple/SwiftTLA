import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct FiniteRandomSubsetInitialModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            Extends(.randomization)
            let finiteRandomSubsetInitialModel = Algorithm(label: "FiniteRandomSubsetInitialModel", scoped: { scope in
                let chosen = scope.sharedVar(in: RandomSubset(
                    upTo: 2, from: SetExpr<Int>.literal(1, 2, 3)
                ))
                Do(Step.stay) { Assign(chosen, to: chosen) }
            })
            finiteRandomSubsetInitialModel
        }
    }
}

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

@TLAModel
struct MixedInitialEvaluationModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            Extends(.randomization)
            let mixedInitialEvaluationModel = Algorithm(label: "MixedInitialEvaluationModel", scoped: { scope in
                let limit = scope.sharedVar(in: SetExpr<Int>.literal(-1, 1))
                let chosen = scope.sharedVar(in: RandomSubset(
                    upTo: limit, from: SetExpr<Int>.literal(7)
                ))
                Do(Step.stay) {
                    Assign(limit, to: limit)
                    Assign(chosen, to: chosen)
                }
            })
            mixedInitialEvaluationModel
        }
    }
}

@TLAModel
struct RandomSubsetFailureOrderModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            Extends(.randomization)
            let randomSubsetFailureOrderModel = Algorithm(label: "RandomSubsetFailureOrderModel", scoped: { scope in
                let limit = scope.sharedVar(initial: -1)
                let zero = scope.sharedVar(initial: 0)
                let chosen = scope.sharedVar(in: RandomSubset(
                    upTo: limit, from: SetExpr<Int>.literal(1 / zero)
                ))
                Do(Step.stay) {
                    Assign(limit, to: limit)
                    Assign(zero, to: zero)
                    Assign(chosen, to: chosen)
                }
            })
            randomSubsetFailureOrderModel
        }
    }
}
