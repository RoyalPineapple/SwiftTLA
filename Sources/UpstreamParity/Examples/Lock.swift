import SwiftTLA
import SwiftTLAMacros

/// The two-process lock example from the PlusCal auxiliary-variables
/// collection. `l2` explicitly returns to `l0`, mirroring the source loop.
@TLAModel
package struct LockModel: Sendable {
    package enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case one = 1
        case two = 2

        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case l0
        case l1
        case cs
        case l2
    }

    package static var spec: TLASpec {
        #spec("Lock") {
            Extends(.integers)
            Algorithm("Lock", scoped: { scope in
                let lock = scope.sharedVar("lock", initial: 1)
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
            })
        }
    }
}

extension Example {
    package static let lockTwoProcess = FiniteModelFixture(
        expectedDistinct: 12,
        maximumStateLimit: 50_000,
        spec: LockModel.spec,
    )
}
