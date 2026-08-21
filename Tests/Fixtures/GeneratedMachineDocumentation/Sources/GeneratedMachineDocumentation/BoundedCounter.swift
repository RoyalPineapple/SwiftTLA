// Example ID: generated-machine-bounded-model

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundedCounter {
    enum Process: String, FiniteDomainKey {
        case only

        static var defaultValue: Self { .only }
        static let formalDomain: [Process] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "documentation.counter.process")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, PlusCalLabel, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("BoundedCounter") {
            Algorithm("BoundedCounter") {
                let value = SharedVar("value", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            }
        }
    }
}
