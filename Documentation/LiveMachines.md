# Live Machines

A live machine is a reference-owned runtime. It has one identity, one mutable state, and one commit order. It is the public way to inspect, observe, and control a machine that is already running.

A generated model value uses `Simulation` for local value work. A live runtime is created through `TLALiveMachineOwner` and shared through its handle.

## Create and share a runtime

Create the runtime once. Keep its `TLALiveMachineOwner` for as long as the runtime must stay available. Give `owner.handle` to generated typed code. Copies of that handle address the same runtime; they do not copy state.

```swift
let owner = try TLALiveMachineOwner.create(for: Counter.self)
let handle = owner.handle
let typed = try Counter.Live(handle: handle)

assert(handle.identity == typed.identity)
assert(handle.schema == typed.schema)
```

`TLALiveMachineOwner` is the only public shutdown authority. Calling `await owner.end()` is idempotent. It ends the runtime for every handle and observer. Releasing a handle does not end the runtime.

The runtime validates a generated schema before it is created. Binding `Counter.Live(handle:)` validates the supplied handle's schema again. A schema mismatch throws `GeneratedLiveMachineDiagnostic`; it never creates a replacement runtime.

## Inspect a live machine

`TLALiveMachine` is the common interface for generic tools. It exposes a stable `identity`, a generated `MachineSchema`, and an atomic current snapshot. A snapshot contains a guarded `TLAStateProjection`, not a public raw formal-state dictionary.

```swift
switch await handle.current() {
case .snapshot(let snapshot):
    print(snapshot.identity)
    print(snapshot.schemaIdentifier)
    print(snapshot.position)
    print(snapshot.state.entries)
case .unavailable(let reason):
    print(reason)
}
```

The position starts at zero and advances once for each committed action. It is ordered only within this runtime identity. The snapshot's availability is the availability computed for that same committed state.

## Execute actions

Typed code uses the generated `Live` façade.

```swift
let typed = try Counter.Live(handle: handle)
let typedOutcome = await typed.execute(.advance)
```

Each request produces exactly one `TLALiveActionOutcome`:

- `committed` contains the request ID, invocation, and atomic before/after snapshots. The after position is one more than the before position.
- `rejected` means the runtime did not accept the request. It includes the current snapshot and a reason such as an ended runtime, wrong identity, schema mismatch, unknown action, invalid arguments, or an unavailable action.
- `failed` means an accepted request could not complete. State and position remain at the included current snapshot.

Once execution enters the runtime, it is non-cancellable. Cancelling the caller cannot turn an accepted action into a non-commit result. It completes as a normal `committed` or `failed` outcome. Live execution also requires one formal successor. If the formal evaluator returns multiple successors, the runtime returns `ambiguousSuccessors` and commits none of them; successor array order is never a policy.

## Observe a running runtime

Call `observe()` on the existing handle. Attachment and the initial snapshot are serialized with commits. Therefore an overlapping commit is either in the initial snapshot or is delivered once as the next update.

```swift
guard case .attached(let subscription) = await handle.observe() else {
    return
}

var iterator = subscription.makeAsyncIterator()
while let event = await iterator.next() {
    switch event {
    case .snapshot(let snapshot, _):
        print(snapshot.position)
    case .update(let commit):
        print(commit.after.position)
    case .loss:
        _ = await subscription.resynchronize()
    case .terminated(let termination):
        print(termination.reason)
        return
    }
}
```

Each subscription has a bounded mailbox. When it cannot retain every update, it emits `loss` and pauses ordinary delivery. Call `resynchronize()` to queue an atomic snapshot with a new ordering point. If the owner ended the runtime first, recovery returns a terminal result instead. Cancelling a subscription stops only that subscription; it does not cancel actions, affect peer observers, or end the runtime.

## Bind generated adapters

Generated `Live`, `@TLAActor`, and `@TLAObservable` surfaces require an existing handle. They do not have a zero-argument live constructor and they do not own a second machine.

```swift
let owner = try TLALiveMachineOwner.create(for: CounterHost.self)
let handle = owner.handle

let live = try CounterHost.Live(handle: handle)
let actor = try await CounterHost.Actor(handle: handle)
let observable = try await CounterHost.Observable(handle: handle)
```

The observable adapter derives its typed cache only from observation events. Its `status` is `attaching`, `current`, `recovering`, `terminated`, or `invalidEvent`; `current` and `state` are unavailable while it recovers. It does not optimistically mutate local state when it submits an action. Its typed callbacks run only for contiguous committed updates that it can decode.

## Limits

Live-machine observation is in-process. It provides identity, atomic state, per-runtime order, bounded-loss reporting, resynchronization, and explicit owner termination. It does not provide a persisted history, cross-runtime global order, remote transport, trace export, timestamps, or an invariant status feed.
