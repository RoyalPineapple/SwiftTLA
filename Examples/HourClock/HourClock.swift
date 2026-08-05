import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct HourClock {
    static var spec: TLASpec {
        TLASpec("HourClock") {
            let hr = Var("hr", 1)
            Variable(hr, 1)

            Action("Tick") {
                (hr < 12) && hr.becomes(hr + 1) ||
                (hr == 12) && hr.becomes(1)
            }
            Invariant("ValidHours") { hr >= 1 && hr <= 12 }
        }
    }
}
