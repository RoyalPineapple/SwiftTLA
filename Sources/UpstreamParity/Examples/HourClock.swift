import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClockModel: Sendable {
    public static var spec: TLASpec {
        #spec("HourClock") {
            let hr = SharedVar(in: 1...12)
            Action("HCnxt") {
                (hr != 12 && hr.becomes(hr + 1)) ||
                (hr == 12 && hr.becomes(1))
            }
            Invariant("HCini") { hr >= 1 && hr <= 12 }
        }
    }
}

extension Example {
    public static let hourClock = Entry(
        id: "SpecifyingSystems/HourClock",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/HourClock/HourClock.tla",
        upstreamCfg: "specifications/SpecifyingSystems/HourClock/HourClock.cfg",
        expectedDistinct: 12,
        spec: HourClockModel.spec,
        notes: "Direct single-action TLA+ model. It exactly matches the published 12-state graph.",
    )
}
