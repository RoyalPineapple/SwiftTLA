// Example ID: generated-machine-nested-observable

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterScreenModel {
    enum Process: String, FiniteTLAValueDomain {
        case only
    }

    enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterScreenModel") {
            Algorithm("CounterScreenModel", scoped: { scope in
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
