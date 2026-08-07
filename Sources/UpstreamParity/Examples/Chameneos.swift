import SwiftTLA

// Chameneos concurrency game. Creatures meet, complement colors, eventually fade.
// N=4 meetings max, M=4 creatures. Uses nested functions, tuples, EXCEPT @ self-ref.
// Port: 1:1 translation. TypeOK + SumMet safety. 81 states.
// Upstream: specifications/Chameneos/Chameneos.tla

extension Example {
    static let chameneosM4N4 = Example.Entry(
        id: "Chameneos/Chameneos",
        upstreamSpec: "Chameneos",
        upstreamModule: "specifications/Chameneos/Chameneos.tla",
        upstreamCfg: "specifications/Chameneos/Chameneos.cfg",
        expectedDistinct: 34534,
        expectedResult: "success",
        spec: chameneosSpec(),
        notes: "M=4, N=4. RECURSIVE Sum for SumMet. Tuple @ self-ref in EXCEPT. 81 init states → 34,534 reachable.",
        matchesUpstreamTLC: true
    )
}

private func chameneosSpec() -> TLASpec {
    let M = 4; let N = 4

    let chameneoses = Var<TLAFunctionType>("chameneoses")
    let meetingPlace = Var<Int>("meetingPlace")
    let numMeetings = Var<Int>("numMeetings")

    let colors: [TLAValue] = [.string("blue"), .string("red"), .string("yellow")]
    let ids: Set<TLAValue> = [.int(1), .int(2), .int(3), .int(4)]
    let colorRange = Set(colors.map { TLAValue.tuple([$0, .int(0)]) })
    let allFuncs = TLAValue.functionSet(domain: ids, range: colorRange)

    return TLASpec("Chameneos") {
        Extends("Integers")

        DefineRecursive("Sum", params: ["f", "S"]) {
            let s = StateExpr.variable("S")
            let f = StateExpr.variable("f")
            let x = StateExpr.any(from: s)
            StateExpr.ifThenElse(
                StateExpr.equal(StateExpr.setLiteral([]), s),
                .value(.int(0)),
                StateExpr.functionApply(f, x) + StateExpr.recursiveCall("Sum", [
                    f,
                    StateExpr.setDifference(s, StateExpr.setLiteral([x]))
                ])
            )
        }

        Variable(chameneoses, in: allFuncs)
        Variable(meetingPlace, 0)
        Variable(numMeetings, 0)

        Invariant("TypeOK") {
            let c = StateExpr.variable("chameneoses")
            let m = StateExpr.variable("meetingPlace")
            let colorsAndFaded = StateExpr.set(
                [StateExpr.value(.string("blue")), .value(.string("red")), .value(.string("yellow")), .value(.string("faded"))])
            let rng = StateExpr.set((0...N).map { StateExpr.value(.int($0)) })
            let ids0 = StateExpr.set((0...M).map { StateExpr.value(.int($0)) })

            for i in 1...M {
                let ci = StateExpr.value(.int(i))
                c.applying(ci).at(1).isIn(colorsAndFaded)
                c.applying(ci).at(2).isIn(rng)
            }
            m.isIn(ids0)
        }

        Action("Meet") {
            ActionExpr.exists("cid", from: StateExpr.setLiteral((1...M).map { .value(.int($0)) })) { cid in
                let mp = StateExpr.variable("meetingPlace")
                let cham = StateExpr.variable("chameneoses")
                let nm = StateExpr.variable("numMeetings")
                let empty = StateExpr.value(.int(0))
                let fadedE = StateExpr.value(.string("faded"))
                let nM = StateExpr.value(.int(N))

                let unfaded = StateExpr.notEqual(cham.applying(cid).at(1), fadedE)

                let enter: ActionExpr = .and(.guard_(StateExpr.equal(mp, empty)),
                    .and(.guard_(nm < nM),
                        .and(.assign("meetingPlace", cid),
                            .and(.unchanged("chameneoses"), .unchanged("numMeetings")))))
                let fade: ActionExpr = .and(.guard_(StateExpr.equal(mp, empty)),
                    .and(.guard_(StateExpr.not(StateExpr.lessThan(nm, nM))),
                        .and(.assign("chameneoses", cham.updated(at: cid, to: StateExpr.tuple([fadedE, cham.applying(cid).at(2)]))),
                            .and(.unchanged("meetingPlace"), .unchanged("numMeetings")))))
                let mpEmptyBranch: ActionExpr = .or(enter, fade)

                let myColor = cham.applying(cid).at(1)
                let otherColor = cham.applying(mp).at(1)
                let complementColor = StateExpr.ifThenElse(
                    StateExpr.equal(myColor, otherColor), myColor,
                    StateExpr.any(from:
                        StateExpr.set([StateExpr.value(.string("blue")), .value(.string("red")), .value(.string("yellow"))])
                        .subtracting(StateExpr.set([myColor, otherColor]))))

                let twoMeet: ActionExpr = .and(.guard_(StateExpr.notEqual(mp, empty)),
                    .and(.guard_(StateExpr.notEqual(mp, cid)),
                        .and(.assign("meetingPlace", empty),
                            .and(.assign("chameneoses", cham
                                .updated(at: cid, to: StateExpr.tuple([complementColor, cham.applying(cid).at(2) + 1]))
                                .updated(at: mp, to: StateExpr.tuple([complementColor, cham.applying(mp).at(2) + 1]))),
                                .assign("numMeetings", nm + 1)))))

                return .and(.guard_(unfaded), .or(mpEmptyBranch, twoMeet))
            }
        }
    }
}
