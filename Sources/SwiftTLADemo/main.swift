import SwiftTLA
import SwiftTLAMacros

@TLA
struct Clock {
    var hr = Var<Int>("hr", 1)

    func tick() {
        hr.becomes(hr + 1).when(hr <= 11)
        hr.becomes(1).when(hr == 12)
    }
}
