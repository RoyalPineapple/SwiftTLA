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
        let rmState = Var<TLAFunctionType>("rmState")
        let initFun = TLAValue.function(Dictionary(uniqueKeysWithValues: rms.map {
            (.string($0), .string("working"))
        }))
        func st(_ rm: String) -> StateExpr {
            .functionApply(.variable("rmState"), .value(.string(rm)))
        }
        return TLASpec("TCommit") {
            Extends("Integers")
            Variable(rmState, initFun)
            for rm in rms {
                Action("Prepare_\(rm)") {
                    st(rm) == "working"
                        && rmState.becomes(Expr(.except(rmState, rm, "prepared")))
                }
                Action("Commit_\(rm)") {
                    st(rm) == "prepared"
                        && (st("r1") == "prepared" || st("r1") == "committed")
                        && (st("r2") == "prepared" || st("r2") == "committed")
                        && (st("r3") == "prepared" || st("r3") == "committed")
                        && rmState.becomes(Expr(.except(rmState, rm, "committed")))
                }
                Action("Abort_\(rm)") {
                    (st(rm) == "working" || st(rm) == "prepared")
                        && st("r1") != "committed" && st("r2") != "committed" && st("r3") != "committed"
                        && rmState.becomes(Expr(.except(rmState, rm, "aborted")))
                }
            }
            Invariant("TCConsistent") {
                !((st("r1") == "aborted" && st("r2") == "committed")
                    || (st("r1") == "aborted" && st("r3") == "committed")
                    || (st("r2") == "aborted" && st("r1") == "committed")
                    || (st("r2") == "aborted" && st("r3") == "committed")
                    || (st("r3") == "aborted" && st("r1") == "committed")
                    || (st("r3") == "aborted" && st("r2") == "committed"))
            }
        }
    }

}
