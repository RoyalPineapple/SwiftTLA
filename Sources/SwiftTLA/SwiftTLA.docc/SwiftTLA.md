# ``SwiftTLA``

Define a finite behavioral model once. Then inspect, execute, and verify the
same model from Swift.

## Overview

`SwiftTLA` contains the formal value model, parser support, compiler, runtime,
and guarded application boundary. The `SwiftTLAMacros` module contains the
macros that generate typed machines from a `TLASpec` declaration.

Application code reads generated `State`, `ActionLabel`, and
`TransitionResult` values. It does not read a raw formal state map.

## Compile the source model

`TLASpec` is the typed source model. `compile()` validates, binds, links,
lowers, and returns one immutable `CompiledSpecification`. Generated machines,
bounded exploration, and rendered bundles use this compiled meaning.

```swift
let compilation = try Counter.spec.compile()
var machine = try Counter.makeMachine()
try machine.apply(.advance)
```

`CompiledSpecification` contains the compiled declaration plan, its
`FormalModuleClosure`, and a stable `CompilationIdentity`. The closure records
the root module, every required import or instance, its owner, and the path
that requires each module.

Compilation can throw `CompilationDiagnostic`. The diagnostic identifies the
stage, code, source path, expected value, actual value, and next safe action.
Fix that source relationship before you compile again.

## Inspect language support

`LanguageCapabilityLedger` records the support dimensions for each
`DeclaredLanguageConstruct`.

```swift
let procedure = LanguageCapabilityLedger.capability(for: .procedure)
let capabilities = LanguageCapabilityLedger.all
```

The parser and result builders use the same ledger. If a required dimension
is unsupported, compilation throws `LanguageCapabilityDiagnostic`. The
diagnostic identifies the construct, operation, source path, and required
action. No compiled specification is available after this failure.

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

### Language capabilities

- ``DeclaredLanguageConstruct``
- ``LanguageCapability``
- ``LanguageCapabilityLedger``
- ``LanguageCapabilityDiagnostic``

### Generated-machine errors

- ``GeneratedMachineError``

### Generated-machine reference

- <doc:GeneratedMachineSurface>
