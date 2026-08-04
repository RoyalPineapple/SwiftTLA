import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Traffic {
    static var spec: TLASpec {
        TLASpec("Traffic") {
            let light = Var(0)
            Action("next") { light.becomes((light + 1) % 3) }
            Invariant("valid") { light >= 0 && light <= 2 }
        }
    }
}
