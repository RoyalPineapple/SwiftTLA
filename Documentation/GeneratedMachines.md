# Generated machines

`@TLAModel` generates a typed Swift state machine from a compiled `TLASpec`.
The machine holds one complete `State` and accepts typed `Action` values. Each
successful action returns a `Transition` with the state before and after it.

```swift
var machine = try Counter.makeMachine()
let transition = try machine.send(.advance)
let state = transition.after
```

Application code uses the generated machine. Formal tools use the compiled
specification and rendered bundles.

## Generate a machine

Import `SwiftTLA` and `SwiftTLAMacros`. Apply `@TLAModel` to a type with a
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

Each generated model exposes these value types:

- `State` is an immutable value with the declared variables and their Swift types.
- `Action` contains declared actions and their typed parameters.
- `Transition` contains the action and the state before and after it.

`send(_:)` applies one action. `isEnabled(_:)` reports whether that action is
currently permitted. Both operations can throw a generated-machine diagnostic.
A rejected action leaves `state` unchanged.

**Example ID:** `generated-machine-direct-action`
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/DirectAction.swift`

```swift
// Example ID: generated-machine-direct-action

import SwiftTLA

func runDirectAction() throws {
    var machine = try BoundedCounter.makeMachine()
    let actions = try machine.enabledActions()
    let result = try machine.send(.advance)

    assert(actions == [.advance])
    assert(result.action == .advance)
    assert(result.before.value == 0)
    assert(result.after.value == 1)
    assert(machine.state.value == 1)
}
```

Use `isEnabled(_:)` to control user actions. Handle each error from
`send(_:)` because application events can arrive after the view changes.

## SwiftUI

The generated machine value is SwiftUI state. Keep it directly in `@State`,
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

`Actor` is a thin asynchronous adapter over one generated value machine. It
serializes `send(_:)` and exposes the same generated `State` and `Action`
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
    let result = try machine.send(.advance)
    let beforeFailure = machine.state

    assert(result.before.value == 0)
    let isEnabled = try machine.isEnabled(.advance)
    assert(isEnabled == false)
    assert(result.after.value == 1)

    do {
        _ = try machine.send(.advance)
        assertionFailure("Expected an unavailable action")
    } catch is GeneratedMachineError {
        assert(machine.state == beforeFailure)
    }
}
```

## Compile and render

Compile the source model before inspection, rendering, or exploration:

```swift
let compilation = try BoundedCounter.spec.compile()
let bundle = compilation.renderedTLAModuleBundle()
```

The generated machine compiles the same source and compares its compilation
identity with the identity from macro expansion. Explicit compilations drive
bounded exploration and formal rendering.

## API reference

| Name | Role |
| --- | --- |
| `@TLAModel` | Generates the typed machine surface for a `TLASpec`. |
| `GeneratedMachineError` | Reports a rejected or invalid generated-machine operation. |
| Generated `State` | Holds declared model variables as Swift values. |
| Generated `Action` | Represents declared actions and their typed parameters. |
| Generated `Transition` | Records a successful action and its before/after state. |
| Generated `state` | Reads the complete current generated state. |
| Generated `send(_:)` | Applies one typed action or throws. |
| Generated `isEnabled(_:)` | Tests whether one typed action is currently permitted. |
| Generated `Actor` | Serializes access to one generated machine value. |
| Generated `enabledActions()` | Lists the typed actions enabled by the current state. |
