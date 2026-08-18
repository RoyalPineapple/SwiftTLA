# Generated machine surface

`@TLAModel` generates a typed machine from a `TLASpec`. The generated public
surface is the application boundary for that model.

## Generated types

Each model with declared variables generates these value types:

- `State`: one typed property for each declared variable.
- `Variables`: an enum of the declared variable names.
- `Actions`: an enum of the declared action names when the model has actions.
- `ActionLabel`: a typed action identity and typed parameters.
- `TransitionResult`: the typed action, state before execution, and state after
  execution.

All generated value types are `Sendable`. A model state is value data. It does
not store an arbitrary reference type.

## One machine plan

The macro first compiles the model. It then creates one `MachineSurfacePlan`
from that compilation and Swift-only type facts. The plan supplies the typed
`State`, `Variables`, `ActionLabel`, action descriptors, and
`GeneratedMachineMetadata`.

The plan does not contain a second action or invariant tree. The canonical
`TLASpec` remains the only formal meaning. This prevents a generated label or
state field from silently describing a different machine.

## Execute an action

Use `apply(_:)` on a canonical generated model. Use `state` and the typed
result values after execution.

```swift
var machine = BoundedCounter()
let result = try machine.apply(.advance)

assert(result.action == .advance)
assert(result.before.value == 0)
assert(result.after.value == 1)
assert(machine.state.value == 1)
```

`apply(_:)` throws `GeneratedMachineError` when the action is not available.
The machine retains its previous state when that error occurs.

## Inspect a machine

`machineObservation()` returns a ``TLAMachineObservation``. Its `state` is a
``TLAStateProjectionResult``. Call `requireProjection()` when a formal-tooling
integration needs a guarded projection. Application code normally reads the
generated typed `state` property instead.

`TLAActionInvocation` is the formal runtime representation of an action. It is
useful at protocol boundaries. Convert between it and a generated
`ActionLabel` with `toInvocation()` and `init?(invocation:)`.

## Actors and observables

Nested `@TLAActor` and `@TLAObservable` declarations adapt one canonical model
type. They expose that model's `State`, `Variables`, `ActionLabel`, and
`TransitionResult` through type aliases.

An actor reads `state()` across its isolation boundary. A nested observable is
main-actor isolated. It publishes typed `on<Action>` callbacks after a
successful transition commits.

```swift
let actor = CounterHost.Actor()
let result = try await actor.execute(CounterHost.Actor.ActionLabel.advance.toInvocation())
assert(result.after.value == 1)
```

## Verification helpers

Generated models provide `verifySpec()` (which returns the explored-state count), `transitionMatrix()`,
`verifyTransitions()`, and `verifyInvariants()` for their declared finite
model. These helpers use the bounded checker and the model's
`verificationStateLimit` (default: `100_000`). They do not prove behavior that
is outside the declared bounds or outside the supported SwiftTLA surface.

For a narrative guide, compiled examples, and evidence limits, read
`Documentation/GeneratedMachines.md` in the repository.

## Verify the generated contract

Generated models provide `verifyGeneratedMachineContract()`. The method checks
the plan identity, metadata, action-label round trips, state projections, and
the bounded initial states and transitions.

```swift
let report = Counter.verifyGeneratedMachineContract()

switch report.status {
case .exact:
    break
case .difference:
    print(report.diagnostic ?? "Generated-machine contract differs.")
case .unavailable:
    print(report.diagnostic ?? "Generated-machine evaluation is unavailable.")
}
```

`difference` means that the generated surface disagreed with the compiled
formal machine. Read the diagnostic and correct the model or generator before
you use the result. `unavailable` means that bounded evaluation did not finish
safely. Increase no bound until you first inspect the diagnostic and its
configured limit.

The verifier checks only the declared finite graph up to
`verificationStateLimit`. An `exact` result is not a proof of larger state
spaces, other generated models, or unsupported language constructs.

## Evidence status

Generated-machine contract evidence is diagnostic-only. The aggregate Public
Workflow report can record `candidateEvidence` when the checked-in GitHub
workflow runs its exact fixture. That aggregate status does not admit general
generated-machine support. See `Documentation/PublicWorkflowConformance.md`.
