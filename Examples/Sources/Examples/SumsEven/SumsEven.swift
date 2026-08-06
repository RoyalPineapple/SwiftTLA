import SwiftTLA

public struct SumsEven {
    public static var spec: TLASpec {
        TLASpec("sums_even") {
            Extends("Naturals")
            let sum = Var("sum", value: 0)
            Variable(sum, 0)
            Action("Double") { sum.becomes(sum + 2).when(sum >= 0) }
            Invariant("Even") { sum % 2 == 0 }
            Theorem("EvenAddition == \\A x \\in Nat : x + x = 2 * x")
        }
    }
}
