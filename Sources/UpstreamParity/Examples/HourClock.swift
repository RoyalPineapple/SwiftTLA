import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClockModel {
    public enum ClockProcess: String, CaseIterable, FiniteDomainKey {
        case clock

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.hour-clock.process")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public static var spec: TLASpec {
        #spec("HourClock") {
            Algorithm("HourClock") {
                let hr = SharedVar(in: 1...12)

                Each(ClockProcess.all) { _ in
                    Do("HCnxt") {
                        Either {
                            When(hr != 12)
                            Assign(hr, to: hr + 1)
                        } or: {
                            When(hr == 12)
                            Assign(hr, to: 1)
                        }
                        Goto("HCnxt")
                    }
                }
                Invariant("HCini") { hr >= 1 && hr <= 12 }
            }
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
        notes: "PlusCal-shaped singleton process. TLC = 12.",
    )
}
