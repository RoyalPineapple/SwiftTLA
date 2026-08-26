import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct HourClock2Model: Sendable {
    package enum Step: String, CaseIterable, Sendable {
        case HCnxt2
    }

    package enum ClockProcess: String, CaseIterable, FiniteTLAValueDomain {
        case clock

        package static var defaultValue: Self { .clock }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .string(rawValue) }
    }

    package static var spec: TLASpec {
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
    package static let hourClock2 = Entry(
        id: "SpecifyingSystems/HourClock2",
        upstreamSpec: "SpecifyingSystems",
        upstreamModule: "specifications/SpecifyingSystems/HourClock/HourClock2.tla",
        upstreamCfg: "specifications/SpecifyingSystems/HourClock/HourClock2.cfg",
        expectedDistinct: 12,
        spec: HourClock2Model.spec,
        notes: "PlusCal-shaped singleton process. Upstream checks HC => HC2 as a property; HC2 alone has 12 states.",
    )
}
