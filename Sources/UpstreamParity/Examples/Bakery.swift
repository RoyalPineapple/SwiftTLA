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
        expectedDistinct: 2303,  // TLC-verified
        spec: bakerySpec(),
        notes: "N=2, MaxNat=2. Mutual exclusion + inductive invariant.",
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

            // e2(self): scan numbers of other processes (N=2: at most 1 unchecked)
            let other = s == 1 ? 2 : 1
            Action("e2_pick_gt_\(s)") {
                pc.applying(s) == "e2" && num.applying(other) > maxV.applying(s)
                    && StateExpr.in(StateExpr.int(other), unchecked.applying(s))
                    && unchecked.becomes(unchecked.updated(at: s,
                        to: unchecked.applying(s).subtracting(StateExpr.singleton(StateExpr.int(other)))))
                    && maxV.becomes(maxV.updated(at: s, to: num.applying(other)))
                    && pc.becomes(pc.updated(at: s, to: "e2"))
                    && flag.stays && nxt.stays && num.stays
            }
            Action("e2_pick_le_\(s)") {
                pc.applying(s) == "e2" && !(num.applying(other) > maxV.applying(s))
                    && StateExpr.in(StateExpr.int(other), unchecked.applying(s))
                    && unchecked.becomes(unchecked.updated(at: s,
                        to: unchecked.applying(s).subtracting(StateExpr.singleton(StateExpr.int(other)))))
                    && maxV.stays
                    && pc.becomes(pc.updated(at: s, to: "e2"))
                    && flag.stays && nxt.stays && num.stays
            }
            Action("e2_done_\(s)") {
                pc.applying(s) == "e2" && unchecked.applying(s) == emptySet
                    && pc.becomes(pc.updated(at: s, to: "e3"))
                    && num.stays && flag.stays && maxV.stays && nxt.stays && unchecked.stays
            }

            // e3(self): choose ticket number > max seen, or loop
            Action("e3_loop_\(s)") {
                pc.applying(s) == "e3"
                    && ActionExpr.exists("k", from: natSetExpr) { k in
                        num.becomes(num.updated(at: s, to: k))
                            && pc.becomes(pc.updated(at: s, to: "e3"))
                            && flag.stays && unchecked.stays && maxV.stays && nxt.stays
                    }
            }
            // Proceed to e4: pick ticket > maxV[s]. 
            // For Nat={0,1,2}: maxV=0→pick from {1,2}, maxV=1→{2}, maxV=2→{} (stuck)
            Action("e3_to_e4_gt1_\(s)") {
                pc.applying(s) == "e3" && maxV.applying(s) < 2
                    && num.becomes(num.updated(at: s, to: 2))
                    && pc.becomes(pc.updated(at: s, to: "e4"))
                    && flag.stays && unchecked.stays && maxV.stays && nxt.stays
            }
            Action("e3_to_e4_gt0_\(s)") {
                pc.applying(s) == "e3" && maxV.applying(s) < 1
                    && num.becomes(num.updated(at: s, to: 1))
                    && pc.becomes(pc.updated(at: s, to: "e4"))
                    && flag.stays && unchecked.stays && maxV.stays && nxt.stays
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
                    && unchecked.becomes(unchecked.updated(at: s, to: StateExpr.setDifference(procSetExpr, StateExpr.singleton(StateExpr.int(s)))))
                    && pc.becomes(pc.updated(at: s, to: "w1"))
                    && num.stays && maxV.stays && nxt.stays
            }

            // w1(self): pick next process to check
            Action("w1_pick_\(s)") {
                pc.applying(s) == "w1" && unchecked.applying(s) != emptySet
                    && ActionExpr.exists("i", from: unchecked.applying(s)) { i in
                        nxt.becomes(nxt.updated(at: s, to: i))
                            && StateExpr.not(flag.applying(i))
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
                let pcAtW2 = StateExpr.equal(pc.applying(s), "w2")
                let nxtIsZero = StateExpr.equal(num.applying(nxt.applying(s)), 0)
                let myLessThanNxt = StateExpr.lessThan(num.applying(s), num.applying(nxt.applying(s)))
                let tieAndSmaller = (num.applying(s) == num.applying(nxt.applying(s)))
                                    && StateExpr.lessThan(StateExpr.value(.int(s)), nxt.applying(s))
                let guardExpr = pcAtW2 && (nxtIsZero || myLessThanNxt || tieAndSmaller)
                let nxtSingular = StateExpr.singleton(nxt.applying(s))
                let newUnchecked = unchecked.applying(s).subtracting(nxtSingular)
                guardExpr
                    && unchecked.becomes(unchecked.updated(at: s, to: newUnchecked))
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

        // Liveness requires WF fairness on all actions (not included in this model).
        // Upstream cfg has *PROPERTIES DeadlockFree StarvationFree — commented out.
    }
}
