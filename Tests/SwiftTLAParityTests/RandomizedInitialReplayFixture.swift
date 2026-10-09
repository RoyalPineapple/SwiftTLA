import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RandomizedInitialReplay {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("RandomizedInitialReplay") { scope in
            Extends(.randomization)
            let x = scope.sharedVar(in: RandomSubset(upTo: 1, from: SetExpr<Int>.literal(0, 1)))
            Do(Step.stay) { Assign(x, to: x) }
        }
    }
}
