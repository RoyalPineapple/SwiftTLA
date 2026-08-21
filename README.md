# SwiftTLA

**SwiftTLA brings formal programming into Swift.**

**SwiftTLA generates typed Swift state machines and exhaustively validates all reachable behavior against your specification.**

Define a system's state, actions, algorithms, invariants, and temporal
properties in Swift. SwiftTLA compiles that one source model into a machine
your app can run, a model checker for your tests, and TLA+/PlusCal artifacts
for TLC.

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
public struct HourClock {
    enum Process: String, FiniteDomainKey {
        case clock

        static let formalDomain: [Process] = [.clock]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "readme.hour-clock.process")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, PlusCalLabel {
        case tick
    }

    public static var spec: TLASpec {
        #spec("HourClock") {
            Algorithm("HourClock") {
                let hour = SharedVar(initial: 1)
                Each(Process.all) { _ in
                    Do(Step.tick) {
                        Either {
                            When(hour < 12)
                            Assign(hour, to: hour + 1)
                        } or: {
                            When(hour == 12)
                            Assign(hour, to: 1)
                        }
                    }
                }
            }
        }
    }
}
```

## Run the generated machine

The generated API gives your application typed state and action cases.

```swift
var clock = try HourClock.makeMachine()
let result = try clock.apply(.tick)
print(result.after.hour)
```

## Validate the same specification

The model checker explores the complete reachable graph from the model's
initial state. It validates the invariants and properties that you define.

```swift
let compilation = try HourClock.spec.compile()
let result = try ModelChecker(compilation: compilation).check()
```

The same compilation renders the TLA+ and PlusCal bundle. Core Conformance
compares SwiftTLA's canonical graph with TLC's graph exactly. The separate
ValidationEvidence workflow translates the canonical PlusCal corpus with the
official translator and retains the independent TLC evidence.

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
