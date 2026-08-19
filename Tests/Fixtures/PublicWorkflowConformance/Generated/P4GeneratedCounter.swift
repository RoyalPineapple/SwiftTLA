import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct P4GeneratedCounter {
    public init() {}

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
    public actor Actor {
        public init() {}
    }
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

    public static func intentionalMismatchActionOutcome(
        actionName: String,
        in state: [String: TLAValue]
    ) -> SpecRuntime.RuntimeActionReport {
        let report = runtime.actionReport(named: actionName, in: state)
        switch report.status {
        case .enabled:
            return .init(
                requested: report.requested,
                state: report.state,
                availability: report.availability,
                status: .enabled(successorCount: 2),
                nextSafeAction: "Intentional mismatch fixture successor count."
            )
        case let status:
            return .init(
                requested: report.requested,
                state: report.state,
                availability: report.availability,
                status: status,
                nextSafeAction: report.nextSafeAction
            )
        }
    }
}
