import SwiftTLA

public enum HourClockSpec {
    public static let hr = Var<Int>("hr")
    public static let spec = TLASpec("HourClock") {
        Variable(hr, 1)
        Act("Tick") {
            let increment: ActionExpr = (hr >= 1) && (hr <= 11) && (hr.next == hr + 1)
            let wrap: ActionExpr = (hr == 12) && (hr.next == 1)
            increment || wrap
        }
    }
    public static let expectedStates = 12
}
