// Example ID: generated-machine-bounded-model

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundedCounter {
    enum Process: String, FiniteTLAValueDomain {
        case only
    }

    enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("BoundedCounter") {
            Algorithm("BoundedCounter", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance, when: value < 1) {
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            })
        }
    }
}
