import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct BoundedCounter {
    var x = Var(0)
    func inc() { x.becomes(x + 1).when(x < 3) }
    func dec() { x.becomes(x - 1).when(x > -3) }
    var bounded: StateExpr { x >= -3 && x <= 3 }
}
