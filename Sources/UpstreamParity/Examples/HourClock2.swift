import SwiftTLA

extension Example {
    public static let hourClock2 = Entry(
        id: "SpecifyingSystems/HourClock2",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/HourClock/HourClock2.tla",
        upstreamCfg: "specifications/SpecifyingSystems/HourClock/HourClock2.cfg",        spec: {
            let hr = Var<Int>("hr", value: 1)
            return TLASpec("HourClock2") {
                Extends("Naturals")
                Variable(hr, in: 1...12)
                Action("HCnxt2") {
                    hr.becomes((hr % 12) + 1)
                }
                Invariant("HCini") { hr >= 1 && hr <= 12 }
            }
        }(),
        notes: "Upstream checks HC => HC2 as property; state space of HC2 alone is 12.",
    )

}
