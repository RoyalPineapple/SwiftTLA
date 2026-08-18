import SwiftTLA
import SwiftTLAMacros

/// The single-switch prisoner puzzle from *Specifying Systems*.
///
/// A single scheduler process chooses the prisoner who enters the room. The
/// model keeps the choice formal with `With`, so no host-language loop or UI
/// policy decides who visits next.
@TLAModel
public struct PrisonerModel: Sendable {
    public enum Prisoner: String, CaseIterable, FiniteDomainKey {
        case alice = "Alice"
        case bob = "Bob"
        case eve = "Eve"

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "examples.prisoner.prisoner")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Light: String, TLAValueType {
        case off
        case on
    }

    private enum Scheduler: String, CaseIterable, FiniteDomainKey {
        case warden

        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "examples.prisoner.scheduler")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case chooseVisitor
    }

    public static var spec: TLASpec {
        #spec("Prisoner") {
            Extends("Naturals")
            Algorithm("Prisoner") {
                let counter = SharedVar(initial: Prisoner.alice)
                let count = SharedVar(initial: 1)
                let announced = SharedVar(initial: false)
                let signalled = SharedVar(initial: Function<Prisoner, Int>.literal(
                    (.alice, 0), (.bob, 0), (.eve, 0)
                ))
                let light = SharedVar(initial: Light.off)
                let hasVisited = SharedVar(initial: SetExpr<Prisoner>())

                Each(Scheduler.all) { _ in
                    Do(Step.chooseVisitor) {
                        With(Prisoner.all) { prisoner in
                            Either {
                                When(counter == prisoner)
                                Either {
                                    When(light == Light.on)
                                    Assign(light, to: Light.off)
                                    Assign(count, to: count + 1)
                                    Assign(announced, to: count + 1 >= 3)
                                } or: {
                                    Assign(announced, to: count >= 3)
                                }
                            } or: {
                                Either {
                                    When(counter != prisoner)
                                    When(light == Light.off)
                                    When(signalled[prisoner] < 1)
                                    Assign(light, to: Light.on)
                                    Assign(signalled, to: signalled.updating(prisoner) { value in value + 1 })
                                } or: {
                                    When(counter != prisoner)
                                    When(!(light == Light.off && signalled[prisoner] < 1))
                                }
                            }
                            Assign(hasVisited, to: hasVisited.inserting(prisoner))
                            Assert(announced == false || hasVisited == SetExpr<Prisoner>.literal(.alice, .bob, .eve))
                        }
                        Goto(Step.chooseVisitor)
                    }
                }
            }
        }
    }
}

extension Example {
    public static let prisonerN3 = Entry(
        id: "Prisoners_Single_Switch/Prisoner",
        upstreamSpec: "Prisoners_Single_Switch",
        upstreamModule: "specifications/Prisoners_Single_Switch/Prisoner.tla",
        upstreamCfg: "specifications/Prisoners_Single_Switch/Prisoner.cfg",
        expectedDistinct: 16,
        spec: PrisonerModel.spec,
        notes: "N=3, typed signalling function, visited set, and formal visitor choice. TLC = 16."
    )
}
