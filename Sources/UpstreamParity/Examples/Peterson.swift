import SwiftTLA
import SwiftTLAMacros

/// Peterson's two-process mutual-exclusion algorithm from the upstream
/// PlusCal auxiliary-variables collection.
@TLAModel
public struct PetersonModel: Sendable {
    public enum Process: Int, CaseIterable, FiniteDomainKey {
        case one = 1
        case two = 2

        public static var defaultValue: Self { .one }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(
            rawValue: "upstream.locks-auxiliary-vars.peterson.process"
        )

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case a0
        case a1
        case a2
        case a3
        case cs
        case a4
    }

    public static var spec: TLASpec {
        #spec("Peterson") {
            Extends(.integers)
            Algorithm("Peterson", scoped: { scope in
                let c = scope.sharedVar("c", initial: Function<Process, Bool>.literal(
                    (.one, false), (.two, false)
                ))
                let turn = scope.sharedVar("turn", initial: Process.one)

                Each(Process.all) { process in
                    Do(Step.a0) {
                        Skip()
                    }
                    Do(Step.a1) {
                        Assign(c, to: c.updating(process, to: true))
                    }
                    Do(Step.a2) {
                        Assign(turn, to: If(
                            process == .one,
                            then: Process.two,
                            else: Process.one
                        ))
                    }
                    Do(Step.a3) {
                        Let(If(
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
                        Assign(c, to: c.updating(process, to: false))
                        Goto(Step.a0)
                    }
                }

                Invariant("TypeOK") {
                    (c[.one] == false || c[.one] == true)
                        && (c[.two] == false || c[.two] == true)
                }
            })
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
