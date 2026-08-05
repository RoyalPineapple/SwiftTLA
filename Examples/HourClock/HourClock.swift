import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClock {
    static var spec: TLASpec {
        TLASpec("HourClock") {
            Extends("Naturals")
            let hr = Var("hr", value: 1)
            Variable(hr, 1)
            Action("HCnxt") {
                (hr != 12) && hr.becomes(hr + 1) ||
                (hr == 12) && hr.becomes(1)
            }
            Invariant("HCini") { hr >= 1 && hr <= 12 }
        }
    }
}
