import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct HourClock2Model: Sendable {
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
            let apUpstream = Validation(label: "AP Upstream") {}
            apUpstream
        }
    }
}
