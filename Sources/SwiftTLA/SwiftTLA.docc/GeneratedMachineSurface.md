# Generated machine surface

`@TLAModel` compiles the inline specification at build time and generates a
typed Swift state machine. Its initialization, guards, and transitions execute
ordinary Swift without runtime specification compilation or interpretation.
Apply it to a struct with a static `TLASpec` declaration.

## Generated types

Each generated machine exposes these `Sendable` value types:

- `State`: immutable typed values for declared variables.
- `Action`: a typed action identity and typed parameters.
- `Transition`: the typed action and state before and after one successful transition.

Collections use native `Set`, `Array`, and `Dictionary` values. Pairs and records
use generated immutable structs, and finite unions use generated enums.

## Direct generated-machine execution

`send(_:)` applies one typed action. `isEnabled(_:)` reports whether one action
is permitted in the current state. Both methods can throw. `state` exposes the
current values of declared variables; the machine also preserves compiler
control state internally.

SwiftUI stores the generated machine directly in `@State`. A successful
`send(_:)` replaces the complete value with its next state.

## Generated actor

`Actor` owns one generated machine. It
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

The typed initializer selects one unique state from the source model's declared
initial states.

## Property checks

`violatedInvariants()` reports the names of false invariants without changing
state. `assumptionsHold()` checks assumptions. State constraints filter
successors; invariant violations remain observable for verification.
