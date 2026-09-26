import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct IndependentAtomicSteps {
    package enum Step: String, CaseIterable { case advance, reset, choose, blocked, rollback }

    package static var spec: TLASpec {
        #spec("IndependentAtomicSteps") { scope in
            let value = scope.sharedVar(initial: 0)
            let copied = scope.sharedVar(initial: 0)
            let ordered = Invariant()
            Do(Step.advance, when: value < 2) {
                Assign(value, to: value + 1)
                Assign(copied, to: value)
                Assert(value <= 2)
            }
            Do(Step.reset, when: value == 2) {
                Assign(value, to: 0)
                Assign(copied, to: value)
            }
            Do(Step.choose, when: value == 0) {
                With(IntRange(1, through: 2)) { selected in
                    Assign(value, to: selected)
                    Assign(copied, to: value)
                }
            }
            Do(Step.blocked, when: false) {
                Assign(value, to: 1 / (value - value))
            }
            Do(Step.rollback) {
                Assign(value, to: 42)
                When(value == 0)
                Assign(copied, to: value)
            }
            ordered { value == copied && value >= 0 && value <= 2 }
            Validation("Complete") {}
        }
    }
}
