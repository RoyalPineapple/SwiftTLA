import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConstrainedParameterizedChoice {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.choose, over: Set<Int>([1, 2])) { branch in
                Choose(1...3) { selected in
                    Assign(value, to: selected.expr)
                }
            }
            Constraint(value <= 2)
        }
    }
}
