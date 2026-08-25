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
            Algorithm("Counter") {
                let value = SharedVar("value", initial: 0)
                Do(Step.advance) {
                    When(value < 1)
                    Assign(value, to: value + 1)
                }
                Invariant("Bounds") {
                    value >= 0 && value <= 1
                }
            }
        }
    }
}
```

Use a named `SharedVar` or `LocalVar` declaration. Use a `CaseIterable` string
enum for a finite set of action labels. Use typed expressions in `When`,
`Assign`, `With`, `Choose`, and property builders.

## Choose builders by source scope

| Source scope | Builder | Source declaration |
| --- | --- | --- |
| Specification | `#spec` | variables, algorithms, properties, imports |
| Algorithm | `Algorithm` | shared variables, processes, procedures |
| Process family | `Each` | one finite process family |
| Atomic action | `Do` | guard, assignment, choice, and transfer statements |
| Procedure | `Procedure` | typed procedure declaration |
| Formal declaration | `FormalDefinition`, `Invariant`, `Theorem`, `Refinement` | typed formal declaration |

The source builders preserve lexical nesting. Compilation binds each declared
name to a private identity. The runtime uses those identities and compiled
state slots.

## Compile before consuming the model

```swift
let compilation = try Counter.spec.compile()
let machine = try Counter.makeMachine()
let transition = try machine.send(.advance)
let bundle = try compilation.renderedTLAModuleBundle()
```

`CompiledSpecification` is the source for local exploration, generated Swift,
direct TLA+, authored PlusCal, and conformance evidence. Its description
exposes declarations, control locations, imports, and identity in canonical
order.

## Use typed generated APIs

Generated `State`, `Action`, and `Transition` form the normal application API.
The generated `Actor` supports shared execution. A generated action carries
the action type and argument types selected by the source model.

## Declare modules and refinement structurally

Use `Import` and `Instance` for TLA+ modules. Compilation links their complete
module closure. Direct TLA+, PlusCal, and TLC staging use the same closure.

Use `FormalDefinition` and `Invariant` for typed formal claims. Use
`Refinement` with a typed abstract model and state mapping. The local checker
evaluates mapped initial states and concrete edges against the abstract model.

## Verify finite behavior

Core conformance explores compiled specifications with declared finite limits
and compares canonical SwiftTLA and TLC graphs for declared finite cases. The
exact comparison explains a mismatch; the graph receipt identifies the
completed exploration.

## Own one concern per component

| Component | Concern |
| --- | --- |
| `TLASpec` | typed source model |
| `SpecParser` | SwiftSyntax input to source declarations |
| `CompiledLayout` | canonical IDs and slots |
| `CompiledEvaluator` | compiled expressions and values |
| `CompiledRuntime` | compiled state and action execution |
| private runtime explorer | finite graph exploration |
| compilation and macros | generated Swift surface |
| `TLASpec+PrettyPrint` | compiled TLA+ declaration plan |
| TLC adapter | declared bundle staging and event parsing |
| canonical graph | exact finite conformance records |
