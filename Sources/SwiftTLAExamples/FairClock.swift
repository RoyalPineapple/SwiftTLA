import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct FairClock {
    var hr = Var(1)

    func tick() {
        (hr < 12) && hr.becomes(hr + 1) ||
        (hr == 12) && hr.becomes(1)
    }

    var validHours: StateExpr { hr >= 1 && hr <= 12 }
    var eventually12: TemporalExpr { hr.leadsTo(hr == 12) }
}
