// Example ID: generated-machine-bounded-model

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundedCounter {
    static var spec: TLASpec {
        TLASpec("BoundedCounter") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }
}
