# Generated Machines

`@TLAModel` turns a verified `TLASpec` declaration into a Swift machine.
This guide documents the generated-machine public contract. A generated model
defines schema and formal behavior. A `TLALiveMachine` is the only mutable
live instance of that model. See [Live Machines](LiveMachines.md) for shared
inspection, observation, and control.
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

This example has one integer variable and two reachable values. It does not demonstrate unbounded state spaces, temporal properties, fairness, or a UI.

The fixture is the compilation authority for this example. It uses Swift tools 5.9 and the macOS 14 package context declared in `Package.swift`.

## Run actions

A generated model has typed `Variables`, `Actions`, `State`, `ActionLabel`, and
`TransitionResult` members. Use `availableActions()` to get typed labels. Use
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
the transition. `ActionLabel.toInvocation()` converts a typed label to a
`TLAActionInvocation`. `ActionLabel.init?(invocation:)` converts a valid
invocation back to a typed label.

`apply(_:)` throws `GeneratedMachineError` when it cannot execute an invocation. A rejected invocation does not replace the current snapshot.

Use `machineObservation()` when code needs state and availability together. It
returns `TLAMachineObservation` even when availability evaluation fails. The
observation contains a guarded `TLAStateProjectionResult`, not a raw state map.

Use this value API for local and deliberately independent work only. It is not
the shared live-machine path.

## Run a live machine

Create the runtime once with `TLALiveMachineOwner.create(for:)`, then bind the
generated `Live` façade to its existing handle. Binding validates exact schema
compatibility and never creates a second machine.

```swift
let owner = try TLALiveMachineOwner.create(for: BoundedCounter.self)
let handle = owner.handle
let live = try BoundedCounter.Live(handle: handle)

switch await live.execute(.advance) {
case .committed(let transition):
    assert(transition.after.value == 1)
case .rejected(let rejection):
    print(rejection.reason)
case .failed(let failure):
    print(failure.code)
}
```

Generic code uses the same runtime through `handle.identity`, `handle.schema`,
`current()`, `observe()`, and `execute(_:)`. Typed and generic actions share
one transition pipeline. Only `committed` changes state. An accepted action is
non-cancellable: it completes as `committed` or normal `failed`.

## Nest a machine

Put `@TLAActor` or `@TLAObservable` on a nested type inside a `@TLAModel`
struct. Bind the generated adapter to a compatible existing live handle. It
does not own model state, a second runtime, or shutdown authority.

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
    let owner = try TLALiveMachineOwner.create(for: CounterHost.self)
    let actor = try await CounterHost.Actor(handle: owner.handle)
    let result = await actor.execute(CounterHost.Actor.ActionLabel.advance.toInvocation())

    guard case .committed(let commit) = result else { return }
    assert(commit.after.position.value == 1)
}
```

The nested actor is asynchronous. Call `current()` or
`execute(_ invocation: TLAActionInvocation)` across its actor boundary. It
shares identity and state with every handle from the same owner.

Nested adapters expose the enclosing model's `State`, `ActionLabel`, and
`TransitionResult` through type aliases.

## Isolation and callbacks

A nested `@TLAObservable` adapter is main-actor isolated. It must be nested in
one `@TLAModel` struct. `@TLAActor` has the same nesting requirement. Neither adapter owns a formal specification or generates an independent machine.

A nested observable requires `await Observable(handle:)`. It attaches to that
runtime and derives its typed cache only from observation events. It does not
provide automatic SwiftUI invalidation beyond its main-actor properties.

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
    let owner = try TLALiveMachineOwner.create(for: CounterScreenModel.self)
    let observable = try await CounterScreenModel.Observable(handle: owner.handle)
    observable.onAdvance = { before, after in
        assert(before.value == 0)
        assert(after.value == 1)
    }
    let result = await observable.execute(CounterScreenModel.Observable.ActionLabel.advance.toInvocation())
    guard case .committed = result else { return }
}
```

