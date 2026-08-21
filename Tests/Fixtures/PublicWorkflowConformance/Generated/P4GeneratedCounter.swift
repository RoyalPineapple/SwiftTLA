import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct P4GeneratedCounter {
    public static var spec: TLASpec {
        #spec("P4GeneratedCounter") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }

    @TLAObservable
    public final class Observable {}

    @TLAActor
    public actor Actor {}
}

@TLAModel
public struct P4GeneratedCounterIntentionalMismatch {
    public static var spec: TLASpec {
        #spec("P4GeneratedCounterIntentionalMismatch") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }

    @TLAObservable
    public final class Observable {}

    @TLAActor
    public actor Actor {}

}
