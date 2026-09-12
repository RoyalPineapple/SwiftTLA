# Generated machines

`@TLAModel` generates a typed Swift state machine from one compiled
specification.
The machine holds its execution state and exposes declared variables through
an immutable `State`. It accepts typed `Action` values; each successful action
returns a `Transition` with the visible state before and after it.

```swift
var machine = try Counter.makeMachine()
let transition = try machine.send(.advance)
let state = transition.after
```

Application code uses the generated machine. TLC and PlusCal tools use the
rendered bundles published by the compiled specification.

## Generate a machine

Import `SwiftTLA` and `SwiftTLAMacros`. Apply `@TLAModel` to a struct with a
`static var spec: TLASpec` declaration.

**Example ID:** `generated-machine-bounded-model`
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/BoundedCounter.swift`

```swift
// Example ID: generated-machine-bounded-model

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundedCounter {
    enum Process: String, FiniteTLAValueDomain {
        case only
    }

    enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("BoundedCounter") {
            Algorithm("BoundedCounter", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            })
        }
    }
}
```

## State, actions, and transitions

Each generated machine exposes these value types:

- `State` is an immutable value with the declared variables and their native Swift types.
- `Snapshot` retains the complete execution state, including compiler-owned control state.
- `Action` contains declared actions and their typed parameters.
- `Transition` contains the action and the state before and after it.

Sets, sequences, and functions use standard Swift `Set`, `Array`, and
`Dictionary` values. Pairs and records become generated immutable structs;
read their fields directly. Finite unions become generated enums containing
exactly their declared values. These mappings apply recursively to nested
values.

`send(_:)` applies one action. `isEnabled(_:)` reports whether that action is
currently permitted. Both operations can throw a generated-machine diagnostic.
A rejected action leaves `state` unchanged.

`initialMachines()` returns every permitted initial machine. `successors(for:)`
returns every distinct successor machine for an action without changing the
receiver. These values retain process control state and application collection
bindings, so each branch can continue independently. A disabled action returns
an empty array. `send(_:)` requires exactly one successor and rejects ambiguous
actions; `makeMachine()` likewise requires exactly one initial state.

**Example ID:** `generated-machine-direct-action`
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/DirectAction.swift`

```swift
// Example ID: generated-machine-direct-action

import SwiftTLA

func runDirectAction() throws {
    var machine = try BoundedCounter.makeMachine()
    let actions = try machine.enabledActions()
    let transition = try machine.send(.advance)

    assert(actions == [.advance])
    assert(transition.action == .advance)
    assert(transition.before.value == 0)
    assert(transition.after.value == 1)
    assert(machine.state.value == 1)
}
```

Use `isEnabled(_:)` to control user actions. Handle each error from
`send(_:)` because application events can arrive after the view changes.

## SwiftUI

The generated machine is SwiftUI state. Keep it directly in `@State`,
read its typed state, and send typed actions. A successful action replaces the
complete state in one transition.

**Example ID:** `generated-machine-swiftui`
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/CounterView.swift`

```swift
// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var machine: CounterScreenModel?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(machine.map { String($0.state.value) } ?? "-")")
            Button("Advance") {
                do {
                    guard var machine else { return }
                    _ = try machine.send(.advance)
                    self.machine = machine
                    diagnostic = ""
                } catch {
                    diagnostic = String(describing: error)
                }
            }
            if diagnostic.isEmpty == false {
                Text(diagnostic)
            }
        }
        .task {
            guard machine == nil else { return }
            do {
                machine = try CounterScreenModel.makeMachine()
            } catch {
                diagnostic = String(describing: error)
            }
        }
    }

}
```

The view creates the machine with its throwing factory. It reads generated
state and sends generated actions. It stores each action error for display.

## Effects and presentation data

The generated machine owns state that controls which transition can occur.
Platform handles, received data, diagnostics, and animation are presentation
data.

The platform examples use this division directly:

- `CameraWorkflow` owns camera phase transitions, including recording and
  stopping. `CameraEffects` owns AVFoundation objects, captured media, and
  selected thumbnails.
- `BluetoothModel` owns scanning transitions. `BluetoothEffects` owns the
  devices reported by Core Bluetooth.

An effect first applies the action that authorizes it. When the platform
reports an outcome, the application sends the corresponding typed action back
to the same machine.

## Actor

`Actor` owns one generated machine. Actor isolation serializes `send(_:)`,
and it exposes the same generated `State` and `Action`
values. Its initializer accepts the same typed initial state as
`makeMachine(_:)`.

**Example ID:** `generated-machine-actor`
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/ActorAccess.swift`