For a nested observable, `execute(_ invocation: TLAActionInvocation)` submits
the request to the runtime. The callback occurs only when its subscription
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
    let initial = await machine.machineObservation()
    let result = try machine.apply(.advance)
    let beforeFailure = machine.state

    assert(initial.projection != nil)
    assert(initial.availableInvocations == [.init(name: "advance", arguments: [.string("only")])])
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

- `TLAMachineObservation.state` and its guarded projection result
- `TLAMachineObservation.availableInvocations`, or `availabilityDiagnostic`
- the attempted `TLAActionInvocation`
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

The generated `verifySpec()` returns the number of explored states. It, `transitionMatrix()`, `verifyTransitions()`, and `verifyInvariants()` use `TLAModelType.verificationStateLimit`, which defaults to `100_000`. A model can override that value for a published finite configuration with a larger checked graph. A limit failure is an error result. It does not establish a complete result outside that limit.

The public-workflow command has a separate bounded scope. A local result is `diagnosticOnly`. A result from the checked-in hosted workflow is `candidateEvidence` for its exact fixture.

Neither label means that all macro inputs, all generated machines, all platforms, or application UI behavior are supported. See [Public workflow conformance](PublicWorkflowConformance.md).

P1 core graph evidence and P3 temporal and symmetry evidence have separate registers and boundaries. A generated-machine example does not widen either surface. See [Core support](CoreSupport.md) and [Temporal and symmetry conformance](TemporalSymmetryConformance.md).

## SwiftUI

Keep the live owner and a handle-bound observable adapter in view state. The
adapter receives its state from the runtime observation, not from a copied
model value.

