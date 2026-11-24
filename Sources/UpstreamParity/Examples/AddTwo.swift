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
