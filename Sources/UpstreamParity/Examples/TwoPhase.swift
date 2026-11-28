// The two-phase handshake coordinates a producer and a consumer.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/TwoPhase/TwoPhase.tla

import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/TwoPhase/MCTwoPhase.tla
@TLAModel
package struct TwoPhaseModel: Sendable {
    package enum Step: String, CaseIterable {
        case produce = "ProducerStep"
        case consume = "ConsumerStep"
    }

    package static var spec: TLASpec {
        #spec("TwoPhase") { scope in
            let p = scope.sharedVar(initial: 0)
            let c = scope.sharedVar(initial: 0)
            let x = scope.sharedVar(initial: 0)

            Do(Step.produce, when: p == c) {
                p.set((p + 1) % 2)
                x.set(x)
            }
            Do(Step.consume, when: p != c) {
                c.set((c + 1) % 2)
                x.set(x)
            }

            Invariant("Inv") {
                let phases = SetExpr<Int>.literal(0, 1)
                phases.contains(p)
                phases.contains(c)
            }
            Validation("MCTwoPhase") {}
        }
    }
}
