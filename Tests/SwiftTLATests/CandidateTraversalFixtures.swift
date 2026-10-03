import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct OrderedCandidateChoices {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec("OrderedCandidateChoices") { scope in
            let first = scope.sharedVar(initial: 0)
            let second = scope.sharedVar(initial: 0)
            let previous = scope.sharedVar(initial: -1)
            Do(Step.pick) {
                With(IntRange(1, through: 2)) { selected in
                    With(IntRange(1, through: 2)) { other in
                        When(selected != 2 || other != 1)
                        Assign(previous, to: first)
                        Assign(first, to: selected)
                        Assign(second, to: other)
                    }
                }
            }
        }
    }
}
