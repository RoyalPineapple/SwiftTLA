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
import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundedCounter {
    enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("BoundedCounter") {
            Algorithm("BoundedCounter") {
                let value = SharedVar("value", initial: 0)
                Do(Step.advance) {
                    When(value < 1)
                    Assign(value, to: value + 1)
                    Stop()
                }
            }
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
import SwiftTLA

func runDirectAction() throws {
    var machine = try BoundedCounter.makeMachine()
    assert(try machine.isEnabled(.advance))
    let result = try machine.send(.advance)

    assert(result.action == .advance)
    assert(result.before.value == 0)
    assert(result.after.value == 1)
    assert(machine.state.value == 1)
}
```

Use `isEnabled(_:)` to drive a control affordance, but always handle a failed
`send(_:)`: state can change between rendering a view and receiving an event.

## SwiftUI

The generated value is a SwiftUI view model. Keep it in `@State`, read its
typed state, and send typed actions. A successful action replaces the complete
state in one transition.

**Example ID:** `generated-machine-swiftui`
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/CounterView.swift`

```swift
import SwiftUI

struct CounterView: View {
    @State private var machine: CounterScreenModel?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(machine?.state.value ?? 0)")
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

            if diagnostic.isEmpty == false {
                Text(diagnostic)
            }
        }
        .task {
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
let actor = try CounterHost.Actor()
let transition = try await actor.send(.advance)
assert(await actor.state == transition.after)

let seeded = try CounterHost.Actor(.init(value: 0))
assert(await seeded.state.value == 0)
```

## Test a model integration

Test the state before and after a transition, the enabled condition, and a
rejected action. These tests verify integration with the generated Swift API;
they do not extend the model's declared finite verification bounds.

**Example ID:** `generated-machine-testing`
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/GeneratedMachineTests.swift`

```swift
var machine = try BoundedCounter.makeMachine()
let result = try machine.send(.advance)
let beforeFailure = machine.state

assert(result.after.value == 1)
assert(try machine.isEnabled(.advance) == false)

do {
    try machine.send(.advance)
    assertionFailure("Expected a disabled action")
} catch is GeneratedMachineError {
    assert(machine.state == beforeFailure)
}
```

## Formal verification

Compile the same model when an application needs to inspect, render, or
explore it:

```swift
let compilation = try BoundedCounter.spec.compile()
let bundle = try compilation.renderedTLAModuleBundle()
```

The generated Swift machine, local exploration, and rendered formal bundle
come from that one compilation.

## Public API

| Name | Role |
| --- | --- |
| `@TLAModel` | Generates the typed machine surface for a `TLASpec`. |
| Generated `State` | Holds declared model variables as Swift values. |
| Generated `Action` | Represents declared actions and their typed parameters. |
| Generated `Transition` | Records a successful action and its before/after state. |
| Generated `state` | Reads the complete current generated state. |
| Generated `send(_:)` | Applies one typed action or throws. |
| Generated `isEnabled(_:)` | Tests whether one typed action is currently permitted. |
| Generated `Actor` | Serializes access to one generated machine value. |

## Claim sources

| Claim area | Evidence |
| --- | --- |
| Generated machine members | `Sources/SwiftTLAPlugin/MacroExpander.swift` and `Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift` |
| Generated machine errors | `Sources/SwiftTLA/GeneratedMachineError.swift` |
| Compilable examples | The fixtures named beside each example ID |
