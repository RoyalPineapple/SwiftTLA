import SwiftTLA
import SwiftTLAMacros

/// The two-process lock example from the PlusCal auxiliary-variables
/// collection. `l2` explicitly returns to `l0`, mirroring the source loop.
@TLAModel
public struct LockModel: Sendable {
    public enum Process: Int, CaseIterable, FiniteDomainKey {
        case one = 1
        case two = 2

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(
            rawValue: "upstream.locks-auxiliary-vars.lock.process"
        )

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case l0
        case l1
        case cs
        case l2
    }

    public static var spec: TLASpec {
        #spec("Lock") {
            Extends("Integers")
            Algorithm("Lock") {
                let lock = SharedVar(initial: 1)
                let acquire = Macro { (value: MacroParameter<Int>) in
                    Await(value == 1)
                    Assign(value, to: 0)
                }
                let release = Macro { (value: MacroParameter<Int>) in
                    Assign(value, to: 1)
                }

                Each(Process.all) { _ in
                    Do(Step.l0) {
                        Skip()
                    }
                    Do(Step.l1) {
                        acquire(lock)
                    }
                    Do(Step.cs) {
                        Skip()
                    }
                    Do(Step.l2) {
                        release(lock)
                        Goto(Step.l0)
                    }
                }

                Invariant("TypeOK") {
                    lock >= 0 && lock <= 1
                }
            }
        }
    }
}

extension Example {
    public static let lockTwoProcess = Entry(
        id: "locks_auxiliary_vars/Lock_N2",
        upstreamSpec: "locks_auxiliary_vars",
        upstreamModule: "specifications/locks_auxiliary_vars/Lock.tla",
        upstreamCfg: "specifications/locks_auxiliary_vars/Lock.cfg",
        expectedDistinct: 12,
        spec: LockModel.spec,
        notes: "Two-process PlusCal lock. TLC = 12."
    )
}
