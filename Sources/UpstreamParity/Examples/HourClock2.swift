import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClock2Model {
    public static var spec: TLASpec {
        TLASpec("HourClock2") {
            Extends("Naturals")
            let hr = Var<Int>("hr")
            Variable(hr, in: 1...12)
            Action("HCnxt2") {
                hr.becomes((hr % 12) + 1)
            }
            Invariant("HCini") { hr >= 1 && hr <= 12 }
        }
    }
}

extension Example {
    public static let hourClock2 = Entry(
        id: "SpecifyingSystems/HourClock2",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/HourClock/HourClock2.tla",
        upstreamCfg: "specifications/SpecifyingSystems/HourClock/HourClock2.cfg",
        expectedDistinct: 12,
        spec: HourClock2Model.spec,
        notes: "Upstream checks HC => HC2 as property; state space of HC2 alone is 12.",
    )
}