**Example ID:** `generated-machine-swiftui`  
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/CounterView.swift`

```swift
// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var owner: TLALiveMachineOwner?
    @State private var machine: CounterScreenModel.Observable?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(machine?.state.map { String($0.value) } ?? "-")")
            Button("Advance") {
                Task { @MainActor in
                    guard let machine else { return }
                    switch await machine.execute(CounterScreenModel.Observable.ActionLabel.advance.toInvocation()) {
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
            guard owner == nil else { return }
            do {
                let owner = try TLALiveMachineOwner.create(for: CounterScreenModel.self)
                self.owner = owner
                machine = try await CounterScreenModel.Observable(handle: owner.handle)
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
| `@TLAActor` | Requires a nested type. Its generated actor binds an existing compatible `TLALiveMachine` handle. | [Macros.swift](../Sources/SwiftTLAMacros/Macros.swift), [MacroExpander+Adapters.swift](../Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift) |
| `@TLAObservable` | Requires a nested type. Its generated main-actor adapter binds an existing compatible handle and reduces observation events. | [Macros.swift](../Sources/SwiftTLAMacros/Macros.swift), [MacroExpander+Adapters.swift](../Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift) |
| `TLALiveMachineOwner` | Creates one live runtime, vends its common handle, and is the sole explicit shutdown authority. | [LiveMachine.swift](../Sources/SwiftTLA/LiveMachine.swift) |
| `TLALiveMachine` | Common handle for type-unknown identity, schema, current snapshot, observation, and action requests. | [LiveMachine.swift](../Sources/SwiftTLA/LiveMachine.swift) |
| `GeneratedLiveMachine` and generated `Live` | Schema-validated typed façade over an existing live handle. | [GeneratedLiveMachine.swift](../Sources/SwiftTLA/GeneratedLiveMachine.swift), [MacroExpander+LiveMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+LiveMachine.swift) |
| `TLALiveMachineObservationSubscription` | Single-consumer async observation with snapshot, update, explicit loss, recovery, and owner termination. | [LiveMachineObservation.swift](../Sources/SwiftTLA/LiveMachineObservation.swift) |
| `TLALiveMachineAdapterBinding` | Validates an adapter binding to an existing generated live runtime without creating state. | [LiveMachineAdapter.swift](../Sources/SwiftTLA/LiveMachineAdapter.swift) |
| Generated `Variables` | `String`, `CaseIterable` enum of declared variables. Each case supplies its raw variable name. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `Actions` | `String`, `CaseIterable` enum of declared action names. Each case supplies its declared action name. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| `TLAStateProjection` | Provides guarded token-based access to a formal state. It owns its internal representation. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAStateProjectionResult` | Contains a valid projection or a typed projection diagnostic. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineObservation` | Contains a guarded state projection result and either available invocations or an availability diagnostic. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineAvailabilityDiagnostic` | Reports an `evaluationFailed` or `stateProjectionFailed` code and a message. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineObserving` | Provides async `machineObservation()`. Its extensions provide `machineState()` and `machineAvailability()`. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineExecuting` | Extends observation with async throwing `execute(_ invocation: TLAActionInvocation)`. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAActionInvocation` | Identifies an action by name and declared arguments. It is the untyped invocation form. | [TLASpec.swift](../Sources/SwiftTLA/TLASpec.swift) |
| `GeneratedMachineError` | Wraps a runtime error, an unexpected error, or an unrepresentable action label. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| Generated `VerificationError` | Error type returned by generated verification helpers when the bounded check does not succeed. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `runtime` | Static `SpecRuntime` for the declared specification. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `verifySpec()` | Runs the generated bounded specification check and returns its explored-state count; it uses `TLAModelType.verificationStateLimit` (default: `100_000`). | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `transitionMatrix()` | Returns the explored transitions as source state, invocation, and target state tuples. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `verifyTransitions()` | Compares each generated transition with the runtime successors for that source state and invocation. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `verifyInvariants()` | Checks declared invariants on explored transition targets when the model has actions and invariants. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `State` | Holds model variables with generated Swift types. Application code reads this type through `state`, before, and after. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `ActionLabel` | Represents declared actions with typed parameters. `toInvocation()` writes a `TLAActionInvocation`. `init?(invocation:)` reads a valid one. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `TransitionResult` | Records the typed action and typed state before and after a successful transition. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `tlaSnapshot()` | Returns `TLAStateProjectionResult` on a generated value model. It is not live-runtime observation. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `availableActions()` | Returns typed available action labels for a model that declares actions. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `availableInvocations()` | Returns runtime `TLAActionInvocation` values on a generated model without declared actions. `TLAMachineObservation` reports runtime availability for every generated machine. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `apply(_:)` | Executes a typed label or `TLAActionInvocation`. It returns `TransitionResult` or throws. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `machineObservation()` | Returns current state and availability. It retains state if availability evaluation fails. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `Live.execute(_:)` | Executes a typed label or generic invocation through the existing live runtime and returns an explicit live outcome. | [MacroExpander+LiveMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+LiveMachine.swift) |
| Generated `synchronousMachineObservation()` | Returns current state and availability without an async boundary on a canonical generated model. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `executeSynchronously(_ invocation: TLAActionInvocation)` | Executes an invocation without an async boundary on a canonical generated model. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |

This guide explicitly excludes removed `@TypedVar` and `@TLAValidated`, private
`_machine` storage, underscored generated helpers such as `_<action>`, and
unsupported annotation combinations. Do not use them as stable public APIs.

## Stable contract

The documented names and observable outcomes in this guide form the current generated-machine documentation contract.

Generated source layout, private storage, underscored helpers, callback scheduling outside stated isolation, and unsupported annotation combinations are not part of this contract.

No SemVer promise is made here. If a future release changes a documented public contract, its release notes must name the affected contract and required migration action.

## Claim sources

| Claim area | Evidence |
|---|---|
| Public annotations | `Sources/SwiftTLAMacros/Macros.swift` |
| Generated model and adapter members | `Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift`, `Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift`, and `Sources/SwiftTLAPlugin/MacroExpander+Generation.swift` |
| Observation and error behavior | `Sources/SwiftTLA/CanonicalMachine.swift` and `Sources/SwiftTLA/SpecRuntime.swift` |
| Action failure preserves state | `CanonicalMachine.apply(_:)` and `Tests/SwiftTLATests/GeneratedStateMachineTests.swift` |
| Public-workflow evidence labels | [Public workflow conformance](PublicWorkflowConformance.md) |
| Compilable examples | The fixtures named beside each example ID |
