import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct SingleLaneBridge {
    static var spec: TLASpec {
        TLASpec("SingleLaneBridge") {
            Extends("Naturals")
            let x = Var<Int>("x", value: 0)
            Variable(x, 0)
            Action("step") { x.becomes(x + 1).when(x < 10) }
            Invariant("ok") { x >= 0 }
        }
    }
}
