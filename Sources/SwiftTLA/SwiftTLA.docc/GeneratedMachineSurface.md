# Generated machine surface

`@TLAModel` generates the typed schema, formal behavior, and `Live` runtime façade for a machine.

## Generated types

Each generated model exposes these `Sendable` value types:

- `State`: typed values for declared variables.
- `ActionLabel`: a typed action identity and typed parameters.
- `TransitionResult`: typed action, state before, and state after for direct value-model execution.
- `MachineObservation`: typed state and currently available typed action labels.


## Direct value-model execution

`apply(_:)`, `machineObservation()`, and `TransitionResult` provide direct value-model execution. `machineObservation()` returns typed `State` and `ActionLabel` values.

## Create a live runtime

Create a typed live runtime from the generated model:

```swift
let live = try Counter.makeLive()
```

`Live.end()` is explicit and idempotent. A generated `Live` value owns one runtime identity and its actor-owned state.

## Typed control

Use a generated label with `Live.execute(_:)`.

```swift
let typedOutcome = await live.execute(.advance)
```

Generated `Live.Outcome` is exhaustive:

- `committed` contains atomic before and after snapshots and advances the runtime position once.
- `rejected` contains the current snapshot and a validation or lifecycle reason.
- `failed` contains the current snapshot and a failure reason.

Accepted requests complete as `committed` or `failed`. Live execution requires one formal successor and reports `ambiguousSuccessors` when the evaluator finds more than one.

Positions begin at zero and have meaning only within one runtime identity. `Live.current()` returns an atomic typed snapshot with the state and available actions for that position.

## Generated adapters

Nested `@TLAActor` and `@TLAObservable` types accept the enclosing model's typed `Live` value with `init(live:)`. The actor forwards control to that runtime. The main-actor observable adapter reduces subscription events into its typed cache. It records `recovering` after loss and `terminated` after runtime termination.

## Verification helpers

Generated models provide `verifySpec()`, `transitionMatrix()`, `verifyTransitions()`, and `verifyInvariants()` for their declared finite model. These helpers use the bounded checker and the model's `verificationStateLimit` (default: `100_000`).

For a narrative guide and limits, read `Documentation/GeneratedMachines.md` and `Documentation/LiveMachines.md` in the repository.
