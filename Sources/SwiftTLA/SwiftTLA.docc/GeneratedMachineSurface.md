# Generated machine surface

`@TLAModel` generates a typed Swift state machine from one compiled model.

## Generated types

Each generated model exposes these `Sendable` value types:

- `State`: immutable typed values for declared variables.
- `Action`: a typed action identity and typed parameters.
- `Transition`: typed action, state before, and state after for one successful transition.


## Direct value-model execution

`send(_:)` applies one typed action. `isEnabled(_:)` checks whether one typed action
is currently permitted. Both methods can throw. `state` contains the complete current
typed state.

## Generated actor

`Actor` owns one generated machine value. It serializes
`send(_:)` and exposes the machine's typed state and actions.

```swift
let actor = try Counter.Actor()
let transition = try await actor.send(.advance)
assert(await actor.state == transition.after)
```
