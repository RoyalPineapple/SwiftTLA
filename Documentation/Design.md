# Compiler design

SwiftTLA is a compiler hosted in Swift. One source model becomes one immutable
compiled specification.

```text
typed Swift source
  → parse
  → source model
  → compile
  → CompiledSpecification
       ├→ private runtime and bounded exploration
       ├→ generated machine and Actor
       ├→ rendered TLA+ bundle
       └→ rendered PlusCal bundle for one authored Algorithm
```

## Source model

`#spec` and result builders create typed declarations. The source model holds
variables, actions, algorithms, procedures, properties, imports, instances,
and refinements.

An `Algorithm` uses scoped declarations. `scope.sharedVar` creates shared
state. `scope.localVar` creates process or procedure state. `Each`, `Do`,
`When`, `Assign`, `With`, `Choose`, `Goto`, and `Stop` create authored control
flow.

## Compilation

Compilation validates declarations, binds lexical names to private identities,
links imports and instances, and lowers algorithms into compiler-owned control
state and actions.

`CompiledLayout` assigns private IDs and state slots in canonical declaration
order. `CompiledLowerer` creates compiled expressions and semantics. A
successful `compile()` returns a complete `CompiledSpecification`.

`CompilationDescription` exposes source declarations in canonical order. It
includes variables, actions, procedures, control locations, properties,
refinements, imports, and compilation identity.

## Execution

The private runtime executes compiled action identities against slot-backed
state. `CompiledEvaluator` evaluates compiled expressions and values.
`ModelChecker` performs bounded reachable-state exploration.

`@TLAModel` derives generated `State`, `Action`, and `Transition` types from
the compiled specification. The generated value machine stores one complete
state and applies one typed action atomically. The generated `Actor` serializes
access to that value machine.

## Rendering and linking

Compilation owns module order, rendered names, configuration, ownership, and
provenance. `CompiledTLARenderer` prints the compiled declaration plan.
`AlgorithmPlusCalRenderer` prints the authored algorithm from its compiled
render plan.

`renderedTLAModuleBundle()` returns the linked TLA+ bundle.
`renderedPlusCalBundle()` returns PlusCal for a compilation with one authored
algorithm.

## Exact finite comparison

SwiftTLA exploration and TLC graph events produce the same canonical graph
model. `GraphComparison` compares complete initial states, states, labeled
edges with multiplicity, and outcomes.

TLC is an independent bounded oracle for each declared case. GitHub Actions
runs the exact comparison against the requested SwiftTLA commit.

## Ownership

| Fact | Owner |
| --- | --- |
| Authored declarations and scope | source model |
| Lexical identities | binding |
| Module closure | linking |
| IDs and state slots | compiled layout |
| Formal meaning | compiled specification |
| Application state and actions | generated machine |
| Text output | renderer |
| External behavior | TLC adapter |
| Finite equality | exact graph comparison |
