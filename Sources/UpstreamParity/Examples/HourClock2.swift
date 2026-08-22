import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClock2Model: Sendable {
    public enum Step: String, PlusCalLabel, CaseIterable {
        case HCnxt2
    }

    public enum ClockProcess: String, CaseIterable, FiniteDomainKey {
        case clock

        public static var defaultValue: Self { .clock }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.hour-clock2.process")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public static var spec: TLASpec {
        #spec("HourClock2") {
            Algorithm("HourClock2", scoped: { scope in
                let hr = scope.sharedVar("hr", in: 1...12)

                Each(ClockProcess.all) { _ in
                    Do(Step.HCnxt2) {
                        Assign(hr, to: (hr % 12) + 1)
                        Goto(Step.HCnxt2)
                    }
                }
                Invariant("HCini") { hr >= 1 && hr <= 12 }
            })
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
