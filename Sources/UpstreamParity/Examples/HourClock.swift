import SwiftTLA

extension Example {
    public static let hourClock = Entry(
        id: "SpecifyingSystems/HourClock",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/HourClock/HourClock.tla",
        upstreamCfg: "specifications/SpecifyingSystems/HourClock/HourClock.cfg",
        expectedDistinct: 12,
        expectedResult: "success",
        spec: {
            let hr = Var<Int>("hr", value: 1)
            return TLASpec("HourClock") {
                Extends("Naturals")
                Variable(hr, in: 1...12)
                Action("HCnxt") {
                    (hr != 12) && hr.becomes(hr + 1) ||
                    (hr == 12) && hr.becomes(1)
                }
                Invariant("HCini") { hr >= 1 && hr <= 12 }
            }
        }(),
        notes: "Upstream SPECIFICATION HC; export uses Spec. TLC = 12.",
        matchesUpstreamTLC: true
    )

}
