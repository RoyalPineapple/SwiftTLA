import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SequentialCounter {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec {
            let counter = Algorithm { scope in
                let value = scope.sharedVar(initial: 0)
                Do(Step.advance, when: value < 5) {
                    value += 1
                    Stop()
                }
            }
            counter
        }
    }
}
