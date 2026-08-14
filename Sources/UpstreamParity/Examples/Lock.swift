import SwiftTLA
import SwiftTLAMacros

/// The two-process lock example from the PlusCal auxiliary-variables
/// collection. `l2` explicitly returns to `l0`, mirroring the source loop.
@TLAModel
public struct LockModel {
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

                Each(Process.all) { _ in
                    Do(Step.l0) {
                        Skip()
                    }
                    Do(Step.l1) {
                        Await(lock == 1)
                        Assign(lock, to: 0)
                    }
                    Do(Step.cs) {
                        Skip()
                    }
                    Do(Step.l2) {
                        Assign(lock, to: 1)
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
        upstreamCfg: nil,
        expectedDistinct: 12,
        spec: LockModel.spec,
        notes: "Two-process PlusCal lock. TLC = 12."
    )
}
