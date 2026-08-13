import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct P4GeneratedCounter {
    public static var spec: TLASpec {
        TLASpec("P4GeneratedCounter") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("advance") { value.becomes(value + 1).when(value < 1) }
            Invariant("withinBounds") { value >= 0 && value <= 1 }
        }
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

    public static func intentionalMismatchActionOutcome(
        actionName: String,
        in state: [String: TLAValue]
    ) -> SpecRuntime.RuntimeActionOutcome {
        switch generatedActionOutcome(actionName: actionName, in: state) {
        case .enabled(let actionName, _):
            return .enabled(actionName: actionName, successors: [["value": .int(2)]])
        case let outcome:
            return outcome
        }
    }
}
