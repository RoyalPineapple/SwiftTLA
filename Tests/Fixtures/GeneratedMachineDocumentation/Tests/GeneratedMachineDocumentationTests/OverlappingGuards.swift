import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct OverlappingGuards {
    enum Step: String, CaseIterable { case pick }

    static var spec: TLASpec {
        #spec {
            let choices = Algorithm { scope in
                let value = scope.sharedVar(initiallyIn: 0...2)
                Do(Step.pick) {
                    Either {
                        When(value == 0) { Assign(value, to: 3) }
                        When(value < 2) { Assign(value, to: 4) }
                        When(value == 1, 1 / value > 0) { Assign(value, to: 5) }
                    }
                }
            }
            choices
        }
    }
}
