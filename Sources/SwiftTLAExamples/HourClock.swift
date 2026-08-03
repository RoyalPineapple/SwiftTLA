import SwiftTLA
import SwiftTLAMacros

let hr = Var<Int>("hr")

#VerifiedStateMachine {
    Variable(hr, 1)
    Act("Tick") {
        let increment: ActionExpr = (hr >= 1) && (hr <= 11) && (next(hr) == hr + 1)
        let wrap: ActionExpr = (hr == 12) && (next(hr) == 1)
        increment || wrap
    }
}
