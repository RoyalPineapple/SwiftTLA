import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct OrderedCallModel {
    package enum Step: String, CaseIterable { case start, enter, finished }
    package enum ProcedureName: String, CaseIterable { case copy }

    package static var spec: TLASpec {
        #spec("OrderedCall") { scope in
            let input = scope.sharedVar(initial: 0)
            let output = scope.sharedVar(initial: 0)
            let OrderedCall = Algorithm {
                Procedure(ProcedureName.copy, parameters: Int.self) { value in
                    Do(Step.enter) {
                        Assign(output, to: value.expr)
                        Return()
                    }
                }
                Do(Step.start) {
                    Assign(input, to: 7)
                    Call(ProcedureName.copy, with: input.expr)
                }
                Do(Step.finished) { Stop() }
            }
            OrderedCall
            let Complete = Validation {}
            Complete
        }
    }
}
