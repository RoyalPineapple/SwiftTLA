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
            let Upstream = Validation {}
            Upstream
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
