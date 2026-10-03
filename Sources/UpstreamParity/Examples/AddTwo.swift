import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct AddTwoModel: Sendable {
    package enum Step: String, CaseIterable { case Next }

    package static var spec: TLASpec {
        #spec("AddTwo") { scope in
            Extends(.naturals)
            let x = scope.sharedVar(initial: 0)
            let TypeOK = Invariant()
            let Even = Invariant()
            Do(Step.Next) { Assign(x, to: x + 2) }
            TypeOK { x >= 0 }
            Even { x % 2 == 0 }
        }
    }
}
