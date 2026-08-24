import SwiftTLA

/// Lamport's transaction-commit protocol over three resource managers.
///
/// The resource-manager state is one finite, typed formal function. The three
/// parameterized actions retain the upstream transition relation without
/// manufacturing a separate action for each manager in Swift.
public struct TCommitModel: Sendable {
    public enum ResourceManager: String, CaseIterable, FiniteTLAValueDomain {
        case one = "r1"
        case two = "r2"
        case three = "r3"

        public static var defaultValue: Self { .one }
        public static let finiteValues = allCases
    }

    private static func specificationComponents(_ scope: SpecificationScope) -> [SpecComponent] {
        let rmState = scope.sharedVar("rmState", initial: Function<ResourceManager, ManagerState>.literal(
            (.one, .working), (.two, .working), (.three, .working)
        ))
        let allPreparedOrCommitted = (rmState[.one] == .prepared || rmState[.one] == .committed)
            && (rmState[.two] == .prepared || rmState[.two] == .committed)
            && (rmState[.three] == .prepared || rmState[.three] == .committed)
        let noneCommitted = rmState[.one] != .committed
            && rmState[.two] != .committed
            && rmState[.three] != .committed

        let prepare: SpecComponent = SwiftTLA.Action("Prepare", parameters: [
            ActionParameter("rm", values: ResourceManager.finiteValues)
        ]) {
            let rm = Expr<ResourceManager>(.variable("rm"))
            rmState[rm] == .working
                && rmState.becomes(rmState.expr.updating(rm, to: .prepared))
        }

        let decideCommit: SpecComponent = SwiftTLA.Action("DecideCommit", parameters: [
            ActionParameter("rm", values: ResourceManager.finiteValues)
        ]) {
            let rm = Expr<ResourceManager>(.variable("rm"))
            rmState[rm] == .prepared
                && allPreparedOrCommitted
                && rmState.becomes(rmState.expr.updating(rm, to: .committed))
        }

        let decideAbort: SpecComponent = SwiftTLA.Action("DecideAbort", parameters: [
            ActionParameter("rm", values: ResourceManager.finiteValues)
        ]) {
            let rm = Expr<ResourceManager>(.variable("rm"))
            (rmState[rm] == .working || rmState[rm] == .prepared)
                && noneCommitted
                && rmState.becomes(rmState.expr.updating(rm, to: .aborted))
        }

        let consistency: SpecComponent = Invariant("TCConsistent") {
            !(rmState[.one] == .aborted && rmState[.two] == .committed)
                && !(rmState[.one] == .aborted && rmState[.three] == .committed)
                && !(rmState[.two] == .aborted && rmState[.one] == .committed)
                && !(rmState[.two] == .aborted && rmState[.three] == .committed)
                && !(rmState[.three] == .aborted && rmState[.one] == .committed)
                && !(rmState[.three] == .aborted && rmState[.two] == .committed)
        }

        return [
            Extends(.integers),
            consistency,
            prepare,
            decideCommit,
            decideAbort
        ]
    }
}

extension Example {
    public static let tCommit = Entry(
        id: "transaction_commit/TCommit",
        upstreamSpec: "transaction_commit",
        upstreamModule: "specifications/transaction_commit/TCommit.tla",
        upstreamCfg: "specifications/transaction_commit/TCommit.cfg",
        expectedDistinct: 34,
        spec: TCommitModel.spec,
        notes: "Lamport TCommit. Typed resource-manager function and parameterized actions. TLC = 34."
    )
}
