# Live Machines

A generated `Live` value owns one runtime identity, one mutable state, and one commit order.

A generated model value uses `Simulation` for local value work.

## Create a typed runtime

Create the runtime from its generated model.

```swift
let live = try Counter.makeLive()

assert(live.schema == Counter.machineSchema)
```

Calling `await live.end()` is idempotent. It ends the runtime for its typed adapters and observers.

The generated model validates its schema before it creates the runtime.

## Inspect a live machine

`Live` exposes a stable identity, the generated schema, and an atomic typed snapshot.

```swift
switch try await live.current() {
case .snapshot(let snapshot):
    print(snapshot.identity)
    print(snapshot.position)
    print(snapshot.state)
case .unavailable(let reason):
    print(reason)
}
```

The position starts at zero and advances once for each committed action. It is ordered within this runtime identity.

## Execute actions

Typed code uses the generated `Live` façade.

```swift
let typedOutcome = try await live.execute(.advance)
```

Each request produces exactly one generated `Live.Outcome`:

- `committed` contains the request ID, typed action, and atomic before/after snapshots. The after position is one more than the before position.
- `rejected` includes the current snapshot and a typed reason.
- `failed` includes the current snapshot and a typed failure.

Live execution selects one successor for each typed action. A multiple-successor result produces `ambiguousSuccessors` and leaves the runtime at its current snapshot.

## Create generated adapters

Generated `Live`, `@TLAActor`, and `@TLAObservable` values share one typed live runtime.

```swift
let live = try CounterHost.makeLive()
let actor = CounterHost.Actor(live: live)
let observable = try await CounterHost.Observable(live: live)
```

The observable adapter derives its typed cache from observation events. Its
`status` is `attaching`, `current`, `recovering`, `terminated`, or
`invalidEvent`. Its typed callbacks run for contiguous committed updates that
it decodes.

## Runtime scope

Live-machine observation provides identity, atomic state, per-runtime order,
bounded-loss reporting, resynchronization, and explicit runtime termination.
