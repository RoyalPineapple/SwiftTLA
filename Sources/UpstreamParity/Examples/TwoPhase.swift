import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/TwoPhase/MCTwoPhase.tla
@TLAModel
package struct TwoPhaseModel: Sendable {
    package enum Step: String, CaseIterable { case ProducerStep, ConsumerStep }

    package static var spec: TLASpec {
        #spec("TwoPhase") { scope in
            let p = scope.sharedVar(initial: 0)
            let c = scope.sharedVar(initial: 0)
            let x = scope.sharedVar(initial: 0)
            let Inv = Invariant()

            Do(Step.ProducerStep) {
                When(p == c)
                Assign(p, to: (p + 1) % 2)
                Assign(x, to: x)
            }
            Do(Step.ConsumerStep) {
                When(p != c)
                Assign(c, to: (c + 1) % 2)
                Assign(x, to: x)
            }

            Inv { SetExpr<Int>.literal(0, 1).contains(p) && SetExpr<Int>.literal(0, 1).contains(c) }
            Validation("MCTwoPhase") {}
        }
    }
}
