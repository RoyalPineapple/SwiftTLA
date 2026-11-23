# SwiftTLA

Write a state machine once in Swift. Your app sends it typed actions, and the
native checker explores the same generated transitions. SwiftTLA also exports
the model to TLA+ for independent checking.

## Write and run your first action

This counter starts at zero. The `.advance` action adds one and then stops.

<!-- **Example ID:** `readme-sequential-counter` -->

```swift
import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SequentialCounter {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec {
            let counter = Algorithm { scope in
                let value = scope.sharedVar(initial: 0)
                Do(Step.advance, when: value < 5) {
                    value += 1
                    Stop()
                }
            }
            counter
        }
    }
}
```

In a throwing function, create the machine and send the action.

```swift
var counter = try SequentialCounter.makeMachine()
let change = try counter.send(.advance)
print(change.after.value)  // 1
```

At one, the guard `value < 5` is still true. A second `send(.advance)` throws
because `Stop()` ended the algorithm. The counter stays at one.

## Write the system rules

For a rule that repeats, consider a clock. Each tick adds a second. At
23:59:59 it rolls over to midnight. Select `ValidTime` to check the hour,
minute, and second in the starting state and in each state the checker reaches.

**Example ID:** `readme-clock-model`

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
            let ValidTime = Invariant()
            let clock = Algorithm(label: "Clock") { scope in
                let hour = scope.sharedVar(initiallyIn: 0...23)
                let minute = scope.sharedVar(initiallyIn: 0...59)
                let second = scope.sharedVar(initiallyIn: 0...59)

                Loop(Step.tick) {
                    Either {
                        When(second < 59) {
                            second += 1
                        }
                        When(second == 59, minute < 59) {
                            second.set(0)
                            minute += 1
                        }
                        When(second == 59, minute == 59, hour < 23) {
                            second.set(0)
                            minute.set(0)
                            hour += 1
                        }
                        When(second == 59, minute == 59, hour == 23) {
                            second.set(0)
                            minute.set(0)
                            hour.set(0)
                        }
                    }
                }

                ValidTime {
                    hour >= 0 && hour <= 23 &&
                    minute >= 0 && minute <= 59 &&
                    second >= 0 && second <= 59
                }
            }
            clock
        }
    }
}
```

Each successful `send(.tick)` runs the loop body once. The next tick needs another send.

The ranges in `sharedVar(initiallyIn:)` describe the allowed **starting values**.
`ValidTime` asks a separate question about **reached values**. For example,
an incorrect midnight update can write hour 24 even though the author allowed
only hours 0 through 23 at startup.

## Run the generated machine

The generated API gives your application typed state and action cases.

```swift
var clock = try ClockModel.makeMachine(
    .init(hour: 16, minute: 19, second: 59)
)
let transition = try clock.send(.tick)
print(transition.after)
// State(hour: 16, minute: 20, second: 0)
```

## Check and replay a midnight tick

Start the clock at 23:59:59 and select its `ValidTime` invariant. This check
explores up to ten states from that one start. A counterexample contains the
initial snapshot and the action and snapshot for each step that follows.
Replay follows those steps and returns a clock at the failure. The starting clock stays at 23:59:59.

```swift
let start = try ClockModel.makeMachine(.init(hour: 23, minute: 59, second: 59))
do {
    let result = try start.check(properties: [.ValidTime], checkDeadlock: false, maximumStates: 10)
    switch result {
    case .counterexample(let witness):
        let failedClock = try start.replay(witness)
        print(failedClock.state)
    case .exhausted:
        print("ValidTime held in every reachable state from this start.")
    }
} catch ExplorationError.stateLimitExceeded(let limit) {
    print("Reached the limit of \(limit) states. The check is incomplete.")
}
```

To see a failure, change the midnight branch's `hour.set(0)` to
`hour += 1`. One `.tick` now takes the clock to hour 24,
minute 0, second 0. Restore the reset and the same tick reaches 00:00:00.
The fixed clock continues ticking, so the ten-state check reaches its limit.

## Use the machine in SwiftUI

The generated state is ordinary Swift value state. A view renders it and sends
typed actions. The machine keeps each transition atomic.

**Example ID:** `readme-clock-swiftui`

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
            guard machine == nil else { return }
            do {
                machine = try ClockModel.makeMachine(
                    .init(hour: 16, minute: 19, second: 59)
                )
            } catch {
                diagnostic = String(describing: error)
            }
        }
    }
}
```

`machine` is the generated machine stored by the view. A failed action throws and
leaves the machine state unchanged. This view stores the diagnostic for display.
Use the generated actor for shared asynchronous state. It stores the same
generated machine behind actor isolation.

## Add bounded assurance

This clock's generated machine supports native exploration. Its compiled model
also renders direct TLA+ and the authored PlusCal algorithm. The independent
validation pipeline compares the generated machine with a pinned TLC run of
the exported TLA+. See
[Finite graph comparison](Documentation/FiniteGraphComparison.md).

## Use it where state order matters

SwiftTLA applies to concurrent tasks, retries, cancellation, sync, background
work, permissions, protocols, and distributed systems.

Use generated `State` and action cases for value-based state. For shared
running state, use the generated `Actor`. See
[Generated Machines](Documentation/GeneratedMachines.md).

## Learn more

- [Compiler design](Documentation/Design.md)
- [Production readiness](Documentation/ProductionReadiness.md)
- [Finite graph comparison](Documentation/FiniteGraphComparison.md)
- [Temporal and symmetry conformance](Documentation/TemporalSymmetryConformance.md)
- [SwiftTLA DocC](Sources/SwiftTLA/SwiftTLA.docc/SwiftTLA.md)
- [Demonstrations app](Examples/SwiftTLADemoApp)

## Requirements

- macOS 14+
- Xcode 16.4
