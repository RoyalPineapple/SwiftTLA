import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct SumsEven {
    static var spec: TLASpec {
        TLASpec("sums_even") {
            let sum = Var("sum", 0)
            Variable(sum, 0)
            Action("Double") { sum.becomes(sum + 2).when(sum >= 0) }
            Invariant("Even") { sum % 2 == 0 }
        }
    }
}
