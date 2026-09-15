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
state. `assumptionsHold()` checks assumptions. State constraints select states
for exploration. They do not change application transitions or action enabledness.
Invariant checks include excluded initial states and successor candidates.

## Model-owned validation scenarios

`Validation("Completes at two") { Bind(limit, to: 2); Bind(stopAtLimit, to: true) }`
declares a finite configuration beside the algorithm. `.expectDeadlock(.violated)`
changes the expected deadlock outcome without disabling its check.

`Model.validationScenarios()` returns immutable generated scenario values.
Each scenario provides `initialMachines()`, `explore(maximumStates:)`, and `render()`.
Generated scenarios conform to `ModelValidationScenario`, which supplies shared
exploration through the generated machine.
Its typed `expectations` include every named property, with `.satisfied` as the
default. `.expect(propertyHandle, .violated)` overrides one expectation.
The property handle must appear in the specification body to register its declaration.

Scalar scenario bindings retain parameter identities and checked value types.
Missing, duplicate, and foreign bindings fail explicitly. Collection bindings
and refinement expectations remain unfinished.

Repository validation derives canonical graphs and native results directly from
scenarios. It validates expected outcomes only after complete exploration.
The adapter reads rendered check metadata without compiling the specification again.
The hosted scenario command compares complete native and TLC graphs and every
declared result. Expected failures change the verdict, not the model or checks.
Independent agreement still requires successful hosted evidence. The unavailable
pinned TLC JAR currently prevents that evidence.

## Positive reachability

`Reachable("AtLimit") { value == limit }` declares a positive goal beside the
algorithm. The predicate and its resolved bindings remain positive through
native generation. `matchedReachabilityProperties()` reports matching goals
in the current execution state.

`ReachabilityGraph.reachabilityResults` contains a result for every declared goal.
`.reached(snapshot)` identifies a witness. `trace(to:)` returns its complete
execution trace. `.unreachable` requires complete exploration without a match.
A state limit throws instead of producing an unreachable result. A match does
not stop graph capture or suppress safety checks.

Reachability checks include excluded candidates, as TLC invariant checks do.
A witness can end outside the constrained graph. Its state and trace remain
available without adding that state to the graph.

TLA+ export negates the predicate only at the final rendering boundary and
retains metadata that identifies the positive claim. The parity adapter converts
a finite TLC counterexample into a positive witness. It validates the complete
path and requires an endpoint that satisfies the native predicate. Different
valid witnesses can establish the same outcome. Complete graph comparison remains
independent of property outcomes.

Reference checks require an explicit property-kind match. Constraint-boundary
witness export remains unsupported and fails explicitly. Hosted TLC evidence
is still required to establish independent agreement.