```swift
// Example ID: generated-machine-actor

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterHost {
    enum Process: String, FiniteTLAValueDomain {
        case only
    }

    enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterHost") {
            Algorithm("CounterHost", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            })
        }
    }

}

func runActorAccess() async throws {
    let actor = try CounterHost.Actor()
    let transition = try await actor.send(.advance)
    let seeded = try CounterHost.Actor(.init(value: 0))

    let actorState = await actor.state
    let seededState = await seeded.state
    assert(actorState == transition.after)
    assert(seededState.value == 0)
}
```

## Validate the generated API

Validate the state before and after a transition. Also validate the enabled
condition and a rejected action. These tests exercise the generated Swift API.

**Example ID:** `generated-machine-testing`
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/GeneratedMachineTests.swift`

```swift
// Example ID: generated-machine-testing

import SwiftTLA

func runGeneratedMachineTesting() throws {
    var machine = try BoundedCounter.makeMachine()
    let transition = try machine.send(.advance)
    let beforeFailure = machine.state

    assert(transition.before.value == 0)
    let isEnabled = try machine.isEnabled(.advance)
    assert(isEnabled == false)
    assert(transition.after.value == 1)

    var rejected = false
    do {
        _ = try machine.send(.advance)
    } catch is GeneratedMachineError {
        rejected = true
    }
    assert(rejected)
    assert(machine.state == beforeFailure)
}
```

## Native exploration

Generated models conform to `StateMachine`. `successors()` enumerates every
action and successor using the same functions that `send(_:)` calls.
`ReachabilityGraph(initialMachines: Model.initialMachines(), maximumStates: limit)`
explores those native successors without compiling or interpreting expressions
and without invoking TLC. Supply initial machines from one finite configuration.

The graph retains all initial snapshots and labeled transitions. Snapshot identity
includes control state: two equal public `State` values can still have different
successors. Exploration throws on exhaustion of the state limit or cancellation;
it never returns a truncated graph as complete. Exploration evaluates generated
assumptions and invariant predicates. It retains invariant and deadlock failures in `safetyViolations` while completing the graph;
`DeadlockCheck()` enables deadlock reporting; normal algorithm termination is
not a deadlock. `trace(to:)` reconstructs a
shortest native execution from the discovery predecessors. False assumptions and
evaluation errors throw. Temporal checking and independent equivalence validation
remain separate; empty safety results do not establish liveness or equivalence.

For independent validation, `machine.formalProjection(of: snapshot)` converts the
complete native snapshot to a validated `TLAStateProjection`. The macro emits
this conversion from resolved types, including compiler-owned control state.
Collection members use the machine's configured correspondence to formal IDs;
unknown members and malformed formal values throw. Use one finite configuration
for the entire graph. This explicit serialization boundary does not execute the
formal interpreter or invoke TLC.

## Compile and render

Compile the source model when exporting formal artifacts:

```swift
let compilation = try BoundedCounter.spec.compile()
let bundle = try compilation.render().tlaBundle
```

Compilation validates declarations, binds names, links modules, lowers
behavior, and allocates private identities. `render()` consumes the resulting
program to produce TLA+/PlusCal text and formal bundles. Reuse that rendered
result when exporting multiple artifacts. At build time, the macro
uses the resolved compiler program to emit typed Swift initialization, guards,
updates, and property checks. Generated machines execute that Swift directly;
construction and transitions do not compile the specification or interpret
formal values. Formal artifacts are exported separately for independent validation.

The inline specification is authoritative. Its getter must contain one direct
`#spec` declaration (or return that declaration), with statically admitted model
structure. Unsupported native operations produce build-time diagnostics.

`violatedInvariants()` returns the names of false invariants in the current
state. `assumptionsHold()` evaluates the declared assumptions. These checks do
not remove invariant violations from the transition relation. State constraints
filter successor candidates before the machine selects a unique transition.

## API reference

| Name | Role |
| --- | --- |
| `@TLAModel` | Generates the typed machine surface for a source model. |
| `GeneratedMachineError` | Reports a rejected or invalid generated-machine operation. |
| Generated `State` | Holds declared model variables as Swift values. |
| Generated `Action` | Represents declared actions and their typed parameters. |
| Generated `Transition` | Records a successful action and its before/after state. |
| Generated `state` | Reads the complete current generated state. |
| Generated `send(_:)` | Applies one typed action or throws. |
| Generated `isEnabled(_:)` | Tests whether one typed action is currently permitted. |
| Generated `Actor` | Serializes access to one generated machine. |
| Generated `enabledActions()` | Lists the typed actions enabled by the current state. |
