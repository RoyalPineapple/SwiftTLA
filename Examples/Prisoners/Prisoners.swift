import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct Prisoners {
    static var spec: TLASpec {
        TLASpec("Prisoners") {
            Extends("Naturals")
            let bulb = Var<Int>("bulb", value: 0); let count = Var<Int>("count", value: 0)
            Variable(bulb, 0); Variable(count, 0)
            Action("P0") { (bulb==1) && bulb.becomes(0) && count.becomes(count+1) }
            Action("P1") { (bulb==0) && bulb.becomes(1) }
            Invariant("OK") { count >= 0 }
        }
    }
}
