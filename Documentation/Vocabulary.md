# SwiftTLA vocabulary

SwiftTLA uses one term for each compiler concept.

| Term | Meaning |
| --- | --- |
| source model | Typed declarations produced by `#spec` and result builders. |
| declaration | One authored variable, action, property, import, procedure, or definition. |
| parse | Convert accepted SwiftSyntax into source declarations. |
| bind | Resolve a lexical name to a declaration identity. |
| link | Resolve imports, instances, substitutions, and the module closure. |
| compile | Validate, bind, link, lower, allocate private identities, render TLA+/PlusCal text, assemble formal bundles, and publish a compiled specification. |
| compiled specification | The immutable product of `compile()`. |
| compilation description | The public declaration view of a compiled specification. |
| layout | The deterministic ordered allocation of private IDs and state slots. |
| compilation identity | The stable digest of one compiled specification. |
| slot | A private compiled-runtime position for one compiled variable. |
| compiled value | A private recursive value used by the compiled runtime. |
| formal value | A value in TLA+ or PlusCal. |
| compiled runtime | Private execution over compiled IDs, slots, expressions, states, and values. |
| machine | The generated typed Swift state machine. |
| state | One complete assignment of model variables. |
| projection | A validated boundary view of formal state data. |
| action | A declared transition with typed parameters. |
| action ID | A private compiled identity used for execution. |
| transition | A generated action and its state before and after execution. |
| control location | A compiler-owned point in an algorithm or procedure. |
| rendered name | The TLA+ or PlusCal spelling of a declaration. |
| module closure | The resolved transitive modules for one root module. |
| bundle | Tool-ready files, configuration, ownership, and provenance. |
| render | Convert compiled declarations to TLA+ or PlusCal text. |
| exploration | A bounded traversal of reachable compiled states. |
| canonical graph | Deterministic initial states, states, labeled edges, and outcome. |
| completed graph run | One canonical graph with explicit completion status. |
| graph comparison | Exact comparison of two completed graph runs. |
| TLC graph reader | The decoder from TLC events to a completed graph run. |
| Swift graph exporter | The conversion from Swift exploration to a completed graph run. |

## Compiler path

```text
source model → compile → compiled specification
                          ├→ compiled runtime
                          ├→ generated machine
                          └→ rendered bundle
```

Source names serve authoring and diagnostics. Private identities and slots
serve execution. Rendered names serve TLA+, PlusCal, and TLC.
