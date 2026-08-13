import SwiftTLA

extension Example {
    public static let syncTD = Entry(
        id: "ewd840/SyncTerminationDetection",
        upstreamSpec: "ewd840",
        upstreamModule: "specifications/ewd840/SyncTerminationDetection.tla",
        upstreamCfg: "specifications/ewd840/SyncTerminationDetection.cfg",
        expectedDistinct: 9,
        spec: syncTDSpec(),
        notes: "Abstract termination detection. N=3, active as function, terminationDetected boolean. TLC = ?",
    )

static func syncTDSpec() -> TLASpec {
        let N = 3
        let nodes = Array(0..<N)
        let boolOpts: [TLAValue] = [.bool(false), .bool(true)]
        var activeFuncs: [TLAValue] = []
        for a0 in boolOpts { for a1 in boolOpts { for a2 in boolOpts {
            activeFuncs.append(.function([.int(0): a0, .int(1): a1, .int(2): a2]))
        }}}

        let active = Var<TLAValue>("active")
        let terminatedDetected = Var<Bool>("terminationDetected")

        func activeOf(_ i: Int) -> StateExpr {
            StateExpr.functionApply(StateExpr.variable("active"), StateExpr.value(.int(i)))
        }
        func allInactive() -> StateExpr {
            StateExpr.and(
                StateExpr.and(
                    StateExpr.equal(activeOf(0), StateExpr.value(.bool(false))),
                    StateExpr.equal(activeOf(1), StateExpr.value(.bool(false)))
                ),
                StateExpr.equal(activeOf(2), StateExpr.value(.bool(false)))
            )
        }

        return TLASpec("SyncTerminationDetection") {
            Extends("Integers")
            Variable(active, in: activeFuncs)
            Variable(terminatedDetected, in: [false])

            for i in nodes {
                Action("Terminate_\(i)") {
                    activeOf(i) == true
                    && .assign(active.name, active.stateExpr.updated(at: i, to: false))
                    && terminatedDetected.stays
                }
            }

            for i in nodes {
                for j in nodes where j != i {
                    Action("Wakeup_\(i)_to_\(j)") {
                        activeOf(i) == true
                        && .assign(active.name, active.stateExpr.updated(at: j, to: true))
                        && terminatedDetected.stays
                    }
                }
            }

            Action("DetectTermination") {
                allInactive()
                && terminatedDetected.becomes(true)
                && active.stays
            }

            Invariant("TDCorrect") {
                terminatedDetected == false || allInactive()
            }
        }
    }

}
