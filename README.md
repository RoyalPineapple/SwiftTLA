# SwiftTLA

**SwiftTLA brings formal programming into Swift.**

**SwiftTLA generates typed Swift state machines and explores reachable behavior within a declared finite configuration.**

Define a system's state, actions, algorithms, invariants, and temporal
properties in Swift. SwiftTLA compiles that source model into a machine that
your app can run. The same compilation supplies bounded exploration and
TLA+/PlusCal bundles for TLC.

**One specification. Production behavior. Formal evidence.**

```text
Swift source model
        │
        ▼
Compiled specification
 ├── Generated Swift machine
 ├── Model checker
 └── TLA+ and PlusCal bundles
```

## Write the system rules

Use `#spec` and `Algorithm` to define the behavior that matters. The DSL
expresses data, transitions, procedures, invariants, and temporal properties.

```swift
import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct ClockModel: Sendable {
    private enum Step: String, PlusCalLabel, CaseIterable {
        case tick
    }

    public static var spec: TLASpec {
        #spec("Clock") {
            Algorithm("Clock") {
                let hour = SharedVar("hour", in: 0...23)
                let minute = SharedVar("minute", in: 0...59)
                let second = SharedVar("second", in: 0...59)

                While(Step.tick, true) {
                    Either {
                        When(second < 59)
                        Assign(second, to: second + 1)
                    } or: {
                        When(second == 59)
                        When(minute < 59)
                        Assign(second, to: 0)
                        Assign(minute, to: minute + 1)
                    } or: {
                        When(second == 59)
                        When(minute == 59)
                        When(hour < 23)
                        Assign(second, to: 0)
                        Assign(minute, to: 0)
                        Assign(hour, to: hour + 1)
                    } or: {
                        When(second == 59)
                        When(minute == 59)
                        When(hour == 23)
                        Assign(second, to: 0)
                        Assign(minute, to: 0)
                        Assign(hour, to: 0)
                    }
                }

                Invariant("ValidTime") {
                    hour >= 0 && hour <= 23 &&
                    minute >= 0 && minute <= 59 &&
                    second >= 0 && second <= 59
                }
            }
        }
    }
}
```

## Run the generated machine

The generated API gives your application typed state and action cases.

```swift
var clock = try ClockModel.makeMachine(
    .init(hour: 16, minute: 19, second: 59)
)
let result = try clock.send(.tick)
print(result.after)
// State(hour: 16, minute: 20, second: 0)
```

## Validate the same specification

The same compiled specification renders the TLA+ and PlusCal bundles. Core
conformance explores the compiled machine and compares its canonical graph
with the TLC graph. Each declared hosted run retains the exact graphs,
`core-decision.json`, the TLC process record, and their provenance. A graph
receipt summarizes the completed exploration. Exact graph comparison decides
the finite case.

## Use it where state order matters

SwiftTLA is for systems where correct operations can still fail in the wrong
order: concurrent tasks, retries, cancellation, sync, background work,
permissions, protocols, and distributed systems.

Use generated `State` and action cases for value-based state. For shared
running state, use the generated live, actor, or observable surface. See
[Generated Machines](Documentation/GeneratedMachines.md) and
[Live Machines](Documentation/LiveMachines.md).

## Learn more

- [Supported language fragment](Documentation/Design.md)
- [Core graph conformance](Documentation/CoreGraphConformance.md)
- [Temporal and symmetry conformance](Documentation/TemporalSymmetryConformance.md)
- [SwiftTLA DocC](Sources/SwiftTLA/SwiftTLA.docc/SwiftTLA.md)
- [Demonstrations app](Examples/SwiftTLADemoApp)

## Requirements

- macOS 14+
- Swift 5.9+
- Xcode 16+
