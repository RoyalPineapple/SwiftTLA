import SwiftTLA
import SwiftTLAMacros

/// Peterson's two-process mutual exclusion algorithm.
///
/// This is a direct PlusCal-shaped port: each `Do` has the published label,
/// and each process is scheduled independently. `c` and `turn` are the only
/// shared algorithm state; the lowerer owns the formal program-counter map.
@TLAModel
public struct PetersonModel {
    public enum Process: Int, CaseIterable, FiniteDomainKey {
        case one = 1
        case two = 2

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(
            rawValue: "upstream.locks-auxiliary-vars.peterson.process"
        )

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case a0
        case a1
        case a2
        case a3
        case cs
        case a4
    }

    public static var spec: TLASpec {
        #spec("Peterson") {
            Extends("Integers")
            Algorithm("Peterson") {
                let c = SharedVar(initial: Function<Process, Bool>.literal(
                    (.one, false), (.two, false)
                ))
                let turn = SharedVar(initial: Process.one)

                Each(Process.all) { process in
                    Do(Step.a0) {
                        Skip()
                    }

                    Do(Step.a1) {
                        Assign(c, to: c.updating(process, to: true))
                    }

                    Do(Step.a2) {
                        If(process == .one) {
                            Assign(turn, to: Process.two)
                        } else: {
                            Assign(turn, to: Process.one)
                        }
                    }

                    Do(Step.a3) {
                        Either {
                            When(process == .one)
                            When(c[.two] == false || turn == .one)
                        } or: {
                            When(process == .two)
                            When(c[.one] == false || turn == .two)
                        }
                    }

                    Do(Step.cs) {
                        Skip()
                    }

                    Do(Step.a4) {
                        Assign(c, to: c.updating(process, to: false))
                        Goto(Step.a0)
                    }
                }
            }
        }
    }
}

extension Example {
    public static let peterson = Entry(
        id: "locks_auxiliary_vars/Peterson",
        upstreamSpec: "locks_auxiliary_vars",
        upstreamModule: "specifications/locks_auxiliary_vars/Peterson.tla",
        upstreamCfg: "specifications/locks_auxiliary_vars/Peterson.cfg",
        expectedDistinct: 42,
        spec: PetersonModel.spec,
        notes: "Two-process Peterson mutual exclusion, authored as labeled PlusCal processes."
    )
}
