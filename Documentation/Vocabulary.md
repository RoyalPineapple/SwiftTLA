# SwiftTLA vocabulary

SwiftTLA uses one term for each compiler concept.

| Term | Meaning |
| --- | --- |
| source model | Typed declarations produced by `#spec` and result builders. |
| declaration | One authored variable, action, property, import, procedure, or definition. |
| parse | Convert accepted SwiftSyntax into source declarations. |
| bind | Resolve a lexical name to a declaration identity. |
| link | Resolve imports, instances, substitutions, and the module closure. |
| compile | Validate, bind, link, and lower declarations without executing the model. |
| compiled specification | The immutable formal-core result of `compile()`, before native type resolution. |
| resolved program | Checked types, bindings, transitions, and properties shared by native generation and typed TLA+ export. |
| compilation description | The public declaration view of a compiled specification. |
| layout | The deterministic ordered allocation of private IDs and state slots. |
| compilation identity | The stable digest of one compiled specification. |
| slot | A private compiled-runtime position for one compiled variable. |
| compiled value | A private semantic value used by compiler expressions and formal-core operations. |
| formal value | A value in TLA+ or PlusCal. |
| compiled runtime | The existing formal-core interpreter used by compiler and parity fixtures. Generated machines do not use it. |
| machine | The generated typed Swift state machine. |
| model parameter | A typed, immutable declaration whose value belongs to a configuration, not mutable state. |
| configuration | Typed parameter bindings for one execution, exploration, or export. Configurations share the generated State and Action types. |
| validation scenario | A model-owned finite configuration and its expected property outcomes. |
| TLC configuration | Serialized constant bindings and check directives derived at the export boundary. |
| state | One complete assignment of model variables. |
| projection | A validated boundary view of formal state data. |
| action | A declared transition with typed parameters. |
| action ID | A private compiled identity used for execution. |
| transition | A generated action and its state before and after execution. |
| control location | A compiler-owned point in an algorithm or procedure. |
| rendered name | The TLA+ or PlusCal spelling of a declaration. |
| module closure | The resolved transitive modules for one root module. |
| bundle | Tool-ready files, configuration, ownership, and provenance. |
| render | Convert resolved expressions to output text. Generated export does not compile the model at runtime. |
| exploration | Traverse generated transitions. A resource limit cannot turn an incomplete traversal into a completed validation result. |
| canonical graph | Deterministic initial states, states, labeled edges, and outcome. |
| completed graph run | One canonical graph with explicit completion status. |
| graph comparison | Exact comparison of two completed graph runs. |
| TLC graph reader | The decoder from TLC events to a completed graph run. |
| Swift graph exporter | The conversion from Swift exploration to a completed graph run. |

## Compiler path

```text
source model → resolution and type checking → resolved program
                                               ├→ generated machine → execution and exploration
                                               └→ TLA+ module + configuration → rendered bundle
```

Source names serve authoring and diagnostics. Private identities and slots
serve execution. Rendered names serve TLA+, PlusCal, and TLC.

The formal-core source renderer remains available for imported modules and authored
PlusCal. Migration of those module closures to typed export is not complete.
