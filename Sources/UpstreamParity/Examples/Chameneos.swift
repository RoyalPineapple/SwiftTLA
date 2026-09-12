import SwiftTLA
import SwiftTLAMacros

// Chameneos concurrency game, N=4 meetings and M=4 creatures.
// Upstream: specifications/Chameneos/Chameneos.tla
extension Example {
    package static let chameneosM4N4 = FiniteModelFixture(
        expectedDistinct: 34534,
        maximumStateLimit: 50_000,
        spec: ChameneosModel.spec
    )
}

@TLAModel
package struct ChameneosModel: Sendable {
    package enum Creature: Int, CaseIterable, FiniteTLAValueDomain {
        case one = 1, two, three, four
        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases
    }

    package enum Color: String, CaseIterable, FiniteTLAValueDomain {
        case blue, red, yellow, faded
        package static var defaultValue: Self { .blue }
        package static let finiteValues = allCases
    }

    package typealias CreatureState = Pair<Color, Int>

    package static var spec: TLASpec {
        #spec("Chameneos") { scope in
            Import(FunctionsModule.module)
            let initialColors = SetExpr<Color>.literal(.blue, .red, .yellow)
            let initialStates = SetExpr<CreatureState>.literal(
                Pair.literal(.blue, 0),
                Pair.literal(.red, 0),
                Pair.literal(.yellow, 0)
            )
            let chameneoses: SharedVariable<Function<Creature, CreatureState>> = scope.sharedVar(
                "chameneoses", in: Functions(from: Creature.all, to: initialStates))
            let meetingPlace = scope.sharedVar("meetingPlace", initial: 0)
            let numMeetings = scope.sharedVar("numMeetings", initial: 0)
            let creature = ActionParameter("cid", values: Creature.finiteValues)

            Invariant("TypeOK") {
                ForAll(Creature.all) { member in
                    SetExpr<Color>.literal(.blue, .red, .yellow, .faded).contains(chameneoses[member].first())
                        && IntRange(0, through: 4).contains(chameneoses[member].second())
                }
                IntRange(0, through: 4).contains(meetingPlace)
            }
            Invariant("SumMet") {
                let creatures = TupleExpr<Creature>.literal(.one, .two, .three, .four)
                let total = Fold(creatures, startingWith: 0) { member, accumulated in
                    chameneoses[member].second() + accumulated
                }
                numMeetings != 4 || total == 8
            }

            SwiftTLA.Action("Meet", parameters: [creature]) {
                let waiting = meetingPlace.assuming(Creature.self)
                let myColor = chameneoses[creature].first()
                let otherColor = chameneoses[waiting].first()
                let complement = If(myColor == otherColor, then: myColor, else:
                    Select(from: initialColors) { color in
                        color.expr != myColor && color.expr != otherColor
                    })
                myColor != Color.faded && (
                    (meetingPlace == 0 && numMeetings < 4
                        && meetingPlace.becomes(creature.assuming(Int.self)))
                    || (meetingPlace == 0 && numMeetings >= 4
                        && chameneoses.becomes(chameneoses.updating(creature, to:
                            Pair.literal(Expr<Color>(Color.faded), chameneoses[creature].second()))))
                    || (meetingPlace != 0 && meetingPlace != creature.assuming(Int.self)
                        && meetingPlace.becomes(0)
                        && chameneoses.becomes(chameneoses
                            .updating(creature, to: Pair.literal(
                                complement, chameneoses[creature].second() + 1))
                            .updating(waiting, to: Pair.literal(
                                complement, chameneoses[waiting].second() + 1)))
                        && numMeetings.becomes(numMeetings + 1))
                )
            }
        }
    }
}
