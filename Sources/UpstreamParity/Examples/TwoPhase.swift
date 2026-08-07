import SwiftTLA

extension Example {
    public static let twoPhase = Entry(
        id: "transaction_commit/TwoPhase",
        upstreamSpec: "transaction_commit",
        upstreamModule: "specifications/transaction_commit/TwoPhase.tla",
        upstreamCfg: "specifications/transaction_commit/TwoPhase.cfg",
        expectedDistinct: 288,
        expectedResult: "success",
        spec: twoPhaseSpec(),
        notes: "Lamport TwoPhase safety. RM={r1,r2,r3}, msgs as record-set. SPECIFICATION TPSpec. TLC = 288.",
        matchesUpstreamTLC: true
    )

static func twoPhaseSpec() -> TLASpec {
        let rms = ["r1", "r2", "r3"]
        let rmSet: StateExpr = .setLiteral(rms.map { .value(.string($0)) })
        let rmState = Var<TLAFunctionType>("rmState")
        let tmState = Var<String>("tmState")
        let tmPrepared = Var<TLASetType>("tmPrepared")
        let msgs = Var<TLASetType>("msgs")

        func recordMsg(_ fields: [String: String]) -> StateExpr {
            .recordLiteral(fields.mapValues { .value(.string($0)) })
        }
        func commitMsg() -> StateExpr { recordMsg(["type": "Commit"]) }
        func abortMsg() -> StateExpr { recordMsg(["type": "Abort"]) }
        func preparedMsg(_ rm: String) -> StateExpr { recordMsg(["type": "Prepared", "rm": rm]) }
        func rmSt(_ rm: String) -> StateExpr {
            .functionApply(.variable("rmState"), .value(.string(rm)))
        }

        return TLASpec("TwoPhase") {
            Extends("Integers")
            let initRMState = TLAValue.function(Dictionary(uniqueKeysWithValues: rms.map {
                (.string($0), .string("working"))
            }))
            Variable(rmState, initRMState)
            Variable(tmState, "init")
            Variable(tmPrepared, TLAValue.set([]))
            Variable(msgs, TLAValue.set([]))

            for rm in rms {
                Action("RcvPrepared_\(rm)") {
                    tmState == "init"
                    && preparedMsg(rm).isIn(msgs)
                    && tmPrepared.becomes(tmPrepared.union(StateExpr.singleton(rm)))
                    && rmState.stays && tmState.stays && msgs.stays
                }
            }

            Action("TMCommit") {
                tmState == "init"
                && tmPrepared.cardinality == 3
                && tmState.becomes("committed")
                && msgs.becomes(msgs.union(StateExpr.singleton(commitMsg())))
                && rmState.stays && tmPrepared.stays
            }

            Action("TMAbort") {
                tmState == "init"
                && tmState.becomes("aborted")
                && msgs.becomes(msgs.union(StateExpr.singleton(abortMsg())))
                && rmState.stays && tmPrepared.stays
            }

            for rm in rms {
                Action("Prepare_\(rm)") {
                    rmSt(rm) == "working"
                    && rmState.becomes(rmState.updated(at: rm, to: "prepared"))
                    && msgs.becomes(msgs.union(StateExpr.singleton(preparedMsg(rm))))
                    && tmState.stays && tmPrepared.stays
                }
                Action("Abort_\(rm)") {
                    rmSt(rm) == "working"
                    && rmState.becomes(rmState.updated(at: rm, to: "aborted"))
                    && tmState.stays && tmPrepared.stays && msgs.stays
                }
                Action("RcvCommit_\(rm)") {
                    commitMsg().isIn(msgs)
                    && rmState.becomes(rmState.updated(at: rm, to: "committed"))
                    && tmState.stays && tmPrepared.stays && msgs.stays
                }
                Action("RcvAbort_\(rm)") {
                    abortMsg().isIn(msgs)
                    && rmState.becomes(rmState.updated(at: rm, to: "aborted"))
                    && tmState.stays && tmPrepared.stays && msgs.stays
                }
            }

            Invariant("TPTypeOK") {
                rmSt("r1").isIn(StateExpr.set(["working", "prepared", "committed", "aborted"]))
                && rmSt("r2").isIn(StateExpr.set(["working", "prepared", "committed", "aborted"]))
                && rmSt("r3").isIn(StateExpr.set(["working", "prepared", "committed", "aborted"]))
                && tmState.isIn(StateExpr.set(["init", "committed", "aborted"]))
                && tmPrepared.isSubset(of: rmSet)
            }
        }
    }

}
