# Migrate to One Live Machine

Use `TLALiveMachine` when a machine must be running, shared, inspected, or observed. A generated model value is not a live-runtime handle.

## Representative migration

Before, independently created values or session-style wrappers could look like one machine while each retained separate state:

```swift
var machine = Counter()
let session = TLAMachineSession(machine)
let actor = Counter.Actor()
```

Do not use this shape for live coordination. It cannot attach the session or adapter to `machine`'s mutable state.

Create one owner and bind every live consumer to its handle instead:

```swift
let owner = try TLALiveMachineOwner.create(for: Counter.self)
let handle = owner.handle

let inspectorHandle = handle
let typed = try Counter.Live(handle: handle)
let actor = try await Counter.Actor(handle: handle)
let observable = try await Counter.Observable(handle: handle)
```

All four handles identify the same runtime. Actions through one are visible to the others through `current()` and `observe()`.

## Replace old live entry points

| Previous use | Replacement | Meaning |
|---|---|---|
| `TLAMachineSession(model)` for live inspection | `owner.handle.observe()` | Attaches to the existing runtime; no model copy. |
| `machineUpdates()` | `TLALiveMachineObservationSubscription` | Initial snapshot, ordered updates, explicit loss, and termination. |
| Zero-argument `@TLAActor` or `@TLAObservable` for live work | `await Actor(handle:)` or `await Observable(handle:)` | Binds the adapter to a compatible existing runtime. |
| Adapter-local state as the live source | `TLALiveMachine.current()` and observation events | The runtime is the sole mutable live source. |
| Direct `apply(_:)` for shared live work | `Live.execute(_:)` or `handle.execute(_:)` | Produces committed, rejected, or failed live outcomes. Keep `Simulation` only for explicitly non-live value work. |

## Release notes

The copy-owning `TLAMachineSession` and its `machineUpdates()` interface are
removed. Zero-argument live actor and observable adapters are removed. Use a
`TLALiveMachineOwner`, its `TLALiveMachine` handle, and the generated
handle-bound `Live`, actor, or observable surface instead. Generated
`Simulation` names the retained non-live value-model path.

## Lifecycle changes

Keep the `TLALiveMachineOwner` where your application owns the runtime lifetime. Calling `await owner.end()` makes current snapshots unavailable, rejects future requests, and sends one terminal event to each connected observer. Cancelling an observation subscription affects only that subscription. Cancelling a caller after its request was accepted does not cancel the runtime's execution.

## Direct model values

Each generated model names its direct value surface `Simulation` (`typealias Simulation = Self`). Use it only when value semantics are what you want: local calculation, a test fixture, or a deliberately independent simulation. Do not describe such a value as an inspector, observer, adapter, or handle for an existing live runtime.
