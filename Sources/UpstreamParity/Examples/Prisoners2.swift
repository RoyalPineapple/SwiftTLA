import SwiftTLA

// Two-switch prisoner puzzle. Counter counts switch flips to N.
// 4 prisoners (p1 counter, p2-p4 others). LET + SUBSET + EXCEPT @.
// Port: TypeOK + CountInvariant safety. 4 states.
// Upstream: specifications/Prisoners/Prisoners.tla

extension Example {
    static let prisoners4 = Example.Entry(
        id: "Prisoners/Prisoners",
        upstreamSpec: "Prisoners",
        upstreamModule: "specifications/Prisoners/Prisoners.tla",
        upstreamCfg: "specifications/Prisoners/Prisoners.cfg",        spec: prisoners4Spec(),
        notes: "4 prisoners, p1=counter. Nondet switches init. 214 states.",
    )
}

private func prisoners4Spec() -> TLASpec {
    let allPrisoners: Set<TLAValue> = [.string("p1"), .string("p2"), .string("p3"), .string("p4")]
    let counter: TLAValue = .string("p1")
    let otherPrisoners = allPrisoners.subtracting([counter])
    let threshold = otherPrisoners.count * 2  // 2 per other prisoner = 6

    let switchAUp = Var<Bool>("switchAUp")
    let switchBUp = Var<Bool>("switchBUp")
    let timesSwitched = Var<TLAFunctionType>("timesSwitched")
    let count = Var<Int>("count")

    let others = StateExpr.setLiteral(otherPrisoners.map { .value($0) })

    let tsInit = TLAValue.function(Dictionary(uniqueKeysWithValues: otherPrisoners.map { ($0, .int(0)) }))

    return TLASpec("Prisoners") {
        Extends("Naturals")
        Constant("Prisoner", TLAValue.set(allPrisoners))
        Constant("Counter", counter)

        Variable(switchAUp, in: [TLAValue.bool(true), TLAValue.bool(false)])
        Variable(switchBUp, in: [TLAValue.bool(true), TLAValue.bool(false)])
        Variable(timesSwitched, tsInit)
        Variable(count, 0)

        Invariant("TypeOK") {
            let a = StateExpr.variable("switchAUp")
            let b = StateExpr.variable("switchBUp")
            let t = StateExpr.variable("timesSwitched")
            let c = StateExpr.variable("count")
            let rng = StateExpr.set([StateExpr.value(.int(0)), .value(.int(1)), .value(.int(2))])

            a.isIn(StateExpr.set([true, false]))
            && b.isIn(StateExpr.set([true, false]))
            && c >= 0 && c <= threshold + 1
            && t.applying(StateExpr.value(.string("p2"))).isIn(rng)
            && t.applying(StateExpr.value(.string("p3"))).isIn(rng)
            && t.applying(StateExpr.value(.string("p4"))).isIn(rng)
        }

        Invariant("CountInvariant") {
            let a = StateExpr.variable("switchAUp")
            let t = StateExpr.variable("timesSwitched")
            let c = StateExpr.variable("count")
            let total = t.applying(StateExpr.value(.string("p2")))
                + t.applying(StateExpr.value(.string("p3")))
                + t.applying(StateExpr.value(.string("p4")))
            let oneIfUp = StateExpr.ifThenElse(a, .value(.int(1)), .value(.int(0)))
            let lo = total - oneIfUp
            let hi = lo + 1
            StateExpr.equal(c, lo) || StateExpr.equal(c, hi)
        }

        Action("CounterStep") {
            let a = StateExpr.variable("switchAUp")
            let c = StateExpr.variable("count")

            let turnOff: ActionExpr = switchAUp.becomes(false)
                && count.becomes(c + 1)
                && switchBUp.stays
            let flipB: ActionExpr = switchAUp.stays
                && count.stays
                && switchBUp.becomes(StateExpr.not(StateExpr.variable("switchBUp")))

            return (a && turnOff || StateExpr.not(a) && flipB) && timesSwitched.stays
        }

        Action("NonCounter") {
            ActionExpr.exists("p", from: others) { p in
                let a = StateExpr.variable("switchAUp")
                let t = StateExpr.variable("timesSwitched")

                let signalA: ActionExpr = StateExpr.not(a) && t.applying(p) < 2
                    && switchAUp.becomes(true)
                    && timesSwitched.becomes(t.updated(at: p, to: t.applying(p) + 1))
                    && switchBUp.stays && count.stays
                let flipB: ActionExpr = StateExpr.not(StateExpr.not(a) && t.applying(p) < 2)
                    && switchBUp.becomes(StateExpr.not(StateExpr.variable("switchBUp")))
                    && switchAUp.stays && timesSwitched.stays && count.stays

                return signalA || flipB
            }
        }
    }
}
