import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ScopedControlProjectionMachine {
    enum Step: String, CaseIterable { case start, enter, resume, finish }
    enum Routine: String, CaseIterable { case outer, inner }

    static var spec: TLASpec {
        #spec("ScopedControlProjectionMachine") {
            let algorithm = Algorithm(label: "ScopedControlProjectionMachine", scoped: { scope in
                Procedure(Routine.outer) {
                    Do(Step.enter) { Call(Routine.inner) }
                    Do(Step.resume) { Return() }
                }
                Procedure(Routine.inner) {
                    Do(Step.enter) { Return() }
                }
                Do(Step.start) { Call(Routine.outer) }
                Do(Step.finish) { Stop() }
            })
            algorithm
        }
    }
}
