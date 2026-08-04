import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Fibonacci {
    static var spec: TLASpec {
        TLASpec("Fibonacci") {
            let a = Var(0)
            let b = Var(1)
            let n = Var(0)
            Action("step") {
                a.becomes(b).when(n < 5) &&
                b.becomes(a + b).when(n < 5) &&
                n.becomes(n + 1).when(n < 5)
            }
        }
    }
}
