import SwiftTLA

let hr = Var<Int>("hr")
let hourClock = TLASpec("HourClock") {
    Variable(hr, 1)
    Act("Tick") {
        let inc: ActionExpr = (hr >= 1) && (hr <= 11) && (hr.next == hr + 1)
        let wrap: ActionExpr = (hr == 12) && (hr.next == 1)
        inc || wrap
    }
}
