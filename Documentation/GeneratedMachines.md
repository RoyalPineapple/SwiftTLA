# Generated Machines

`@TLAModel` turns a compiled `TLASpec` declaration into a typed Swift machine.
This guide documents the generated-machine public contract. A generated model
defines its machine surface and formal behavior. Its `Live` value owns mutable state.
See [Live Machines](LiveMachines.md) for shared inspection, observation, and
control.
Read [the SwiftTLA DocC catalog](../Sources/SwiftTLA/SwiftTLA.docc/SwiftTLA.md)
for the symbol-oriented reference.

## Contents

- [Generate a machine](#generate-a-machine)
- [Run actions](#run-actions)
- [Run a live machine](#run-a-live-machine)
- [Nest a machine](#nest-a-machine)
- [Isolation and callbacks](#isolation-and-callbacks)
- [Test an integration](#test-an-integration)
- [Debug a machine](#debug-a-machine)
- [Limits and evidence](#limits-and-evidence)
- [SwiftUI](#swiftui)
- [API reference](#api-reference)
- [Stable contract](#stable-contract)

## Generate a machine

Import `SwiftTLA` and `SwiftTLAMacros`. Apply `@TLAModel` to a struct, class, or actor that declares `static var spec: TLASpec`.

The macro generates a typed Swift surface from the model source. Each generated
factory compiles the model before it creates a machine.

**Example ID:** `generated-machine-bounded-model`  
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/BoundedCounter.swift`

```swift
// Example ID: generated-machine-bounded-model

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BoundedCounter {
    enum Process: String, FiniteDomainKey {
        case only

        static let formalDomain: [Process] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "documentation.counter.process")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, PlusCalLabel, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("BoundedCounter") {
            Algorithm("BoundedCounter") {
                let value = SharedVar("value", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            }
        }
    }
}
```

This example has one integer variable and two reachable values.

The fixture is the compilation authority for this example. It uses Swift tools 5.9 and the macOS 14 package context declared in `Package.swift`.

## Run actions

A generated model has typed `State`, `ActionLabel`, and `TransitionResult`
members. Use `availableActions()` to get typed labels. Use
`apply(_:)` to execute one label synchronously on a non-actor value model.
That value has no live-runtime identity or observer connection.

**Example ID:** `generated-machine-direct-action`  
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/DirectAction.swift`

```swift
// Example ID: generated-machine-direct-action

import SwiftTLA

func runDirectAction() throws {
    var machine = try BoundedCounter.makeMachine()
    let actions = try machine.availableActions()
    let result = try machine.apply(.advance)

    assert(actions == [.advance])
    assert(result.action == .advance)
    assert(result.before.value == 0)
    assert(result.after.value == 1)
    assert(machine.state.value == 1)
}
```

`TransitionResult` records the typed action and typed state before and after
the transition.

`apply(_:)` throws `GeneratedMachineError` for a rejected action label. The current snapshot remains available after that error.

Use `machineObservation()` when code needs state and availability together. It
returns the generated `MachineObservation`, with typed `State` and typed
available action labels.

Use this value API for independent value-based work. Use `Live` when multiple
adapters share one mutable machine.

## Run a live machine

Create the typed live runtime with the generated model factory.

```swift
let live = try BoundedCounter.makeLive()

switch await live.execute(.advance) {
case .committed(let transition):
    assert(transition.after.value == 1)
case .rejected(let rejection):
    print(rejection.reason)
case .failed(let failure):
    print(failure.code)
}
```

Use `Live.execute(_:)` with the generated `ActionLabel`. Only `committed`
changes state. An accepted action is non-cancellable: it completes as
`committed` or normal `failed`.

## Nest a machine

Put `@TLAActor` or `@TLAObservable` on a nested type inside a `@TLAModel`
struct. Create the generated adapter with the enclosing model's `Live` value.

**Example ID:** `generated-machine-actor`  
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/ActorAccess.swift`

```swift
// Example ID: generated-machine-actor

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterHost {
    enum Process: String, FiniteDomainKey {
        case only

        static let formalDomain: [Process] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "documentation.actor.process")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, PlusCalLabel, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterHost") {
            Algorithm("CounterHost") {
                let value = SharedVar("value", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            }
        }
    }

    @TLAActor
    actor Actor {}
}

func runActorAccess() async throws {
    let live = try CounterHost.makeLive()
    let actor = CounterHost.Actor(live: live)
    let result = try await actor.apply(.advance)

    guard case .committed(let commit) = result else { return }
    assert(commit.after.position.value == 1)
}
```

The nested actor is asynchronous. Call `current()` or `apply(_:)` across its
actor boundary. It shares identity and state with adapters created from the
same `Live` value.

Nested adapters expose the enclosing model's `State`, `ActionLabel`, and
`TransitionResult` through type aliases.

## Isolation and callbacks

A nested `@TLAObservable` adapter is main-actor isolated. It is nested in one
`@TLAModel` struct. `@TLAActor` has the same nesting requirement. Adapters
share the enclosing model's typed `Live` runtime.

A nested observable uses `await Observable(live:)`. It attaches to that
runtime and derives its typed cache from observation events. Its main-actor
properties provide SwiftUI observation.

A nested observable exposes `onTransition`. The callback receives the typed
`ActionLabel`, plus typed state values from before and after each successful
execution.

**Example ID:** `generated-machine-nested-observable`  
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/NestedObservable.swift`

```swift
// Example ID: generated-machine-nested-observable

import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CounterScreenModel {
    enum Process: String, FiniteDomainKey {
        case only

        static let formalDomain: [Process] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "documentation.observable.process")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Step: String, PlusCalLabel, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterScreenModel") {
            Algorithm("CounterScreenModel") {
                let value = SharedVar("value", initial: 0)
                Each(Process.all) { _ in
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Stop()
                    }
                }
            }
        }
    }

    @TLAObservable
    final class Observable {}
}

@MainActor
func runObservable() async throws {
    let live = try CounterScreenModel.makeLive()
    let observable = try await CounterScreenModel.Observable(live: live)
    observable.onTransition = { action, before, after in
        guard case .advance = action else { return }
        assert(before.value == 0)
        assert(after.value == 1)
    }
    let result = try await observable.apply(.advance)
    guard case .committed = result else { return }
}
```

For a nested observable, `apply(_:)` submits the request to the runtime. The
callback occurs only when its subscription
reduces a contiguous committed update. A rejected or failed action does not
call the callback. On loss, the observable clears its cache and resynchronizes.

Callbacks are main-actor isolated. The generated typed `ActionLabel`, `State`,
`Live`, and transition result form the public integration surface.

## Test an integration

Test the initial observation, enabled action, transition result, and failed-action
outcome. These tests confirm application integration. They do not extend the
model-checking claim beyond the model's declared finite bounds.

**Example ID:** `generated-machine-testing`  
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/GeneratedMachineTests.swift`

```swift
// Example ID: generated-machine-testing

import SwiftTLA

func runGeneratedMachineTesting() async throws {
    var machine = try BoundedCounter.makeMachine()
    let initial = try await machine.machineObservation()
    let result = try machine.apply(.advance)
    let beforeFailure = machine.state

    assert(initial.state.value == 0)
    assert(initial.availableActions == [.advance])
    assert(result.after.value == 1)

    do {
        _ = try machine.apply(.advance)
        throw GeneratedMachineDocumentationError.expectedUnavailableAction
    } catch is GeneratedMachineError {
        assert(machine.state == beforeFailure)
    }
}

private enum GeneratedMachineDocumentationError: Error {
    case expectedUnavailableAction
}
```

For a callback test, retain the callback's before and after `State` values. For
an actor test, read state with `await`. Execute actions with `try await`.

## Debug a machine

For an action problem, collect these public values:

- `MachineObservation.state`
- `MachineObservation.availableActions`
- the attempted generated `ActionLabel`
- the returned `TransitionResult`, when execution succeeds
- the `GeneratedMachineError`, when execution fails

For a macro expansion problem, collect the macro diagnostic and model source.

## SwiftUI

Keep the typed `Live` value and observable adapter in view state. The adapter
receives its state from runtime observation.

**Example ID:** `generated-machine-swiftui`  
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/CounterView.swift`

```swift
// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var live: CounterScreenModel.Live?
    @State private var machine: CounterScreenModel.Observable?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(machine?.state.map { String($0.value) } ?? "-")")
            Button("Advance") {
                Task { @MainActor in
                    guard let machine else { return }
                    switch try await machine.apply(.advance) {
                    case .committed:
                        diagnostic = ""
                    case .rejected(let rejection):
                        diagnostic = rejection.reason.description
                    case .failed(let failure):
                        diagnostic = failure.message
                    }
                }
            }
            if !diagnostic.isEmpty {
                Text(diagnostic)
            }
        }
        .task {
            guard live == nil else { return }
            do {
                let live = try CounterScreenModel.makeLive()
                self.live = live
                machine = try await CounterScreenModel.Observable(live: live)
            } catch {
                diagnostic = String(describing: error)
            }
        }
    }
}
```

The fixture compiles this view in the macOS package context. A manual review must inspect the initial render, the render after `advance`, and the state after a loss or termination.

The example omits disabled-button logic. The observable adapter automatically
observes its supplied runtime; it displays explicit rejection or failure text.

## API reference

The following table is the public inventory for this guide. Sources identify the declaration or generator that establishes each claim.

| Name | Role and observable contract | Source |
|---|---|---|
| `@TLAModel` | Attaches generated machine members to a struct, class, or actor with a `TLASpec`. | [Macros.swift](../Sources/SwiftTLAMacros/Macros.swift), [ModelMacro.swift](../Sources/SwiftTLAPlugin/ModelMacro.swift) |
| `@TLAActor` | Requires a nested type. Its generated actor accepts the enclosing model's typed `Live` value. | [Macros.swift](../Sources/SwiftTLAMacros/Macros.swift), [MacroExpander+Adapters.swift](../Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift) |
| `@TLAObservable` | Requires a nested type. Its generated main-actor adapter accepts the enclosing model's typed `Live` value and reduces observation events. | [Macros.swift](../Sources/SwiftTLAMacros/Macros.swift), [MacroExpander+Adapters.swift](../Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift) |
| Generated `Live` | Creates and owns one typed live runtime. | [MacroExpander+LiveMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+LiveMachine.swift) |
| `GeneratedMachineError` | Reports invalid initial state selection, unavailable successors, and live-machine failures. | [GeneratedMachineError.swift](../Sources/SwiftTLA/GeneratedMachineError.swift) |
| Generated `State` | Holds model variables with generated Swift types. Application code reads this type through `state`, before, and after. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `ActionLabel` | Represents declared actions with typed parameters. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `TransitionResult` | Records the typed action and typed state before and after a successful transition. | [MacroExpander+GeneratedMachineStorage.swift](../Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift) |
| Generated `availableActions()` | Returns typed available action labels for a model that declares actions. | [MacroExpander+GeneratedMachineStorage.swift](../Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift) |
| Generated `apply(_:)` | Executes a typed `ActionLabel`. It returns `TransitionResult` or throws. | [MacroExpander+GeneratedMachineStorage.swift](../Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift) |
| Generated `MachineObservation` | Records typed state and currently available typed action labels. | [MacroExpander+GeneratedMachineStorage.swift](../Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift) |
| Generated `machineObservation()` | Returns `MachineObservation` or throws. | [MacroExpander+GeneratedMachineStorage.swift](../Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift) |
| Generated `Live.execute(_:)` | Executes a typed label through the existing live runtime and returns an explicit live outcome. | [MacroExpander+LiveMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+LiveMachine.swift) |
| Generated `synchronousMachineObservation()` | Returns current state and availability without an async boundary on a generated model. | [MacroExpander+GeneratedMachineStorage.swift](../Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift) |

## Stable contract

The documented types and observable outcomes in this guide are the generated
machine contract. `State`, `ActionLabel`, `TransitionResult`, `Live`, actor,
and observable adapters are the application-facing generated API.


## Claim sources

| Claim area | Evidence |
|---|---|
| Public annotations | `Sources/SwiftTLAMacros/Macros.swift` |
| Generated model and adapter members | `Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift`, `Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift`, and `Sources/SwiftTLAPlugin/MacroExpander.swift` |
| Observation and error behavior | `Sources/SwiftTLA/GeneratedMachineError.swift` and `Sources/SwiftTLA/LiveMachine.swift` |
| Action failure preserves state | Generated `apply(_:)` and `Tests/SwiftTLATests/GeneratedStateMachineTests.swift` |
| Public-workflow evidence labels | [Public workflow conformance](PublicWorkflowConformance.md) |
| Compilable examples | The fixtures named beside each example ID |
