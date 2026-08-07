import SwiftTLA

/// Lamport's Bakery algorithm — mutual exclusion without atomic reads/writes.
/// N=2 processes, Nat bounded to 0..2. PlusCal translation ported 1:1.
/// Upstream: specifications/Bakery-Boulangerie/Bakery.tla

extension Example {
    public static let bakeryN2 = Entry(
        id: "Bakery/N2",
        upstreamSpec: "Bakery-Boulangerie",
        upstreamModule: "specifications/Bakery-Boulangerie/Bakery.tla",
        upstreamCfg: "specifications/Bakery-Boulangerie/MCBakery.cfg",
        expectedDistinct: 0,
        expectedResult: "success",
        spec: bakerySpec(),
        notes: "N=2, MaxNat=2. Mutual exclusion + inductive invariant.",
        matchesUpstreamTLC: false
    )
}

private func bakerySpec() -> TLASpec {
    let N = 2
    let procs = 1...N
    let maxNat = 2
    let natVals = 0...maxNat
    let pcStates = ["ncs", "e1", "e2", "e3", "e4", "w1", "w2", "cs", "exit"]

    let num = Var<TLAFunctionType>("num")
    let flag = Var<TLAFunctionType>("flag")
    let pc = Var<TLAFunctionType>("pc")
    let unchecked = Var<TLAFunctionType>("unchecked")
    let maxV = Var<TLAFunctionType>("max")
    let nxt = Var<TLAFunctionType>("nxt")

    // Init: functions over Procs
    let initNum: TLAValue = .function(Dictionary(uniqueKeysWithValues: procs.map { (.int($0), .int(0)) }))
    let initFlag: TLAValue = .function(Dictionary(uniqueKeysWithValues: procs.map { (.int($0), .bool(false)) }))
    let initPC: TLAValue = .function(Dictionary(uniqueKeysWithValues: procs.map { (.int($0), .string("ncs")) }))
    let initUnchecked: TLAValue = .function(Dictionary(uniqueKeysWithValues: procs.map { (.int($0), .set([])) }))
    let initMax: TLAValue = .function(Dictionary(uniqueKeysWithValues: procs.map { (.int($0), .int(0)) }))
    let initNxt: TLAValue = .function(Dictionary(uniqueKeysWithValues: procs.map { (.int($0), .int(1)) }))

    let procSetExpr: StateExpr = .setLiteral(procs.map { .int($0) })
    let natSetExpr: StateExpr = .setLiteral(natVals.map { .int($0) })
    let emptySet: StateExpr = .setLiteral([])

    return TLASpec("Bakery") {
        Extends("Integers")

        Variable(num, initNum)
        Variable(flag, initFlag)
        Variable(pc, initPC)
        Variable(unchecked, initUnchecked)
        Variable(maxV, initMax)
        Variable(nxt, initNxt)

        Invariant("TypeOK") {
            for i in procs {
                let ik = StateExpr.value(.int(i))
                StateExpr.in(num.applying(ik), natSetExpr)
                    && StateExpr.in(flag.applying(ik), .setLiteral([.bool(false), .bool(true)]))
                    && StateExpr.in(pc.applying(ik), .setLiteral(pcStates.map { .value(.string($0)) }))
                    && StateExpr.in(maxV.applying(ik), natSetExpr)
                    && StateExpr.in(nxt.applying(ik), procSetExpr)
            }
        }

        Invariant("MutualExclusion") {
            !(pc.applying(1) == "cs" && pc.applying(2) == "cs")
        }

        // Per-process actions — following the PlusCal translation

        for s in procs {
            // ncs(self): non-critical section → e1
            Action("ncs_\(s)") {
                pc.applying(s) == "ncs"
                    && pc.becomes(pc.updated(at: s, to: "e1"))
                    && num.stays && flag.stays && unchecked.stays && maxV.stays && nxt.stays
            }

            // e1(self): toggle flag OR set flag=TRUE and start e2
            Action("e1a_\(s)") {
                pc.applying(s) == "e1"
                    && flag.becomes(flag.updated(at: s, to: StateExpr.not(flag.applying(s))))
                    && pc.becomes(pc.updated(at: s, to: "e1"))
                    && num.stays && unchecked.stays && maxV.stays && nxt.stays
            }
            Action("e1b_\(s)") {
                pc.applying(s) == "e1"
                    && flag.becomes(flag.updated(at: s, to: StateExpr.value(.bool(true))))
                    && unchecked.becomes(unchecked.updated(at: s, to: StateExpr.setDifference(procSetExpr, StateExpr.singleton(StateExpr.int(s)))))
                    && maxV.becomes(maxV.updated(at: s, to: 0))
                    && pc.becomes(pc.updated(at: s, to: "e2"))
                    && num.stays && nxt.stays
            }

            // e2(self): scan numbers of other processes
            Action("e2_pick_\(s)") {
                pc.applying(s) == "e2" && unchecked.applying(s) != emptySet
                    && ActionExpr.exists("i", from: unchecked.applying(s)) { i in
                        let gtBranch = num.applying(i) > maxV.applying(s)
                            && unchecked.becomes(unchecked.updated(at: s,
                                to: unchecked.applying(s).subtracting(StateExpr.singleton(i))))
                            && maxV.becomes(maxV.updated(at: s, to: num.applying(i)))
                            && pc.becomes(pc.updated(at: s, to: "e2"))
                            && num.stays && flag.stays && nxt.stays
                        let leBranch = !(num.applying(i) > maxV.applying(s))
                            && unchecked.becomes(unchecked.updated(at: s,
                                to: unchecked.applying(s).subtracting(StateExpr.singleton(i))))
                            && maxV.stays
                            && pc.becomes(pc.updated(at: s, to: "e2"))
                            && num.stays && flag.stays && nxt.stays
                        return gtBranch || leBranch
                    }
            }
            Action("e2_done_\(s)") {
                pc.applying(s) == "e2" && unchecked.applying(s) == emptySet
                    && pc.becomes(pc.updated(at: s, to: "e3"))
                    && num.stays && flag.stays && maxV.stays && nxt.stays && unchecked.stays
            }

            // e3(self): choose ticket number > max seen
            Action("e3_loop_\(s)") {
                pc.applying(s) == "e3"
                    && ActionExpr.exists("k", from: natSetExpr) { k in
                        num.becomes(num.updated(at: s, to: k))
                            && pc.becomes(pc.updated(at: s, to: "e3"))
                            && flag.stays && unchecked.stays && maxV.stays && nxt.stays
                    }
            }
            Action("e3_proceed_\(s)") {
                pc.applying(s) == "e3"
                    && ActionExpr.exists("i", from: StateExpr.filterSet(natSetExpr) { j in j > maxV.applying(s) }) { i in
                        num.becomes(num.updated(at: s, to: i))
                            && pc.becomes(pc.updated(at: s, to: "e4"))
                            && flag.stays && unchecked.stays && maxV.stays && nxt.stays
                    }
            }

            // e4(self): lower flag
            Action("e4a_\(s)") {
                pc.applying(s) == "e4"
                    && flag.becomes(flag.updated(at: s, to: StateExpr.not(flag.applying(s))))
                    && pc.becomes(pc.updated(at: s, to: "e4"))
                    && num.stays && maxV.stays && nxt.stays && unchecked.stays
            }
            Action("e4b_\(s)") {
                pc.applying(s) == "e4"
                    && flag.becomes(flag.updated(at: s, to: StateExpr.value(.bool(false))))
                    && unchecked.becomes(unchecked.updated(at: s, to: StateExpr.setDifference(procSetExpr, .singleton(.int(s)))))
                    && pc.becomes(pc.updated(at: s, to: "w1"))
                    && num.stays && maxV.stays && nxt.stays
            }

            // w1(self): pick next process to check
            Action("w1_pick_\(s)") {
                pc.applying(s) == "w1" && unchecked.applying(s) != emptySet
                    && ActionExpr.exists("i", from: unchecked.applying(s)) { i in
                        nxt.becomes(nxt.updated(at: s, to: i))
                            && StateExpr.not(flag.applying(nxt.applying(s)))
                            && pc.becomes(pc.updated(at: s, to: "w2"))
                            && num.stays && flag.stays && unchecked.stays && maxV.stays
                    }
            }
            Action("w1_done_\(s)") {
                pc.applying(s) == "w1" && unchecked.applying(s) == emptySet
                    && pc.becomes(pc.updated(at: s, to: "cs"))
                    && num.stays && flag.stays && unchecked.stays && maxV.stays && nxt.stays
            }

            // w2(self): wait until safe to proceed
            Action("w2_\(s)") {
                pc.applying(s) == "w2"
                    && (num.applying(nxt.applying(s)) == 0
                        || num.applying(s) < num.applying(nxt.applying(s))
                        || (num.applying(s) == num.applying(nxt.applying(s)) && .int(s) < nxt.applying(s)))
                    && unchecked.becomes(unchecked.updated(at: s,
                        to: unchecked.applying(s).subtracting(StateExpr.singleton(nxt.applying(s)))))
                    && pc.becomes(pc.updated(at: s, to: "w1"))
                    && num.stays && flag.stays && maxV.stays && nxt.stays
            }

            // cs(self): critical section
            Action("cs_\(s)") {
                pc.applying(s) == "cs"
                    && pc.becomes(pc.updated(at: s, to: "exit"))
                    && num.stays && flag.stays && unchecked.stays && maxV.stays && nxt.stays
            }

            // exit(self): reset ticket number
            Action("exit_loop_\(s)") {
                pc.applying(s) == "exit"
                    && ActionExpr.exists("k", from: natSetExpr) { k in
                        num.becomes(num.updated(at: s, to: k))
                            && pc.becomes(pc.updated(at: s, to: "exit"))
                            && flag.stays && unchecked.stays && maxV.stays && nxt.stays
                    }
            }
            Action("exit_reset_\(s)") {
                pc.applying(s) == "exit"
                    && num.becomes(num.updated(at: s, to: 0))
                    && pc.becomes(pc.updated(at: s, to: "ncs"))
                    && flag.stays && unchecked.stays && maxV.stays && nxt.stays
            }
        }

        LeadsTo("DeadlockFree",
            StateExpr.exists(in: procSetExpr, pc.applying(.variable("x")) == "e1"),
            StateExpr.exists(in: procSetExpr, pc.applying(.variable("x")) == "cs"))
        LeadsTo("StarvationFree_1",
            pc.applying(1) == "e1",
            pc.applying(1) == "cs")
        LeadsTo("StarvationFree_2",
            pc.applying(2) == "e1",
            pc.applying(2) == "cs")
    }
}
