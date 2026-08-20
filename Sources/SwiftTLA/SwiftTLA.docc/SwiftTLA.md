# ``SwiftTLA``

Define a finite behavioral model once. Then inspect, execute, and verify the
same model from Swift.

## Overview

`SwiftTLA` contains the formal value model, parser support, checker, runtime,
and guarded application boundary. The `SwiftTLAMacros` module contains the
macros that generate typed machines from a `TLASpec` declaration.

Application code reads generated `State`, `ActionLabel`, and
`TransitionResult` values. It does not read a raw formal state map.

## Compile before formal work

`TLASpec` is the one formal meaning of a supported model. Compile it before
you run the checker, create a runtime, or export TLA+ text.

```swift
let compilation = try Counter.spec.compile()
let checker = ModelChecker(compilation: compilation)
let runtime = SpecRuntime(compilation: compilation)
```

`CompiledSpecification` contains the canonical `TLASpec`, its
`FormalModuleClosure`, and a stable `CompilationIdentity`. The closure records
the root module, every required import or instance, the owner, and the path
that requires each module. It contains no unrelated modules.

Compilation can throw `CompilationDiagnostic`. The diagnostic identifies the
stage, code, source path, expected value, actual value, and next safe action.
Fix that source relationship before you compile again. Do not ignore the
diagnostic and construct a checker or renderer from uncompiled input.

## Materialize a linked bundle

Compile first. Then materialize the validated bundle from that compilation.

```swift
let compilation = try Counter.spec.compile()
try compilation.materializeModuleBundle(to: outputDirectory)
```

`TLAModuleBundle` is source-owned input for a formal tool. The compiler links
imports and instances before rendering, checks the rendered closure, writes it
to an isolated sibling staging directory, and publishes it with one rename.
A structural, rendering, I/O, or rename failure does not present a partial
destination as a valid compiler result. Inspect the diagnostic, correct the
named source relationship or destination, and compile again.

If a model has `Algorithm` source, its authored PlusCal export is also
throwing:

```swift
let bundle = try compilation.renderedPlusCalBundle()
```

`AlgorithmPlusCalRenderDiagnostic` identifies an Algorithm node that has no
source-faithful PlusCal spelling. Change that model construct. Do not replace
the failed node with text that changes the model's meaning.

## Compiler and evidence limits

Compilation produces an executable formal model. It does not prove every
possible TLA+ module or every behavior outside the configured finite bounds.
External comparison is a separate evidence step. Read
<doc:GeneratedMachineSurface> for the generated-machine contract and
`Documentation/PublicWorkflowConformance.md` for evidence status meanings.

## Topics

### Compilation and bundles

- ``CompiledSpecification``
- ``CompilationIdentity``
- ``CompilationDiagnostic``
- ``FormalModuleClosure``
- ``TLAModuleBundle``
- ``TLAModuleBundleIntegrityError``

### State boundaries

- ``TLAStateProjection``
- ``TLAStateProjectionResult``
- ``TLAStateProjectionDiagnostic``
- ``TLAMachineObservation``
- ``TLAMachineAvailabilityDiagnostic``

### Live machines

- ``TLALiveMachineOwner``
- ``TLALiveMachine``
- ``TLALiveMachineIdentity``
- ``TLALiveMachineSnapshot``
- ``TLALiveActionOutcome``
- ``TLALiveMachineObservationSubscription``
- ``TLALiveMachineObservationEvent``
- ``GeneratedLiveMachine``
- ``TLALiveMachineAdapterBinding``

### Runtime action identity

- ``TLAActionInvocation``
- ``GeneratedMachineError``

### Generated-machine reference

- <doc:GeneratedMachineSurface>
