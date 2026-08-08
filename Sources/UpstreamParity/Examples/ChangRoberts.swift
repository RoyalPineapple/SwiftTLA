import SwiftTLA

extension Example {
    public static let changRobertsN3 = Entry(
        id: "ChangRoberts/ChangRoberts_N3",
        upstreamSpec: "chang_roberts",
        upstreamModule: "specifications/chang_roberts/ChangRoberts.tla",
        upstreamCfg: "specifications/chang_roberts/MCChangRoberts.cfg",
        expectedDistinct: 137,
        spec: changRobertsSpec(),
        notes: "N=3, Id=i. 137 states matching upstream. Combined n0/n1 per-node actions.",
    )

    static func changRobertsSpec() -> TLASpec {
        let N = 3
        let nodes = Array(1...N)
        func successor(_ i: Int) -> Int { i == N ? 1 : i + 1 }

        let initiator = Var<TLAFunctionType>("initiator")
        let processState = Var<TLAFunctionType>("state")
        let pc = Var<TLAFunctionType>("pc")
        let msgs = Var<TLAFunctionType>("msgs")

        let bools: [TLAValue] = [.bool(false), .bool(true)]
        var initFuncs: [TLAValue] = []
        for i1 in bools { for i2 in bools { for i3 in bools {
            initFuncs.append(.function([.int(1): i1, .int(2): i2, .int(3): i3]))
        }}}

        let p = Var<Int>("p")
        let nodeSet = StateExpr.set([1, 2, 3])
        let stateExpr = StateExpr.functionLiteral(p, in: nodeSet,
            StateExpr.if(
                StateExpr.equal(
                    StateExpr.functionApply(StateExpr.variable("initiator"),
                        StateExpr.variable("p")),
                    StateExpr.value(.bool(true))),
                then: StateExpr.value(.string("cand")),
                else: StateExpr.value(.string("lost"))))

        func guardContains(_ node: Int, _ id: Int) -> StateExpr {
            StateExpr.in(StateExpr.value(.int(id)),
                StateExpr.functionApply(StateExpr.variable("msgs"),
                    StateExpr.value(.int(node))))
        }

        return TLASpec("ChangRoberts") {
            Extends("Integers")

            Variable(initiator, in: initFuncs)
            Variable(computed: processState) { stateExpr }
            Variable(pc, TLAValue.function([.int(1): "n0", .int(2): "n0", .int(3): "n0"]))
            Variable(msgs, TLAValue.function([
                .int(1): .set([]), .int(2): .set([]), .int(3): .set([])]))

            Invariant("NoFalseWinner") {
                !(processState.applying(1) == "won" && initiator.applying(1) == false)
                && !(processState.applying(2) == "won" && initiator.applying(2) == false)
                && !(processState.applying(3) == "won" && initiator.applying(3) == false)
            }

            for i in nodes {
                let s = successor(i)

                Action("n0_\(i)") {
                    let send = pc.applying(i) == "n0" && initiator.applying(i) == true
                        && msgs.becomes(msgs.updated(at: s,
                            to: msgs.applying(s).union(StateExpr.singleton(i))))
                        && pc.becomes(Expr(.except(pc.stateExpr, .int(i), .value(.string("n1"))))))
                        && initiator.stays && processState.stays

                    let skip = pc.applying(i) == "n0" && initiator.applying(i) == false
                        && pc.becomes(Expr(.except(pc.stateExpr, .int(i), .value(.string("n1"))))))
                        && initiator.stays && processState.stays && msgs.stays

                    send || skip
                }

                Action("n1_\(i)") {
                    var branches: [ActionExpr] = []
                    for picked in nodes {
                        branches.append(
                            pc.applying(i) == "n1"
                                && processState.applying(i) == "lost"
                                && guardContains(i, picked)
                                && msgs.becomes(
                                    msgs.updated(at: i,
                                        to: msgs.applying(i).subtracting(
                                            StateExpr.singleton(picked)))
                                         .updated(at: s,
                                        to: msgs.applying(s).union(
                                            StateExpr.singleton(picked))))
                                && initiator.stays
                                && processState.stays
                                && pc.stays
                        )

                        branches.append(
                            pc.applying(i) == "n1"
                                && processState.applying(i) == "cand"
                                && guardContains(i, picked)
                                && picked < i
                                && msgs.becomes(
                                    msgs.updated(at: i,
                                        to: msgs.applying(i).subtracting(
                                            StateExpr.singleton(picked)))
                                         .updated(at: s,
                                        to: msgs.applying(s).union(
                                            StateExpr.singleton(picked))))
                                && processState.becomes(
                                    processState.updated(at: i, to: "lost"))
                                && initiator.stays
                                && pc.stays
                        )

                        branches.append(
                            pc.applying(i) == "n1"
                                && processState.applying(i) == "cand"
                                && guardContains(i, picked)
                                && picked > i
                                && msgs.becomes(
                                    msgs.updated(at: i,
                                        to: msgs.applying(i).subtracting(
                                            StateExpr.singleton(picked))))
                                && initiator.stays
                                && processState.stays
                                && pc.stays
                        )

                        branches.append(
                            pc.applying(i) == "n1"
                                && processState.applying(i) == "cand"
                                && guardContains(i, picked)
                                && picked == i
                                && msgs.becomes(
                                    msgs.updated(at: i,
                                        to: msgs.applying(i).subtracting(
                                            StateExpr.singleton(picked))))
                                && processState.becomes(
                                    processState.updated(at: i, to: "won"))
                                && initiator.stays
                                && pc.stays
                        )
                    }
                    return branches.dropFirst().reduce(branches[0]) { $0 || $1 }
                }

                WeakFairness("n0_\(i)")
                WeakFairness("n1_\(i)")
            }
            LeadsTo("Liveness",
                StateExpr.existsIn(nodeSet) { n in processState.applying(n) == "cand" },
                StateExpr.existsIn(nodeSet) { n in processState.applying(n) == "won" })
        }
    }

}
