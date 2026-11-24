import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct HourClock2Model: Sendable {
    package enum Step: String, CaseIterable { case HCnxt2 }

    package static var spec: TLASpec {
        #spec("HourClock2") {
            let HCini = Invariant()
            let Clock = Algorithm(scoped: { scope in
                let hr = scope.sharedVar(initiallyIn: 1...12)
                While(Step.HCnxt2, true) {
                    hr.set(hr % 12 + 1)
                }
                HCini { hr >= 1 && hr <= 12 }
            })
            Clock
            let apUpstream = Validation(label: "AP Upstream") {}
            apUpstream
        }
    }
}
