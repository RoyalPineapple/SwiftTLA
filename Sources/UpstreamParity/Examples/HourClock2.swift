import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClock2Model {
    public enum ClockProcess: String, CaseIterable, FiniteDomainKey {
        case clock

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.hour-clock2.process")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public static var spec: TLASpec {
        #spec("HourClock2") {
            Algorithm("HourClock2") {
                let hr = SharedVar(in: 1...12)

                Each(ClockProcess.all) { _ in
                    Do("HCnxt2") {
                        Assert(hr >= 1 && hr <= 12)
                        Assign(hr, to: (hr % 12) + 1)
                        Goto("HCnxt2")
                    }
                }
            }
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
        notes: "PlusCal-shaped singleton process. Upstream checks HC => HC2 as a property; HC2 alone has 12 states.",
    )
}
