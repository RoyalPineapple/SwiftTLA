# SwiftTLA

**SwiftTLA brings formal programming into Swift.**

**SwiftTLA generates typed Swift state machines and exhaustively validates all reachable behavior against your specification.**

Write the rules of a system once: its data, actions, algorithms, invariants,
and temporal properties. SwiftTLA turns those rules into production Swift code
that your app can run. The same specification can explore every reachable
outcome in tests and produce TLA+ and PlusCal for independent TLC validation.

**One specification. Production behavior. Formal evidence.**

## What you get

SwiftTLA gives one specification three jobs:

- A typed Swift state machine for your application.
- Exhaustive exploration of reachable behavior in tests.
- TLA+ and PlusCal artifacts for TLC validation.

The generated machine gives your application typed state and action cases.
The model checker explores the same compiled specification. For declared finite
cases, SwiftTLA compares its graph with TLC's graph exactly.

## Define a model. Use it in your app.

Define the model with `#spec` and `Algorithm`. Then use its generated machine
as ordinary Swift code.

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

var clock = try HourClock.makeMachine()
let result = try clock.apply(.tick)
print(result.after.hour)
```

## Validate the same model

In tests, SwiftTLA explores the reachable graph from the model's initial state.
It validates the invariants and properties in that specification.

Core Conformance runs the declared finite cases through SwiftTLA and TLC. It
compares the complete canonical state graph and labeled transition graph.
The [Core Graph Conformance guide](Documentation/CoreGraphConformance.md)
describes the retained evidence and comparison results.

The separate ValidationEvidence workflow translates the canonical PlusCal
corpus with the official PlusCal translator and runs TLC. It supplies
independent evidence for selected upstream models.

## Use live state when you need it

Use generated `State` and action cases for value-based application state. For
shared running state, create one `TLALiveMachineOwner` and use its generated
live, actor, or observable surface. See [Live Machines](Documentation/LiveMachines.md)
and [Generated Machines](Documentation/GeneratedMachines.md).

## See it running

The macOS demonstration app is in
[`Examples/SwiftTLADemoApp`](Examples/SwiftTLADemoApp). It uses the generated
machines from [`Examples/SwiftTLADemos`](Examples/SwiftTLADemos).

```bash
cd Examples/SwiftTLADemoApp
swift run SwiftTLADemoApp
```

## Learn more

- [Supported language fragment](Documentation/Design.md)
- [Generated machines](Documentation/GeneratedMachines.md)
- [Core graph conformance](Documentation/CoreGraphConformance.md)
- [Temporal and symmetry conformance](Documentation/TemporalSymmetryConformance.md)
- [SwiftTLA DocC](Sources/SwiftTLA/SwiftTLA.docc/SwiftTLA.md)

## Requirements

- macOS 14+
- Swift 5.9+
- Xcode 16+
