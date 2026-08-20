# Generated machine surface

`@TLAModel` generates the typed schema and formal behavior of a machine. It also generates a typed `Live` façade. `Live` binds an existing ``TLALiveMachine``; it does not own mutable model state or create a runtime.

## Generated types

Each generated model exposes these `Sendable` value types:

- `State`: typed values for declared variables.
- `Variables`: declared variable names.
- `Actions`: declared action names when actions exist.
- `ActionLabel`: a typed action identity and typed parameters.
- `TransitionResult`: typed action, state before, and state after for direct value-model execution.

`ActionLabel.toInvocation()` converts a typed label to a ``TLAActionInvocation``. `ActionLabel.init?(invocation:)` accepts only a valid invocation for that generated type.

## Direct value-model execution

`apply(_:)`, `machineObservation()`, `TLAStateProjectionResult`, and `TransitionResult` remain useful for value semantics. A direct value model is not a live machine: it has no runtime identity, shared mutable state, subscription, or observation history. Use it for local calculation and deliberately independent simulation, not for a running shared machine.

## Create a live runtime

Create a runtime once from the generated model, retain its owner, and pass its handle to every consumer:

```swift
let owner = try TLALiveMachineOwner.create(for: Counter.self)
let handle = owner.handle
let live = try Counter.Live(handle: handle)
```

The owner is the only shutdown authority. `end()` is explicit and idempotent. Handle copies share the same stable ``TLALiveMachineIdentity`` and actor-owned state. A `Live(handle:)` binding checks the exact generated ``MachineSchema``; an incompatible handle throws ``GeneratedLiveMachineDiagnostic`` rather than creating a substitute runtime.

## Typed and generic control

Use a generated label with `Live.execute(_:)` or a generic invocation with ``TLALiveMachine/execute(_:requestID:)``. Both reach the same formal transition pipeline.

```swift
let typedOutcome = await live.execute(.advance)
let genericOutcome = await handle.execute(
    TLAActionInvocation(name: "advance", arguments: [])
)
```

``TLALiveActionOutcome`` is exhaustive:

- `committed` contains atomic before and after snapshots and advances the per-runtime ``TLALiveMachinePosition`` once.
- `rejected` did not enter execution and contains the unchanged current snapshot plus a validation or lifecycle reason.
- `failed` entered execution but did not commit; its current snapshot proves state and position remain unchanged.

After a request is accepted, execution is non-cancellable. Caller cancellation cannot report that an accepted action did not commit. If the formal evaluator produces more than one successor, live execution fails with `ambiguousSuccessors`; array order never selects a successor.

## Inspect an unknown live machine

``TLALiveMachine`` is the type-unknown common surface. It provides the runtime identity, generated schema, atomic `current()` snapshots, observation, and generic action execution. A snapshot contains a validated ``TLAStateProjection``, never a public `[String: TLAValue]` map.

Positions begin at zero and have meaning only within one runtime identity. The snapshot availability was evaluated for the exact snapshot state.

## Observe and recover

`observe()` attaches to an existing runtime. Its first event is an atomic snapshot. An overlapping commit is either already in that baseline or is delivered once as the following update.

``TLALiveMachineObservationSubscription`` is a single-consumer `AsyncSequence` of ``TLALiveMachineObservationEvent``. It yields snapshot, update, explicit loss, and one owner-termination event. Its mailbox is bounded. After `loss`, do not treat updates as contiguous; call `resynchronize()` and wait for the recovery snapshot. Cancellation ends only that subscription. It does not end the runtime or cancel an accepted action.

## Generated adapters

Nested `@TLAActor` and `@TLAObservable` types bind a supplied compatible handle with `init(handle:)`; they do not provide zero-argument live ownership. The actor forwards control to the same runtime. The main-actor observable adapter reduces subscription events into its typed cache. Its state is not optimistically changed by an action request. On loss it becomes recovering and waits for a resynchronization snapshot; on owner termination it becomes terminated.

## Verification helpers

Generated models provide `verifySpec()`, `transitionMatrix()`, `verifyTransitions()`, and `verifyInvariants()` for their declared finite model. These helpers use the bounded checker and the model's `verificationStateLimit` (default: `100_000`). They do not prove behavior outside the declared bounds or supported SwiftTLA surface.

For a narrative guide and limits, read `Documentation/GeneratedMachines.md` and `Documentation/LiveMachines.md` in the repository.
