# Generated machine surface

`@TLAModel` generates a typed Swift state machine from one compiled model.

## Generated types

Each generated model exposes these `Sendable` value types:

- `State`: typed values for declared variables.
- `Action`: a typed action identity and typed parameters.
- `Transition`: typed action, state before, and state after for one successful transition.


## Direct value-model execution

`send(_:)` applies one typed action. `isEnabled(_:)` checks whether one typed action
is currently permitted. Both methods can throw. `state` contains the complete current
typed state.

## Create a live runtime

Create a typed live runtime from the generated model:

```swift
let live = try Counter.makeLive()
```

`Live.end()` is explicit and idempotent. A generated `Live` value owns one runtime identity and its actor-owned state.

## Typed control

Use a generated action with `Live.send(_:)`.

```swift
let typedOutcome = await live.send(.advance)
```

Generated `Live.Outcome` is exhaustive:

- `committed` contains atomic before and after snapshots and advances the runtime position once.
- `rejected` contains the current snapshot and a validation or lifecycle reason.
- `failed` contains the current snapshot and a failure reason.

Accepted requests complete as `committed` or `failed`. A live action reports `ambiguousAction` when it produces more than one successor.

Positions begin at zero and have meaning only within one runtime identity. `Live.current()` returns an atomic typed snapshot with the state and enabled actions for that position.

## Generated actor

Nested `@TLAActor` types accept the enclosing model's typed `Live` value with `init(live:)`. The actor forwards control to that runtime.
