# SwiftTLA language design

SwiftTLA is a compiler hosted in Swift. Typed Swift declarations create one
source model. Compilation creates one immutable compiled specification.

```text
typed Swift source → source model → compile → compiled specification
                                            ├→ generated Swift machine
                                            ├→ private runtime and exploration
                                            └→ rendered TLA+ and PlusCal bundles
```

The compiled specification carries the model meaning through every local
output. It owns the layout, declaration identities, module closure, generated
machine plan, diagnostics, and rendered-bundle plans.

## Author a model

Application models use `#spec` and PlusCal-shaped builders. A builder creates
an authored declaration. It does not allocate a runtime slot or render text.

```swift
@TLAModel
struct Counter {
    enum Step: String, PlusCalLabel, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("Counter") {
            Algorithm("Counter") {
                let count = SharedVar("count", initial: 0)
                Do(Step.advance) {
                    When(count < 1)
                    Assign(count, to: count + 1)
                }
                Invariant("Bounds") {
                    count >= 0 && count <= 1
                }
            }
        }
    }
}
```

`Algorithm`, `Each`, `Procedure`, `Do`, `When`, `Assign`, `With`, `Choose`,
`Goto`, and `Stop` create the source model. `FormalDefinition`, `Invariant`,
`Theorem`, `Import`, `Instance`, and `Refinement` create typed formal
declarations in the same model.

Direct TLA+ builders serve imported formal modules and parity fixtures. They
also compile into a `CompiledSpecification`.

## Compile a model

Compilation validates declarations, binds lexical names, links modules,
lowers algorithms, and assigns private IDs and slots in canonical declaration
order.

```swift
let compilation = try Counter.spec.compile()
let description = compilation.description
```

`CompilationDescription` exposes the stable author-facing declaration order:
variables, actions, procedures, control locations, imports, and compilation
identity. Private runtime IDs and slots do not cross this API boundary.

Compilation throws `CompilationDiagnostic` when the source model has an
invalid declaration, scope, import, instance, or required capability. A
successful `CompiledSpecification` is complete for its declared model.

## Execute generated Swift

`@TLAModel` generates the application-facing API. Application code uses
typed state and typed action labels.

```swift
var machine = try Counter.makeMachine()
let transition = try machine.apply(.advance)
let state = transition.after
```

The generated machine converts an `ActionLabel` to a private compiled action
request. The private runtime executes compiled action identities and
slot-backed state. Application code does not use action names, runtime IDs,
slots, or formal state maps.

Generated `Live`, `@TLAActor`, and `@TLAObservable` APIs use the same typed
state and action labels. See [Generated Machines](GeneratedMachines.md) and
[Live Machines](LiveMachines.md).

## Render formal bundles

The compiled specification renders direct TLA+ and authored PlusCal bundles.

```swift
let tla = try compilation.renderedTLAModuleBundle()
let plusCal = try compilation.renderedPlusCalBundle()
```

Compilation resolves the module closure before rendering. A rendered bundle
contains the root module, transitive imports, configuration, and provenance.
The renderer prints the compiled declaration plan.

## Explore and compare finite behavior

The conformance harness explores the compiled specification with a declared
finite exploration configuration. The runtime evaluates compiled expressions,
values, state slots, and action identities.

Core conformance runs SwiftTLA exploration and TLC against the same rendered
bundle. Both sides produce a canonical graph. Exact graph comparison decides
the declared finite case. A graph receipt identifies a completed exploration;
the retained canonical records provide the difference explanation.

See [Core graph conformance](CoreGraphConformance.md) and
[Upstream parity](UpstreamParity.md).

## Inspect language capabilities

`LanguageCapabilityLedger` records one capability for every
`DeclaredLanguageConstruct`. Each record states whether source decoding,
result-builder construction, compilation, TLA+ rendering, PlusCal rendering,
execution, and bounded conformance are supported.

```swift
let capability = LanguageCapabilityLedger.capability(for: .procedure)
let capabilities = LanguageCapabilityLedger.all
```

The parser and result builders use this ledger before compilation publishes a
compiled specification. `LanguageCapabilityDiagnostic` identifies the
construct, operation, source path, expected boundary, actual use, and next
action. Capability validation also visits declarations inside processes and
procedures. If the required capability is unsupported, compilation returns no
compiled specification.

Refinement checking evaluates a typed concrete model, typed abstract model,
and typed state mapping. It checks mapped initial states and concrete edges,
including abstract stuttering.

## Ownership

| Concern | Owner |
| --- | --- |
| Authored structure | `#spec` and result builders |
| Name binding and module linking | compilation |
| IDs and slots | `CompiledLayout` |
| Runtime evaluation | private compiled runtime and evaluator |
| Generated Swift surface | compilation and macros |
| TLA+ and PlusCal text | renderers |
| TLC staging and event parsing | TLC adapter |
| Graph comparison and evidence | canonical graph and conformance components |

Each owner carries structured data to the next phase. Text appears at source,
rendering, TLC, diagnostics, and serialized-evidence boundaries.
