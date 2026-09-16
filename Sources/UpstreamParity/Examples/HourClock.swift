import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct HourClockModel: Sendable {
    package enum Step: String, CaseIterable { case HCnxt }

    package static var spec: TLASpec {
        #spec("HourClock") {
            let HCini = Invariant()
            Algorithm("Clock", scoped: { scope in
                let hr = scope.sharedVar("hr", in: 1...12)
                While(Step.HCnxt, true) {
                    If(hr != 12) {
                        Assign(hr, to: hr + 1)
                    } else: {
                        Assign(hr, to: 1)
                    }
                }
                HCini { hr >= 1 && hr <= 12 }
            })
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
