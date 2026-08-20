# Generated Machines

`@TLAModel` turns a verified `TLASpec` declaration into a Swift machine.
This guide documents the generated-machine public contract. A generated model
defines schema and formal behavior. Its `Live` value owns the mutable runtime.
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

The macro parses the specification and runs bounded model checking during macro expansion for the supported model shape.

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

    enum Step: String, PlusCalLabel {
        case advance
    }

    static var spec: TLASpec {
        #spec("BoundedCounter") {
            Algorithm("BoundedCounter") {
                let value = SharedVar(initial: 0)
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
    var machine = BoundedCounter()
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

Use this value API for local and deliberately independent work only. It is not
the shared live-machine path.

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

    enum Step: String, PlusCalLabel {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterHost") {
            Algorithm("CounterHost") {
                let value = SharedVar(initial: 0)
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

For each action, a nested observable generates an `on<Action>` callback property. The callback receives action parameters, when present, and typed state values from before and after a successful execution.

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

    enum Step: String, PlusCalLabel {
        case advance
    }

    static var spec: TLASpec {
        #spec("CounterScreenModel") {
            Algorithm("CounterScreenModel") {
                let value = SharedVar(initial: 0)
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
    observable.onAdvance = { before, after in
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

Do not depend on callback scheduling beyond main-actor isolation. Do not infer
a global order between callbacks on separate adapters. The generated names
that start with `_` are convenience methods, not the supported public
integration surface.

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
    var machine = BoundedCounter()
    let initial = try await machine.machineObservation()
    let result = try machine.apply(.advance)
    let beforeFailure = machine.state

    assert(initial.state.value == 0)
    assert(initial.availableActions == [.advance])
    assert(result.after.value == 1)

    do {
        _ = try machine.apply(.advance)
        assertionFailure("Expected an unavailable action")
    } catch is GeneratedMachineError {
        assert(machine.state == beforeFailure)
    }
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

`TLAMachineAvailabilityDiagnostic` has `evaluationFailed` and
`stateProjectionFailed` codes. An unavailable observation does not make a raw
state map public. An execution failure does not commit a successor state.

For a macro expansion problem, collect the macro diagnostic and model source.
When the macro provides the invariant name and trace, record them. Record the explored
state count, limit, Swift toolchain, and platform context.

## Limits and evidence

Generated-machine verification depends on a declared finite state space and a configured exploration limit. It is not a proof for unbounded models.

The generated `verifySpec()`, `verifyTransitions()`, and `verifyInvariants()` use `TLAModelType.verificationStateLimit`, which defaults to `100_000`. They return the verified state, transition, and invariant-check counts. A model can override that value for a published finite configuration with a larger checked graph. A limit failure is an error result.

The public-workflow command has a separate bounded scope. A local result is `diagnosticOnly`. A result from the checked-in hosted workflow is `candidateEvidence` for its exact fixture.

Neither label means that all macro inputs, all generated machines, all platforms, or application UI behavior are supported. See [Public workflow conformance](PublicWorkflowConformance.md).

P1 core graph evidence and P3 temporal and symmetry evidence have separate registers and boundaries. A generated-machine example does not widen either surface. See [Core support](CoreSupport.md) and [Temporal and symmetry conformance](TemporalSymmetryConformance.md).

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
| `GeneratedMachineError` | Wraps a runtime error, an unexpected error, or an unrepresentable action label. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| Generated `VerificationError` | Error type returned by generated verification helpers when the bounded check does not succeed. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `verifySpec()` | Runs the generated bounded specification check and returns its explored-state count; it uses `TLAModelType.verificationStateLimit` (default: `100_000`). | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `verifyTransitions()` | Compares each generated transition with the runtime successors for that source state and returns the verified transition count. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `verifyInvariants()` | Checks declared invariants on explored transition targets and returns the verified invariant-check count. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `State` | Holds model variables with generated Swift types. Application code reads this type through `state`, before, and after. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `ActionLabel` | Represents declared actions with typed parameters. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `TransitionResult` | Records the typed action and typed state before and after a successful transition. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `availableActions()` | Returns typed available action labels for a model that declares actions. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `apply(_:)` | Executes a typed `ActionLabel`. It returns `TransitionResult` or throws. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `MachineObservation` | Records typed state and currently available typed action labels. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `machineObservation()` | Returns `MachineObservation` or throws. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `Live.execute(_:)` | Executes a typed label through the existing live runtime and returns an explicit live outcome. | [MacroExpander+LiveMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+LiveMachine.swift) |
| Generated `synchronousMachineObservation()` | Returns current state and availability without an async boundary on a canonical generated model. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |

This guide explicitly excludes removed `@TypedVar` and `@TLAValidated`, private
`_machine` storage, underscored generated helpers such as `_<action>`, and
unsupported annotation combinations. Do not use them as stable public APIs.

## Stable contract

The documented names and observable outcomes in this guide form the current generated-machine documentation contract.

Generated source layout, private storage, underscored helpers, callback scheduling outside stated isolation, and unsupported annotation combinations are not part of this contract.


## Claim sources

| Claim area | Evidence |
|---|---|
| Public annotations | `Sources/SwiftTLAMacros/Macros.swift` |
| Generated model and adapter members | `Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift`, `Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift`, and `Sources/SwiftTLAPlugin/MacroExpander+Generation.swift` |
| Observation and error behavior | `Sources/SwiftTLA/CanonicalMachine.swift` and `Sources/SwiftTLA/SpecRuntime.swift` |
| Action failure preserves state | `CanonicalMachine.apply(_:)` and `Tests/SwiftTLATests/GeneratedStateMachineTests.swift` |
| Public-workflow evidence labels | [Public workflow conformance](PublicWorkflowConformance.md) |
| Compilable examples | The fixtures named beside each example ID |
