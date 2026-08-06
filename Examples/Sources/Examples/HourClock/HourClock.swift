import SwiftTLA

public struct HourClock {
    public static var spec: TLASpec {
        TLASpec("HourClock") {
            Extends("Naturals")
            let hr = Var("hr", value: 1)
            // Upstream SpecifyingSystems/HourClock: hr \in 1..12
            Variable(hr, in: 1...12)
            Action("HCnxt") {
                (hr != 12) && hr.becomes(hr + 1) ||
                (hr == 12) && hr.becomes(1)
            }
            Invariant("HCini") { hr >= 1 && hr <= 12 }
        }
    }
}
