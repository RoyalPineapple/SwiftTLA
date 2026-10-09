# ``SwiftTLA``

Define a typed state-transition model in Swift. `@TLAModel` generates a Swift
machine and a TLA+ export from the same `#spec` declaration.

## Overview

`SwiftTLA` contains the source language, compiler, generated-machine support,
and formal renderers. `SwiftTLAMacros` contains `@TLAModel`.

Application code uses generated `State`, `Action`, `Transition`, machine, and
`Actor` types.

## Execute the generated machine

The generated machine runs the transitions that the model declares. It does
not compile the source model at runtime or use an expression interpreter.

```swift
var machine = try BoundedCounter.makeMachine()
let transition = try machine.send(.advance)
```

For a finite model, `ReachabilityGraph` checks the same generated transitions.
The native check does not need TLC.

```swift
let graph = try ReachabilityGraph(
    initialMachines: BoundedCounter.initialMachines(),
    maximumStates: 100
)
let violations = graph.safetyViolations
```

## Render the formal bundle

The generated export contains the TLA+ module and its configuration. It uses
the same model as the generated machine.

```swift
let rendered = try BoundedCounter.render()
let bundle = rendered.tlaBundle
let rootModule = bundle.root
let importedModules = bundle.imports
```

The bundle also contains the imports, ownership, and provenance. A model with
one authored `Algorithm` can provide a PlusCal bundle.

```swift
let plusCal = try rendered.plusCalBundle()
```

## Use the machine in an app

The generated machine is a Swift value. SwiftUI stores it in `@State`. The
generated `Actor` serializes access to the same machine.

Read <doc:GeneratedMachineSurface> for the generated API. Read
`Documentation/FiniteGraphComparison.md` for exact bounded TLC comparison.

## Topics

### Compilation and bundles

- ``CompiledSpecification``
- ``CompilationIdentity``
- ``CompilationDiagnostic``
- ``TLAModuleBundle``

### Generated machine

- ``GeneratedMachineError``
- <doc:GeneratedMachineSurface>
