import SwiftTLA

extension Example {
    public static let tCommit = Entry(
        id: "transaction_commit/TCommit",
        upstreamSpec: "transaction_commit",
        upstreamModule: "specifications/transaction_commit/TCommit.tla",
        upstreamCfg: "specifications/transaction_commit/TCommit.cfg",
        expectedDistinct: 34,
        spec: tCommitSpec(),
        notes: "Lamport TCommit. SPECIFICATION TCSpec. TLC = 34.",
    )

static func tCommitSpec() -> TLASpec {
        let rms = ["r1", "r2", "r3"]
        let rmState = Var<TLAValue>("rmState")
        let initFun = TLAValue.function(Dictionary(uniqueKeysWithValues: rms.map {
            (.string($0), .string("working"))
        }))
        func st(_ rm: String) -> StateExpr {
            .functionApply(.variable("rmState"), .value(.string(rm)))
        }
        func isPreparedOrCommitted(_ rm: String) -> StateExpr {
            st(rm) == "prepared" || st(rm) == "committed"
        }
        func noResourceManagerHasCommitted() -> StateExpr {
            st("r1") != "committed" && st("r2") != "committed" && st("r3") != "committed"
        }
        func abortAndCommitAreMutuallyExclusive(_ aborted: String, _ committed: String) -> StateExpr {
            !(st(aborted) == "aborted" && st(committed) == "committed")
        }
        return TLASpec("TCommit") {
            Extends("Integers")
            Variable(rmState, initFun)
            for rm in rms {
                Action("Prepare_\(rm)") {
                    st(rm) == "working"
                        && .assign(rmState.name, rmState.stateExpr.updated(at: rm, to: "prepared"))
                }
                Action("Commit_\(rm)") {
                    st(rm) == "prepared"
                        && isPreparedOrCommitted("r1")
                        && isPreparedOrCommitted("r2")
                        && isPreparedOrCommitted("r3")
                        && .assign(rmState.name, rmState.stateExpr.updated(at: rm, to: "committed"))
                }
                Action("Abort_\(rm)") {
                    (st(rm) == "working" || st(rm) == "prepared")
                        && noResourceManagerHasCommitted()
                        && .assign(rmState.name, rmState.stateExpr.updated(at: rm, to: "aborted"))
                }
            }
            Invariant("TCConsistent") {
                abortAndCommitAreMutuallyExclusive("r1", "r2")
                    && abortAndCommitAreMutuallyExclusive("r1", "r3")
                    && abortAndCommitAreMutuallyExclusive("r2", "r1")
                    && abortAndCommitAreMutuallyExclusive("r2", "r3")
                    && abortAndCommitAreMutuallyExclusive("r3", "r1")
                    && abortAndCommitAreMutuallyExclusive("r3", "r2")
            }
        }
    }

}
