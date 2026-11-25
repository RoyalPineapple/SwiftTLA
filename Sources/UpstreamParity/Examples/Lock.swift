import SwiftTLA
import SwiftTLAMacros

/// The two-process lock example from the PlusCal auxiliary-variables
/// collection. `l2` explicitly returns to `l0`, mirroring the source loop.
@TLAModel
package struct LockModel: ParameterlessGeneratedModel {
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
            let Lock = Algorithm { scope in
                let lock = scope.sharedVar(initial: 1)
                let acquire = Macro { (value: MacroParameter<Int>) in
                    When(value == 1)
                    value.set(0)
                }
                let release = Macro { (value: MacroParameter<Int>) in
                    value.set(1)
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
                    (0...1).contains(lock)
                    Process.all.allSatisfy { process in
                        process.isAt(anyOf: Step.l0, .l1, .cs, .l2)
                    }
                }
                let holders = Process.all.filter { process in process.isAt(anyOf: Step.cs, .l2) }
                Invariant("LockInv") {
                    holders.count <= 1
                    holders.isEmpty || lock == 0
                }
            }
            Lock
            let twoProcess = Validation(label: "Lock") {}
            twoProcess
        }
    }
}
