# SwiftTLA

**SwiftTLA declares how an application is allowed to change state.**

Define explicit state, permitted actions, and rules that must hold. SwiftTLA
generates a typed Swift machine your application can run. The same model can
also explore bounded behavior and render TLA+/PlusCal for independent TLC
comparison.

**One model. Typed application state. Bounded formal evidence.**

```text
Swift source model
        │
        ▼
Generated Swift machine
 ├── State and Action
 ├── value machine in SwiftUI `@State`
 ├── generated `Actor` around that value
 └── bounded exploration and formal bundles
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
    private enum Step: String, CaseIterable {
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

## Use the machine in SwiftUI

The generated state is ordinary Swift value state. A view renders it and sends
typed actions; the machine keeps each transition atomic.

```swift
import SwiftUI

struct ClockView: View {
    @State private var machine: ClockModel?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            if let machine {
                Text("Time: \(machine.state.hour):\(machine.state.minute):\(machine.state.second)")
                Button("Tick") {
                    do {
                        var machine = machine
                        _ = try machine.send(.tick)
                        self.machine = machine
                        diagnostic = ""
                    } catch {
                        diagnostic = String(describing: error)
                    }
                }
            } else {
                ProgressView()
            }

            if diagnostic.isEmpty == false {
                Text(diagnostic)
            }
        }
        .task {
            do {
                machine = try ClockModel.makeMachine()
            } catch {
                diagnostic = String(describing: error)
            }
        }
    }
}
```

`machine` is the generated value stored by the view. A failed action is explicit
application state, not a discarded error. Use the generated actor when the
application needs shared asynchronous state; it stores the same generated
machine value behind actor isolation.

## Add bounded assurance

The same compiled specification renders the TLA+ and PlusCal bundles. Core
conformance explores the compiled machine and compares its complete bounded
graph with TLC. See [Core graph conformance](Documentation/CoreGraphConformance.md)
for the retained audit evidence and precise claim.

## Use it where state order matters

SwiftTLA is for systems where correct operations can still fail in the wrong
order: concurrent tasks, retries, cancellation, sync, background work,
permissions, protocols, and distributed systems.

Use generated `State` and action cases for value-based state. For shared
running state, use the generated `Actor`. See
[Generated Machines](Documentation/GeneratedMachines.md) and
[Actor Machines](Documentation/ActorMachines.md).

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
