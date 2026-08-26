import SwiftTLA
import SwiftTLAMacros

// Chameneos concurrency game. Creatures meet, complement colors, eventually fade.
// N=4 meetings max, M=4 creatures. Uses nested functions, tuples, EXCEPT @ self-ref.
// Port: 1:1 translation. TypeOK + SumMet safety. 81 states.
// Upstream: specifications/Chameneos/Chameneos.tla

extension Example {
    package static let chameneosM4N4 = Example.Entry(
        id: "Chameneos/Chameneos",
        upstreamSpec: "Chameneos",
        upstreamModule: "specifications/Chameneos/Chameneos.tla",
        upstreamCfg: "specifications/Chameneos/Chameneos.cfg",
        expectedDistinct: 34534,
        maximumStateLimit: 50_000,
        spec: chameneosSpec(),
        notes: "M=4, N=4. RECURSIVE Sum for SumMet. Tuple @ self-ref in EXCEPT. 81 init states → 34,534 reachable.",
    )
}

private enum ChameneosCreature: Int, CaseIterable, FiniteTLAValueDomain {
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    static var defaultValue: Self { .one }
    static let finiteValues = allCases
}

private enum ChameneosColor: String, TLAValueType {
    case blue
    case red
    case yellow
    case faded

    static var defaultValue: Self { .blue }
}

private typealias ChameneosState = Pair<ChameneosColor, Int>

private func chameneosSpec() -> TLASpec {
    let M = 4; let N = 4

    let initialColors = SetExpr<ChameneosColor>.literal(.blue, .red, .yellow)
    let initialCreatureStates = SetExpr<ChameneosState>.literal(
        ChameneosState.literal(.blue, 0),
        ChameneosState.literal(.red, 0),
        ChameneosState.literal(.yellow, 0)
    )

    let specification: TLASpec = #spec("Chameneos") { scope in
        Extends(.integers)

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

        let chameneoses = scope.sharedVar(
            "chameneoses",
            in: Functions(from: ChameneosCreature.all, to: initialCreatureStates)
        )
        let meetingPlace = scope.sharedVar("meetingPlace", initial: 0)
        let numMeetings = scope.sharedVar("numMeetings", initial: 0)

        Invariant("TypeOK") {
            let colorsAndFaded = SetExpr<ChameneosColor>.literal(.blue, .red, .yellow, .faded)
            let rng = StateExpr.set((0...N).map { StateExpr.value(.int($0)) })
            let ids0 = StateExpr.set((0...M).map { StateExpr.value(.int($0)) })

            for creature in ChameneosCreature.all {
                colorsAndFaded.contains(chameneoses[creature].first())
                StateExpr.in(chameneoses[creature].second().raw, rng)
            }
            meetingPlace.stateExpr.isIn(ids0)
        }

        SwiftTLA.Action("Meet") {
            ActionExpr.exists("cid", from: SetExpr<ChameneosCreature>.literal(.one, .two, .three, .four)) { rawCreature in
                let creature = Expr<ChameneosCreature>(rawCreature)
                let mp = meetingPlace.stateExpr
                let nm = numMeetings.stateExpr
                let empty = StateExpr.value(.int(0))
                let nM = StateExpr.value(.int(N))

                let unfaded = StateExpr.notEqual(chameneoses[creature].first().raw, ChameneosColor.faded.stateExpr)

                let enter: ActionExpr = .and(.guard_(StateExpr.equal(mp, empty)),
                    .and(.guard_(nm < nM),
                        .and(meetingPlace.becomes(Expr<Int>(rawCreature)),
                            .and(chameneoses.stays, numMeetings.stays))))
                let fade: ActionExpr = .and(.guard_(StateExpr.equal(mp, empty)),
                    .and(.guard_(StateExpr.not(StateExpr.lessThan(nm, nM))),
                        .and(chameneoses.becomes(chameneoses.updating(
                            creature,
                            to: ChameneosState.literal(Expr(.faded), chameneoses[creature].second())
                        )), .and(meetingPlace.stays, numMeetings.stays))))
                let mpEmptyBranch: ActionExpr = .or(enter, fade)

                let meetingCreature = Expr<ChameneosCreature>(mp)
                let myColor = chameneoses[creature].first()
                let otherColor = chameneoses[meetingCreature].first()
                let complementColor = Expr<ChameneosColor>(StateExpr.ifThenElse(
                    StateExpr.equal(myColor.raw, otherColor.raw), myColor.raw,
                    StateExpr.any(from: initialColors.raw
                        .subtracting(StateExpr.set([myColor.raw, otherColor.raw])))))

                let twoMeet: ActionExpr = .and(.guard_(StateExpr.notEqual(mp, empty)),
                    .and(.guard_(StateExpr.notEqual(mp, rawCreature)),
                        .and(meetingPlace.becomes(0),
                            .and(chameneoses.becomes(chameneoses
                                .updating(creature, to: ChameneosState.literal(
                                    complementColor,
                                    chameneoses[creature].second() + 1
                                ))
                                .updating(meetingCreature, to: ChameneosState.literal(
                                    complementColor,
                                    chameneoses[meetingCreature].second() + 1
                                ))), numMeetings.becomes(numMeetings + 1)))))

                return .and(.guard_(unfaded), .or(mpEmptyBranch, twoMeet))
            }
        }
    }
    return specification
}
