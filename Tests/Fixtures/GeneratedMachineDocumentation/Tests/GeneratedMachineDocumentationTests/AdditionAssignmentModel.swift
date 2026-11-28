import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct AdditionAssignmentModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec {
            let counter = Algorithm(scoped: { scope in
                let value = scope.sharedVar(initiallyIn: 0...1)
                Do(Step.advance) {
                    value += 1
                    value += 9_223_372_036_854_775_807 - 3 + value * 2
                }
            })
            counter
        }
    }
}
