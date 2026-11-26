// Starting at zero, each step adds two and preserves evenness.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/LearnProofs/AddTwo.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct AddTwoModel: Sendable {
    package enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("AddTwo") { scope in
            Extends(.naturals)
            let x = scope.sharedVar(initial: 0)
            Do(Step.next) { x += 2 }
            Invariant("TypeOK") { x >= 0 }
            Invariant("Even") { x % 2 == 0 }
        }
    }
}
