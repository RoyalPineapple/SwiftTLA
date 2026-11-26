// A clock can start at any hour and wraps from twelve to one on a tick.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/HourClock/HourClock.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct HourClockModel: Sendable {
    package enum Step: String, CaseIterable { case tick = "HCnxt" }

    package static var spec: TLASpec {
        #spec("HourClock") {
            let Clock = Algorithm { scope in
                // Every hour in this range is a valid starting state.
                let hr = scope.sharedVar(initiallyIn: 1...12)
                Loop(Step.tick) {
                    If(hr != 12) {
                        hr += 1
                    } else: {
                        hr.set(1)
                    }
                }
                Invariant("HCini") { (1...12).contains(hr) }
            }
            Clock
            Validation("Upstream") {}
        }
    }
}

extension Example {
    package static let hourClock = FiniteModelFixture(
        expectedDistinct: 12,
        maximumStateLimit: 50_000,
        spec: HourClockModel.spec,
    )
}
