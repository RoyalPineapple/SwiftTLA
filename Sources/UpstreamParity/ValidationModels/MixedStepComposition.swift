import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct MixedStepComposition {
    package enum Process: String, FiniteTLAValueDomain { case only }
    package enum Step: String, CaseIterable { case advance, reset }

    package static var spec: TLASpec {
        #spec { scope in
            let value = scope.sharedVar(initial: 0)
            let Advance = Algorithm {
                Each(Process.all, scoped: { _, process in
                    let advanced = process.localVar(initial: false)
                    Do(Step.advance, when: value < 2) {
                        If(advanced) {
                            Assign(value, to: 2)
                        } else: {
                            Assign(value, to: 1)
                        }
                        Assign(advanced, to: true)
                        Goto(Step.advance)
                    }
                })
            }
            Advance
            Do(Step.reset, when: value == 1) {
                Assign(value, to: 0)
            }
            let Complete = Validation {}.expectDeadlock(.violated)
            Complete
        }
    }
}
