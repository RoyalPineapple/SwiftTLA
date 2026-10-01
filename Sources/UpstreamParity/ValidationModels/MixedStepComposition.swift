import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct MixedStepComposition {
    package enum Step: String, CaseIterable { case advance, reset }

    package static var spec: TLASpec {
        #spec("MixedStepComposition") { scope in
            let value = scope.sharedVar(initial: 0)
            Algorithm("Advance") {
                Do(Step.advance, when: value < 2) {
                    Assign(value, to: value + 1)
                    Goto(Step.advance)
                }
            }
            Do(Step.reset, when: value == 1) {
                Assign(value, to: 0)
            }
            Validation("Complete") {}.expectDeadlock(.violated)
        }
    }
}
