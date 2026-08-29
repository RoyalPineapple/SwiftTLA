# ``SwiftTLA``

Define a typed state-transition model in Swift. Compilation produces the
meaning used by the generated machine and rendered formal bundles.

## Overview

`SwiftTLA` contains the source language, compiler, private runtime, and formal
renderers. `SwiftTLAMacros` contains `@TLAModel`, which generates typed Swift
machines from `TLASpec` declarations.

Application code uses generated `State`, `Action`, `Transition`, machine, and
`Actor` types.

## Compile a source model

`TLASpec` is the typed source model. `compile()` validates declarations, binds
names, links modules, lowers algorithms, and returns one
`CompiledSpecification`.

```swift
let compilation = try Counter.spec.compile()
var machine = try Counter.makeMachine()
let transition = try machine.send(.advance)
```

`CompiledSpecification.description` exposes declarations and imports in
canonical order. `CompiledSpecification.identity` identifies the compiled
meaning used by generated code and formal outputs.

Compilation errors use `CompilationDiagnostic`. Each diagnostic identifies
the compiler stage, source path, expected fact, and actual fact.

## Render a linked bundle

The compiler resolves the module closure before it renders text.

```swift
let compilation = try Counter.spec.compile()
let bundle = compilation.renderedTLAModuleBundle()
let rootModule = bundle.root
let importedModules = bundle.imports
```

The rendered bundle contains the root module, imports, configuration,
ownership, and provenance. A compilation with one authored `Algorithm` also
provides a PlusCal bundle.

```swift
let plusCal = try compilation.renderedPlusCalBundle()
```

## Execute generated Swift

The generated machine is a Swift value. SwiftUI stores it directly in
`@State`. The generated `Actor` serializes access to the same value machine.

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
