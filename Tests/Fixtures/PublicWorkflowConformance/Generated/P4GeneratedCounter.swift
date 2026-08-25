import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct P4GeneratedCounter {
    public static var spec: TLASpec {
        #spec("P4GeneratedCounter") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }

}

@TLAModel
public struct P4GeneratedCounterIntentionalMismatch {
    public static var spec: TLASpec {
        #spec("P4GeneratedCounterIntentionalMismatch") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }

}
