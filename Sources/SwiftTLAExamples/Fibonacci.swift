import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Fibonacci {
    var a = Var(0)
    var b = Var(1)
    var n = Var(0)

    func step() {
        a.becomes(b).when(n < 5)
        b.becomes(a + b).when(n < 5)
        n.becomes(n + 1).when(n < 5)
    }
}
