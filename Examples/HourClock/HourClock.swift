import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct HourClock {
    static var spec: TLASpec {
        TLASpec("HourClock") {
            let hr = Var(1)
            Action("tick") {
                (hr < 12) && hr.becomes(hr + 1) ||
                (hr == 12) && hr.becomes(1)
            }
            Invariant("valid") { hr >= 1 && hr <= 12 }
        }
    }
}
