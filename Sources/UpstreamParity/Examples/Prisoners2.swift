import SwiftTLA
import SwiftTLAMacros

/// The two-switch prisoner puzzle.
///
/// The scheduler makes the nondeterministic visitor choice explicit. The
/// shared switch state and per-prisoner signal counts are typed formal values.
@TLAModel
package struct PrisonersModel: Sendable {
    package enum NonCounterPrisoner: String, CaseIterable, FiniteTLAValueDomain {
        case two = "p2"
        case three = "p3"
        case four = "p4"

        package static var defaultValue: Self { .two }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Scheduler: String, CaseIterable, FiniteTLAValueDomain {
        case warden

        static var defaultValue: Self { .warden }
        static let finiteValues = allCases

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case chooseVisitor
    }

    package static var spec: TLASpec {
        #spec("Prisoners") {
            Extends(.naturals)
            Algorithm("Prisoners", scoped: { scope in
                let switchAUp = scope.sharedVar("switchAUp", in: SetExpr<Bool>.literal(true, false))
                let switchBUp = scope.sharedVar("switchBUp", in: SetExpr<Bool>.literal(true, false))
                let timesSwitched = scope.sharedVar("timesSwitched", initial: Function<NonCounterPrisoner, Int>.literal(
                    (.two, 0), (.three, 0), (.four, 0)
                ))
                let count = scope.sharedVar("count", initial: 0)

                Each(Scheduler.all) { _ in
                    Do(Step.chooseVisitor) {
                        Either {
                            Either {
                                When(switchAUp == true)
                                Assign(switchAUp, to: false)
                                Assign(count, to: count + 1)
                            } or: {
                                When(switchAUp == false)
                                Assign(switchBUp, to: !(switchBUp == true))
                            }
                        } or: {
                            With(NonCounterPrisoner.all) { prisoner in
                                Either {
                                    When(switchAUp == false)
                                    When(timesSwitched[prisoner] < 2)
                                    Assign(switchAUp, to: true)
                                    Assign(timesSwitched, to: timesSwitched.updating(prisoner) { value in value + 1 })
                                } or: {
                                    When(!(switchAUp == false && timesSwitched[prisoner] < 2))
                                    Assign(switchBUp, to: !(switchBUp == true))
                                }
                                Assert(count >= 0 && count <= 7)
                            }
                        }
                        Goto(Step.chooseVisitor)
                    }
                }
            })
        }
    }
}

extension Example {
    package static let prisoners4 = Entry(
        id: "Prisoners/Prisoners",
        upstreamSpec: "Prisoners",
        upstreamModule: "specifications/Prisoners/Prisoners.tla",
        upstreamCfg: "specifications/Prisoners/Prisoners.cfg",
        expectedDistinct: 214,
        maximumStateLimit: 50_000,
        spec: PrisonersModel.spec,
        notes: "Four prisoners, typed switch state and signal function. TLC = 214."
    )
}
