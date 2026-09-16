import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GuardedEndlessLoop {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("GuardedEndlessLoop") {
            Algorithm("Loop", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                While(Step.advance, true) {
                    When(value < 1)
                    Assign(value, to: value + 1)
                }
            })
        }
    }
}

@TLAModel
struct FinishingLoop {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("FinishingLoop") {
            Algorithm("Loop", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                While(Step.advance, value < 1) {
                    Assign(value, to: value + 1)
                }
            })
        }
    }
}
