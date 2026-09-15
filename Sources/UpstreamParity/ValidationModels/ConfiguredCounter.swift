import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ConfiguredCounter {
    package enum Process: String, FiniteTLAValueDomain { case only }
    package enum Step: String, CaseIterable { case advance }

    package static var spec: TLASpec {
        #spec("ConfiguredCounter") { scope in
            let limit = scope.parameter(as: Int.self, in: 1...100)
            let stopAtLimit = scope.parameter(as: Bool.self)
            let value = scope.sharedVar("value", initial: 0)
            let previous = scope.sharedVar("previous", initial: 0)
            let copied = scope.sharedVar("copied", initial: 0)
            Algorithm("Counter") {
                Each(Process.all) { _ in
                    Do(Step.advance, when: value < limit) {
                        let saved = value
                        Assign(value, to: value + 1)
                        Assign(previous, to: saved)
                        Assign(copied, to: value)
                        If(stopAtLimit && value == limit) {
                            Stop()
                        } else: {
                            Goto(Step.advance)
                        }
                    }
                }
            }
            Invariant("OrderedCopy") { copied == value }
            Invariant("Bounded") { value <= limit }
            Reachable("AtLimit") { value == limit }
            Validation("Completes at two") {
                Bind(limit, to: 2)
                Bind(stopAtLimit, to: true)
            }
            Validation("Deadlocks at four") {
                Bind(limit, to: 4)
                Bind(stopAtLimit, to: false)
            }.expectDeadlock(.violated)
        }
    }
}
