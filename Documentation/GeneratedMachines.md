# Generated machines

`@TLAModel` turns a compiled `TLASpec` declaration into a typed Swift state
machine. The generated value is the normal application surface: it holds one
complete `State`, accepts typed `Action` values, and publishes a complete new
state for each successful transition.

```swift
var machine = try Counter.makeMachine()
let transition = try machine.send(.advance)
let state = transition.after
```

The model is useful before any formal-tool vocabulary is needed. Its formal
bundle and bounded exploration remain available through compilation.

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

        static var defaultValue: Self { .only }
        static let finiteValues: [Process] = [.only]

        var tlaValue: TLAValue { .string(rawValue) }
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

`send(_:)` applies one action. `isEnabled(_:)` asks whether that action is
currently permitted. Both operations can throw a generated-machine diagnostic;
a rejected action leaves `state` unchanged.

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

Use `isEnabled(_:)` to drive a control affordance, but always handle a failed
`send(_:)`: state can change between rendering a view and receiving an event.

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
                    try machine.send(.advance)
                    self.machine = machine
                    diagnostic = ""
                } catch {
                    diagnostic = String(describing: error)
                }
            }
            if !diagnostic.isEmpty {
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

The fixture uses an explicit throwing factory at its boundary. The view works
only with generated state and actions, and it presents a rejected action as
application state.

## Advanced execution

`Actor` owns a generated machine value when an application needs asynchronous
coordination. It serializes `send(_:)` and exposes the same generated `State`
and `Action` values used by value and SwiftUI code. Its initializer accepts the
same typed initial state as `makeMachine(_:)`.

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

        static var defaultValue: Self { .only }
        static let finiteValues: [Process] = [.only]

        var tlaValue: TLAValue { .string(rawValue) }
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

## Test a model integration

Test the state before and after a transition, the enabled condition, and a
rejected action. These tests verify integration with the generated Swift API;
they do not extend the model's declared finite verification bounds.

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

## Formal verification

Compile the same model when an application needs to inspect, render, or explore it:

```swift
let compilation = try BoundedCounter.spec.compile()
let bundle = try compilation.renderedTLAModuleBundle()
```

The generated Swift machine, local exploration, and rendered formal bundle
come from that one compilation.

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

## Stable contract

| Claim area | Evidence |
| --- | --- |
| Generated machine members | `Sources/SwiftTLAPlugin/MacroExpander.swift` and `Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift` |
| Generated machine errors | `Sources/SwiftTLA/GeneratedMachineError.swift` |
| Compilable examples | The fixtures named beside each example ID |
