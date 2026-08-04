import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct BoundedCounter {
    static var spec: TLASpec {
        TLASpec("BoundedCounter") {
            let x = Var(0)
            Action("inc") { x.becomes(x + 1).when(x < 3) }
            Action("dec") { x.becomes(x - 1).when(x > -3) }
            Invariant("bounded") { x >= -3 && x <= 3 }
        }
    }
}
