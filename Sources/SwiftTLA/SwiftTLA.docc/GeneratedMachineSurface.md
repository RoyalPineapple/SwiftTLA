# Generated machine surface

`@TLAModel` generates a typed Swift state machine from one compiled model.

## Generated types

Each generated model exposes these `Sendable` value types:

- `State`: immutable typed values for declared variables.
- `Action`: a typed action identity and typed parameters.
- `Transition`: the typed action and state before and after one successful transition.


## Direct value-model execution

`send(_:)` applies one typed action. `isEnabled(_:)` reports whether one action
is permitted in the current state. Both methods can throw. `state` contains
the complete current typed state.

SwiftUI stores the generated machine directly in `@State`. A successful
`send(_:)` replaces the complete value with its next state.

## Generated actor

`Actor` is a thin asynchronous adapter over one generated machine value. It
serializes `send(_:)` and exposes the same typed state and actions.

```swift
let actor = try Counter.Actor()
let transition = try await actor.send(.advance)
let actorState = await actor.state
assert(actorState == transition.after)

let seeded = try Counter.Actor(.init(count: 0))
let seededState = await seeded.state
assert(seededState.count == 0)
```

The typed initializer selects one unique state from the model's declared
initial states.
