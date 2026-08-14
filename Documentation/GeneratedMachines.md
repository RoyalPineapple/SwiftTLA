# Generated Machines

`@TLAModel` turns a verified `TLASpec` declaration into a Swift machine.
This guide documents the current generated-machine public contract. The
contract covers generated models and their model-owned adapters.
Read [the SwiftTLA DocC catalog](../Sources/SwiftTLA/SwiftTLA.docc/SwiftTLA.md)
for the symbol-oriented reference.

## Contents

- [Generate a machine](#generate-a-machine)
- [Run actions](#run-actions)
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
`apply(_:)` to execute one label synchronously on a non-actor model.

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

An adapter does not execute an `ActionLabel` directly. Follow
`ActionLabel` → `toInvocation()` →
`execute(_ invocation: TLAActionInvocation)`:

```swift
let label: CounterHost.Actor.ActionLabel = .advance
let invocation = label.toInvocation()
let result = try await actor.execute(invocation)
```

## Nest a machine

Put `@TLAActor` or `@TLAObservable` on a nested type inside a `@TLAModel`
struct. The generated adapter owns its own canonical instance of the enclosing
model type. It does not share mutable state with another adapter or with a
separately created enclosing model.

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
    let actor = CounterHost.Actor()
    let state = await actor.state
    let result = try await actor.execute(CounterHost.Actor.ActionLabel.advance.toInvocation())

    assert(state.value == 0)
    assert(result.action == CounterHost.Actor.ActionLabel.advance)
    assert(result.after.value == 1)
}
```

The nested actor provides its own canonical machine instance. Actor access is
asynchronous. Call `machineObservation()` or
`execute(_ invocation: TLAActionInvocation)` across its actor boundary.

Nested adapters expose the enclosing model's `State`, `ActionLabel`, and
`TransitionResult` through type aliases.

## Isolation and callbacks

A nested `@TLAObservable` adapter is main-actor isolated. It must be nested in
one `@TLAModel` struct. `@TLAActor` has the same nesting requirement. Neither adapter owns a formal specification or generates an independent machine.

A nested observable owns its own canonical model and provides async action
execution. It does not provide automatic SwiftUI invalidation or shared state
between adapters.

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
    let observable = CounterScreenModel.Observable()
    observable.onAdvance = { before, after in
        assert(before.value == 0)
        assert(after.value == 1)
    }
    let result = try await observable.execute(CounterScreenModel.Observable.ActionLabel.advance.toInvocation())
    assert(result.action == CounterScreenModel.Observable.ActionLabel.advance)
}
```

For a nested observable, `execute(_ invocation: TLAActionInvocation)` first
commits the successful transition, then awaits the matching callback, then
returns its transition result. A failed execution does not call the callback.

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

The generated `verifySpec()`, `transitionMatrix()`, `verifyTransitions()`, and `verifyInvariants()` methods use a `100_000` state limit in the current macro generator. A limit failure is an error result. It does not establish a complete result outside that limit.

The public-workflow command has a separate bounded scope. A local result is `diagnosticOnly`. A result from the checked-in hosted workflow is `candidateEvidence` for its exact fixture.

Neither label means that all macro inputs, all generated machines, all platforms, or application UI behavior are supported. See [Public workflow conformance](PublicWorkflowConformance.md).

P1 core graph evidence and P3 temporal and symmetry evidence have separate registers and boundaries. A generated-machine example does not widen either surface. See [Core support](CoreSupport.md) and [Temporal and symmetry conformance](TemporalSymmetryConformance.md).

## SwiftUI

Store the generated typed `State` and an optional `TLAMachineObservation` in
view state. Refresh both values after a successful action. This pattern does
not claim automatic updates.

**Example ID:** `generated-machine-swiftui`  
**Fixture:** `Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/CounterView.swift`

```swift
// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var machine = CounterScreenModel.Observable()
    @State private var state: CounterScreenModel.State?
    @State private var observation: TLAMachineObservation?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(state.map { String($0.value) } ?? "-")")
            Button("Advance") {
                Task { @MainActor in
                    do {
                        _ = try await machine.execute(CounterScreenModel.Observable.ActionLabel.advance.toInvocation())
                        state = machine.state
                        observation = await machine.machineObservation()
                        diagnostic = ""
                    } catch {
                        diagnostic = String(describing: error)
                    }
                }
            }
            if let invocations = observation?.availableInvocations {
                ForEach(invocations, id: \.self) { invocation in
                    Text(invocation.description)
                }
            } else if let diagnostic = observation?.availabilityDiagnostic {
                Text(diagnostic.message)
            }
            if !diagnostic.isEmpty {
                Text(diagnostic)
            }
        }
        .task {
            state = machine.state
            observation = await machine.machineObservation()
        }
    }
}
```

The fixture compiles this view in the macOS package context. A manual review must inspect the initial render and the render after `advance`.

The example omits disabled-button logic and automatic observation. It displays
the public execution error after a rejected action.

## API reference

The following table is the public inventory for this guide. Sources identify the declaration or generator that establishes each claim.

| Name | Role and observable contract | Source |
|---|---|---|
| `@TLAModel` | Attaches generated machine members to a struct, class, or actor with a `TLASpec`. | [Macros.swift](../Sources/SwiftTLAMacros/Macros.swift), [ModelMacro.swift](../Sources/SwiftTLAPlugin/ModelMacro.swift) |
| `@TLAActor` | Requires a nested type. It attaches an actor adapter for the enclosing model type. | [Macros.swift](../Sources/SwiftTLAMacros/Macros.swift), [ModelMacro.swift](../Sources/SwiftTLAPlugin/ModelMacro.swift) |
| `@TLAObservable` | Requires a nested type. It attaches a main-actor adapter for the enclosing model type. | [Macros.swift](../Sources/SwiftTLAMacros/Macros.swift), [ModelMacro.swift](../Sources/SwiftTLAPlugin/ModelMacro.swift), [MacroExpander+Adapters.swift](../Sources/SwiftTLAPlugin/MacroExpander+Adapters.swift) |
| Generated `Variables` | `String`, `CaseIterable` enum of declared variables. Each case supplies its raw variable name. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `Actions` | `String`, `CaseIterable` enum of declared action names. Each case supplies its declared action name. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| `TLAStateProjection` | Provides guarded token-based access to a formal state. It owns its internal representation. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAStateProjectionResult` | Contains a valid projection or a typed projection diagnostic. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineObservation` | Contains a guarded state projection result and either available invocations or an availability diagnostic. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineAvailabilityDiagnostic` | Reports an `evaluationFailed` or `stateProjectionFailed` code and a message. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineObserving` | Provides async `machineObservation()`. Its extensions provide `machineState()` and `machineAvailability()`. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineExecuting` | Extends observation with async throwing `execute(_ invocation: TLAActionInvocation)`. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineAdapterCanonicalModel` | Protocol for a canonical adapter model. It provides synchronous observation and `executeSynchronously(_:)`. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAMachineAdapterAccess` | Protocol for an adapter that provides async `withCanonicalMachine(_:)`. Its constrained extension provides `canonicalMachineObservation()` and `executeCanonical(_:)`. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| `TLAActionInvocation` | Identifies an action by name and declared arguments. It is the untyped invocation form. | [TLASpec.swift](../Sources/SwiftTLA/TLASpec.swift) |
| `GeneratedMachineError` | Wraps a runtime error, an unexpected error, or an unrepresentable action label. | [CanonicalMachine.swift](../Sources/SwiftTLA/CanonicalMachine.swift) |
| Generated `VerificationError` | Error type returned by generated verification helpers when the bounded check does not succeed. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `runtime` | Static `SpecRuntime` for the declared specification. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `verifySpec()` | Runs the generated bounded specification check with the current `100_000` state limit. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `transitionMatrix()` | Returns the explored transitions as source state, invocation, and target state tuples. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `verifyTransitions()` | Compares each generated transition with the runtime successors for that source state and invocation. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `verifyInvariants()` | Checks declared invariants on explored transition targets when the model has actions and invariants. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `State` | Holds model variables with generated Swift types. Application code reads this type through `state`, before, and after. | [MacroExpander.swift](../Sources/SwiftTLAPlugin/MacroExpander.swift) |
| Generated `ActionLabel` | Represents declared actions with typed parameters. `toInvocation()` writes a `TLAActionInvocation`. `init?(invocation:)` reads a valid one. | [MacroExpander+Generation.swift](../Sources/SwiftTLAPlugin/MacroExpander+Generation.swift) |
| Generated `TransitionResult` | Records the typed action and typed state before and after a successful transition. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `tlaSnapshot()` | Returns `TLAStateProjectionResult` on a generated model and its model-owned adapters. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `availableActions()` | Returns typed available action labels for a model that declares actions. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `availableInvocations()` | Returns runtime `TLAActionInvocation` values on a generated model without declared actions. `TLAMachineObservation` reports runtime availability for every generated machine. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `apply(_:)` | Executes a typed label or `TLAActionInvocation`. It returns `TransitionResult` or throws. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `machineObservation()` | Returns current state and availability. It retains state if availability evaluation fails. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `execute(_ invocation: TLAActionInvocation)` | Asynchronously executes an invocation and returns `TransitionResult`. Convert a typed `ActionLabel` first. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `synchronousMachineObservation()` | Returns current state and availability without an async boundary on a canonical generated model. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |
| Generated `executeSynchronously(_ invocation: TLAActionInvocation)` | Executes an invocation without an async boundary on a canonical generated model. | [MacroExpander+CanonicalMachine.swift](../Sources/SwiftTLAPlugin/MacroExpander+CanonicalMachine.swift) |

This guide explicitly excludes `@TypedVar`, removed `@TLAValidated`, private
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
