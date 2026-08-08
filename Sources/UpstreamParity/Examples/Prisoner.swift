import SwiftTLA

// Single-switch prisoner puzzle. Counter turns light off, counts to N.
// N=3, Light_Unknown=FALSE. 3 initial counter choices → 16 states.
// Port: 1:1. TypeOK + VictoryOK.
// Upstream: specifications/Prisoners_Single_Switch/Prisoner.tla

extension Example {
    static let prisonerN3 = Example.Entry(
        id: "Prisoners_Single_Switch/Prisoner",
        upstreamSpec: "Prisoners_Single_Switch",
        upstreamModule: "specifications/Prisoners_Single_Switch/Prisoner.tla",
        upstreamCfg: "specifications/Prisoners_Single_Switch/Prisoner.cfg",
        expectedDistinct: 16,
        spec: prisonerSpec(),
        notes: "N=3, Light_Unknown=FALSE. 3 initial counter choices via Variable(in:).",
    )
}

private func prisonerSpec() -> TLASpec {
    let prisoners: Set<TLAValue> = [.string("Alice"), .string("Bob"), .string("Eve")]
    let lightUnknown: TLAValue = .bool(false)
    let threshold: StateExpr = 3

    let count = Var<Int>("count")
    let announced = Var<Bool>("announced")
    let signalled = Var<TLAFunctionType>("signalled")
    let light = Var<String>("light")
    let hasVisited = Var<TLASetType>("has_visited")
    let counter = Var<String>("counter")

    let lightOff = StateExpr.value(.string("off"))
    let lightOn = StateExpr.value(.string("on"))
    let trueE = StateExpr.value(.bool(true))
    let falseE = StateExpr.value(.bool(false))
    let pSet = StateExpr.setLiteral(prisoners.map { StateExpr.value($0) })
    let rng02 = StateExpr.set([StateExpr.value(.int(0)), .value(.int(1)), .value(.int(2))])

    return TLASpec("Prisoner") {
        Extends("Naturals")
        Constant("Prisoner", TLAValue.set(prisoners))
        Constant("Light_Unknown", lightUnknown)

        Variable(counter, TLAValue.string("Alice"))
        Variable(count, 1)
        Variable(announced, false)
        Variable(signalled, TLAValue.function([.string("Alice"): 0, .string("Bob"): 0, .string("Eve"): 0]))
        Variable(light, TLAValue.string("off"))
        Variable(hasVisited, TLAValue.set([]))

        Invariant("TypeOK") {
            let c = StateExpr.variable("count")
            let a = StateExpr.variable("announced")
            let l = StateExpr.variable("light")
            let h = StateExpr.variable("has_visited")
            let s = StateExpr.variable("signalled")

            c >= 1 && c <= threshold + 1
                && a.isIn(StateExpr.set([trueE, falseE]))
                && l.isIn(StateExpr.set([lightOff, lightOn]))
                && h.isSubset(of: pSet)
            for p in ["Alice", "Bob", "Eve"] {
                s.applying(StateExpr.value(.string(p))).isIn(rng02)
            }
        }

        Invariant("VictoryOK") {
            let a = StateExpr.variable("announced")
            let h = StateExpr.variable("has_visited")
            StateExpr.ifThenElse(a, StateExpr.equal(h, pSet), trueE)
        }

        Action("Warden") {
            ActionExpr.exists("p", from: pSet) { p in
                let ct = StateExpr.variable("counter")
                let l = StateExpr.variable("light")
                let cnt = StateExpr.variable("count")
                let sig = StateExpr.variable("signalled")
                let hv = StateExpr.variable("has_visited")
                let isPct = StateExpr.equal(p, ct)

                let lightOnAct: ActionExpr = .and(.assign("light", lightOff),
                    .and(.assign("count", cnt + 1),
                        .assign("announced", cnt + 1 >= threshold)))
                let lightOffAct: ActionExpr = .and(.unchanged("light"),
                    .and(.unchanged("count"),
                        .assign("announced", cnt >= threshold)))
                let counterBody: ActionExpr = .and(.guard_(isPct),
                    .and(.or(.and(.guard_(StateExpr.equal(l, lightOn)), lightOnAct),
                             .and(.guard_(StateExpr.notEqual(l, lightOn)), lightOffAct)),
                        .unchanged("signalled")))

                let sigAct: ActionExpr = .and(.assign("light", lightOn),
                    .assign("signalled", sig.updated(at: p, to: sig.applying(p) + 1)))
                let noSigAct: ActionExpr = .and(.unchanged("light"),
                    .unchanged("signalled"))
                let canSignal = StateExpr.equal(l, lightOff) && sig.applying(p) < 1
                let standardBody: ActionExpr = .and(.guard_(StateExpr.notEqual(p, ct)),
                    .and(.or(.and(.guard_(canSignal), sigAct),
                             .and(.guard_(StateExpr.not(canSignal)), noSigAct)),
                        .and(.unchanged("count"),
                            .unchanged("announced"))))

                return .and(.or(counterBody, standardBody),
                    .assign("has_visited", hv.union(StateExpr.singleton(p))))
            }
        }
    }
}
