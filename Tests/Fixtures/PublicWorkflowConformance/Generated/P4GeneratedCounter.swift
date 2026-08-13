import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct P4GeneratedCounter {
    public init() {}

    public static var spec: TLASpec {
        TLASpec("P4GeneratedCounter") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
    }

    @TLAObservable
    public final class Observable {}

    @TLAActor
    public actor Actor {
        public init() {}
    }
}

@TLAModel
public struct P4GeneratedCounterIntentionalMismatch {
    public static var spec: TLASpec {
        TLASpec("P4GeneratedCounterIntentionalMismatch") {
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

    public static func intentionalMismatchActionOutcome(
        actionName: String,
        in state: [String: TLAValue]
    ) -> SpecRuntime.RuntimeActionOutcome {
        switch runtime.generatedActionOutcome(actionName: actionName, in: state) {
        case .enabled(let actionName, _):
            return .enabled(actionName: actionName, successors: [["value": .int(2)]])
        case let outcome:
            return outcome
        }
    }
}
