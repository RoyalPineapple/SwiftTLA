import SwiftTLA
import SwiftTLAMacros

/// Peterson's two-process mutual-exclusion algorithm from the upstream
/// PlusCal auxiliary-variables collection.
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
                        Assign(c, to: c.stateExpr.updated(at: process, to: true))
                    }
                    Do(Step.a2) {
                        Assign(turn, to: Expr<Process>.ifThenElse(
                            process == .one,
                            then: Process.two,
                            else: Process.one
                        ))
                    }
                    Do(Step.a3) {
                        Let(Expr<Process>.ifThenElse(
                                process == .one,
                                then: Process.two,
                                else: Process.one
                            )) { other in
                            Await(c[other] == false || turn.stateExpr == process.stateExpr)
                        }
                    }
                    Do(Step.cs) {
                        Skip()
                    }
                    Do(Step.a4) {
                        Assign(c, to: c.stateExpr.updated(at: process, to: false))
                        Goto(Step.a0)
                    }
                }

                Invariant("TypeOK") {
                    (c[.one] == false || c[.one] == true)
                        && (c[.two] == false || c[.two] == true)
                }
            }
        }
    }
}

extension Example {
    public static let petersonTwoProcess = Entry(
        id: "locks_auxiliary_vars/Peterson_N2",
        upstreamSpec: "locks_auxiliary_vars",
        upstreamModule: "specifications/locks_auxiliary_vars/Peterson.tla",
        upstreamCfg: "specifications/locks_auxiliary_vars/Peterson.cfg",
        expectedDistinct: 42,
        spec: PetersonModel.spec,
        notes: "Two-process PlusCal Peterson mutex with function-shaped flags and explicit control state."
    )
}
