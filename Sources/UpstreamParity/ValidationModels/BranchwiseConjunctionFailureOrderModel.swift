import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BranchwiseConjunctionFailureOrderModel: Sendable {
    package enum Step: String, CaseIterable { case pick }

    package static var spec: TLASpec {
        #spec("BranchwiseConjunctionFailureOrderModel") { scope in
            let divisor = scope.sharedVar(initiallyIn: 0...1)
            let modulus = scope.sharedVar(initiallyIn: Set<Int>([-1, 0, 1, 2]))
            let selected = scope.sharedVar(initial: -1)
            let result = scope.sharedVar(initial: 0)
            Do(Step.pick) {
                Either {
                    Assign(selected, to: 0)
                } or: {
                    Assign(selected, to: 1 % modulus)
                }
                Assign(result, to: 1 / divisor)
            }
            let selectionFloor = Invariant("SelectionFloor") { selected >= -1 }
            let resultNonnegative = Invariant("ResultNonnegative") { result >= 0 }
            let divisorNonnegative = Invariant("DivisorNonnegative") { divisor >= 0 }
            selectionFloor
            resultNonnegative
            divisorNonnegative
            let Selected = Validation {}.checking(only: [selectionFloor, resultNonnegative]).checkingDeadlock(false)
            Selected
        }
    }
}
