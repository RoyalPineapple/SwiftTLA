# SwiftTLA DSL patterns

## Build one source model

`#spec` and Swift result builders create typed source declarations. The
compiler receives that source model once.

```swift
@TLAModel
struct Counter {
    enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("Counter") {
            Algorithm("Counter", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Do(Step.advance) {
                    When(value < 1)
                    Assign(value, to: value + 1)
                }
                Invariant("Bounds") {
                    value >= 0 && value <= 1
                }
            })
        }
    }
}
```

Declare shared state with `scope.sharedVar` and process or procedure state with
the corresponding `scope.localVar`. Use a `CaseIterable` string enum for a
finite set of action labels. Use typed expressions in `When`, `Assign`, `With`,
`Choose`, and property builders.

## Choose builders by source scope

| Source scope | Builder | Source declaration |
| --- | --- | --- |
| Specification | `#spec` | variables, algorithms, properties, imports |
| Algorithm | `Algorithm` | shared variables, processes, procedures |
| Process family | `Each` | one finite process family |
| Atomic action | `Do` | guard, assignment, choice, and transfer statements |
| Procedure | `Procedure` | typed procedure declaration |
| Formal declaration | `FormalDefinition`, `Invariant`, `Refinement` | typed formal declaration |

The source builders preserve lexical nesting. Compilation binds each declared
name to a private identity. The runtime uses those identities and compiled
state slots.

## Compile before consuming the model

```swift
let compilation = try Counter.spec.compile()
let machine = try Counter.makeMachine()
let transition = try machine.send(.advance)
let bundle = compilation.renderedTLAModuleBundle()
```

`CompiledSpecification` is the single compiled input for local exploration,
generated Swift, direct TLA+, authored PlusCal for a single authored
`Algorithm`, and conformance evidence. Its description
exposes declarations, control locations, imports, and identity in canonical
order.

## Use typed generated APIs

Generated `State`, `Action`, and `Transition` form the normal application API.
The generated `Actor` supports shared execution. A generated action carries
the action type and argument types selected by the source model.

## Declare modules and refinement structurally

Use `Import` and `Instance` for TLA+ modules. Compilation links their complete
module closure. Direct TLA+ and available authored PlusCal bundles use that
closure. TLC invocations that consume compiled bundles stage those declared
files. Conformance fixtures remain independent external bundles.

Use `FormalDefinition` and `Invariant` for typed formal claims. Use
`Refinement` with a typed abstract model and state mapping. The local checker
evaluates mapped initial states and concrete edges against the abstract model.

## Verify finite behavior

Finite graph comparison explores compiled specifications with declared finite limits
and compares canonical SwiftTLA and TLC graphs for declared finite cases. The
exact comparison explains a mismatch from retained state and edge records.

## Own one concern per component

| Component | Concern |
| --- | --- |
| `TLASpec` | typed source model |
| `SpecParser` | SwiftSyntax input to source declarations |
| `CompiledLayout` | canonical IDs and slots |
| `CompiledEvaluator` | compiled expressions and values |
| `CompiledRuntime` | compiled state and action execution |
| `ModelChecker` | bounded reachable-state exploration |
| compilation and `@TLAModel` | generated Swift surface |
| `CompiledTLARenderer` | compiled expressions and declarations to TLA+ text |
| `TLCProcessAdapter` and `TLCGraphReader` | declared bundle execution and TLC event decoding |
| `CanonicalGraph` and `GraphComparison` | deterministic finite records and exact equality |
