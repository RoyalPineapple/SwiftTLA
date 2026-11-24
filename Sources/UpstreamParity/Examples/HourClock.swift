import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct HourClockModel: Sendable {
    package enum Step: String, CaseIterable { case HCnxt }

    package static var spec: TLASpec {
        #spec("HourClock") {
            let HCini = Invariant()
            let Clock = Algorithm(scoped: { scope in
                let hr = scope.sharedVar(initiallyIn: 1...12)
                Loop(Step.HCnxt) {
                    If(hr != 12) {
                        hr += 1
                    } else: {
                        hr.set(1)
                    }
                }
                HCini { hr >= 1 && hr <= 12 }
            })
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
