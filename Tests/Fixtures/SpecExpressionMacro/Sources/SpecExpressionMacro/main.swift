import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct Counter {
    static var spec: TLASpec {
        #spec("Counter") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }
}

var counter = Counter()
let result = try counter.apply(.advance)
precondition(result.after.value == 1)
