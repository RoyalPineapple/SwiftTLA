import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct HourClockModel: Sendable {
    package static var spec: TLASpec {
        #spec("HourClock") { scope in
            let hr = scope.sharedVar("hr", in: 1...12)
            SwiftTLA.Action("HCnxt") {
                (hr != 12 && hr.becomes(hr + 1)) ||
                (hr == 12 && hr.becomes(1))
            }
            Invariant("HCini") { hr >= 1 && hr <= 12 }
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
