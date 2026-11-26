// The modular clock step is checked against the original twelve-hour clock.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/HourClock/HourClock2.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct PublishedHourClock2Model: Sendable {
    private enum Step: String, CaseIterable { case tick = "HCnxt" }

    package static var spec: TLASpec {
        #spec("PublishedHourClock2") { scope in
            let hr = scope.sharedVar(initiallyIn: 1...12)
            Do(Step.tick) {
                hr.set(If(hr != 12, then: hr + 1, else: 1))
            }

            let moduloClock = Instance(of: HourClock2Model.self) {}
            moduloClock
            let HC2 = Refinement(instance: moduloClock, behavior: .initialAndNext) {
                Map(\.hr, from: hr)
            }
            HC2
            Validation("Upstream") {}.checking(only: [HC2])
        }
    }
}
