import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct HourRangeFixture {
    enum Step: String, CaseIterable { case tick }

    static var spec: TLASpec {
        #spec("HourRangeFixture") {
            let ValidHour = Invariant()
            let clock = Algorithm { scope in
                let hour = scope.sharedVar(initial: -1)
                Loop(Step.tick) { hour += 1 }
                ValidHour { (0...23).contains(hour) }
            }
            clock
        }
    }
}
