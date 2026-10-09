import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/Chameneos/Chameneos.tla
@TLAModel
package struct ChameneosModel: Sendable {
    package enum Hue: String, CaseIterable, FiniteTLAValueDomain {
        case blue, red, yellow
        package static var defaultValue: Self { .blue }
        package static let finiteValues = allCases
    }

    package enum FadedToken: String, CaseIterable, FiniteTLAValueDomain {
        case faded = "Faded"
        package static var defaultValue: Self { .faded }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum EmptyMeetingPlace: String, CaseIterable, FiniteTLAValueDomain {
        case empty = "MeetingPlaceEmpty"
        package static var defaultValue: Self { .empty }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package typealias Color = OneOf<Hue, FadedToken>
    package typealias CreatureState = Pair<Color, Int>
    package typealias WaitingPlace = OneOf<Int, EmptyMeetingPlace>
    package enum Step: String, CaseIterable { case Next }

    package static var spec: TLASpec {
        #spec("Chameneos") { scope in
            Import(FunctionsModule.module)
            let N = scope.parameter(as: Int.self, in: Int.all)
            let M = scope.parameter(as: Int.self, in: Int.all)
            let Faded = scope.parameter(as: FadedToken.self, in: Set<FadedToken>([.faded]))
            let MeetingPlaceEmpty = scope.parameter(as: EmptyMeetingPlace.self,
                in: Set<EmptyMeetingPlace>([.empty]))
            let TypeOK = Invariant()
            let SumMet = Invariant()
            Assume(N > 0 && M > 0)
            let creatureIDs = IntRange(1, through: M)
            let initialColors = SetExpr<Hue>.literal(.blue, .red, .yellow)
            let initialStates = SetExpr<CreatureState>.literal(
                Pair.literal(Color.first(Hue.blue), 0),
                Pair.literal(Color.first(Hue.red), 0),
                Pair.literal(Color.first(Hue.yellow), 0)
            )
            let chameneoses: SharedVariable<[Int: CreatureState]> = scope.sharedVar(in: Functions(from: creatureIDs, to: initialStates))
            let fadedColor = Color.second(Faded)
            let empty = WaitingPlace.second(MeetingPlaceEmpty)
            let meetingPlace: SharedVariable<WaitingPlace> = scope.sharedVar(initial: empty)
            let numMeetings = scope.sharedVar(initial: 0)

            Do(Step.Next) {
                With(creatureIDs) { cid in
                    When(chameneoses[cid].first() != fadedColor)
                    If(meetingPlace == empty) {
                        If(numMeetings < N) {
                            Assign(meetingPlace, to: WaitingPlace.first(cid))
                        } else: {
                            Assign(chameneoses[cid], to: Pair.literal(
                                fadedColor, chameneoses[cid].second()))
                        }
                    } else: {
                        When(meetingPlace != WaitingPlace.first(cid))
                        Let(meetingPlace.assuming(Int.self)) { waiting in
                            let myColor = chameneoses[cid].first().assuming(Hue.self)
                            let otherColor = chameneoses[waiting].first().assuming(Hue.self)
                            Let(If(myColor == otherColor, then: myColor, else:
                                Select(from: initialColors) { color in
                                    color.expr != myColor && color.expr != otherColor
                                })) { newColor in
                                Assign(meetingPlace, to: empty)
                                Assign(chameneoses[cid], to: Pair.literal(
                                    Color.first(newColor.expr), chameneoses[cid].second() + 1))
                                Assign(chameneoses[waiting], to: Pair.literal(
                                    Color.first(newColor.expr), chameneoses[waiting].second() + 1))
                                Assign(numMeetings, to: numMeetings + 1)
                            }
                        }
                    }
                }
            }
            TypeOK {
                chameneoses.keys == creatureIDs
                    && ForAll(in: creatureIDs) { id in
                        let color = chameneoses[id.expr].first()
                        return (color == Color.first(Hue.blue)
                            || color == Color.first(Hue.red)
                            || color == Color.first(Hue.yellow)
                            || color == fadedColor)
                            && IntRange(0, through: N).contains(chameneoses[id.expr].second())
                    }
                    && (meetingPlace == empty || Exists(in: creatureIDs) { id in
                        meetingPlace == WaitingPlace.first(id.expr)
                    })
            }

            SumMet {
                let meetings = SequenceMapping(length: M) { index in
                    chameneoses[index.expr].second()
                }
                let total = Fold(meetings, startingWith: 0) { count, accumulated in
                    count + accumulated
                }
                numMeetings != N || total == 2 * N
            }

            let Chameneos = Validation {
                Bind(N, to: 4)
                Bind(M, to: 4)
                Bind(Faded, to: FadedToken.faded)
                Bind(MeetingPlaceEmpty, to: EmptyMeetingPlace.empty)
            }.checkingDeadlock(false)
            Chameneos
        }
    }
}
