// This clock computes the next hour with modular arithmetic in the Apalache example.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/HourClock/APHourClock2.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct HourClock2Model: ParameterlessGeneratedModel {
    package enum Step: String, CaseIterable { case tick = "HCnxt2" }

    package static var spec: TLASpec {
        #spec("HourClock2") {
            let Clock = Algorithm { scope in
                let hr = scope.sharedVar(initiallyIn: 1...12)
                Loop(Step.tick) {
                    hr.set(hr % 12 + 1)
                }
                Invariant("HCini") { (1...12).contains(hr) }
            }
            Clock
            Validation("apUpstream", label: "AP Upstream") {}
        }
    }
}
