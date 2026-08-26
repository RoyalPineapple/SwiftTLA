# SwiftTLA vocabulary

SwiftTLA uses one preferred term for each compiler concept. Source code,
documentation, diagnostics, and reviews use these terms.

| Term | Meaning | Do not use for this concept |
| --- | --- | --- |
| source model | Typed declarations produced by `#spec` and result builders. | spec, machine, runtime |
| declaration | One authored variable, action, property, import, procedure, or definition. | descriptor, entry, component |
| compile | Validate, bind, link, lower, allocate IDs, and create a compiled specification. | build, prepare, resolve |
| compiled specification | The immutable product of `compile()`. | compiled model, runtime spec |
| binding | Resolve a name in lexical scope to a declaration identity. | linking, lookup |
| linking | Resolve module imports, instances, substitutions, and the module closure. | binding, staging |
| layout | The ordered allocation of compiler-owned IDs and slots. | schema, map, registry |
| identity | The stable digest for one compiled declaration plan and configuration. | hash, fingerprint, ID |
| configuration | The declared finite exploration and tool settings for one check. | options, setup |
| slot | A private runtime position for one compiled variable. | index, key |
| compiled value | A private recursive value used by the runtime. | formal value, state value |
| formal value | A value in TLA+ or PlusCal. | compiled value |
| runtime | The private evaluator for compiled IDs, slots, and values. | machine, checker |
| machine | The generated typed Swift state machine. | runtime |
| state | One complete assignment of model variables. | projection, snapshot |
| projection | A validated boundary view of state data. | state map, snapshot |
| action | An authored transition declaration. | invocation, transition |
| action call | An action with concrete formal argument values. | action ID |
| action ID | A private compiled identity that executes an action. | action name |
| control location | A compiler-owned algorithm or procedure position. | label, pc |
| source location | A position in author source used by diagnostics and inspection. | source name, identity |
| rendered name | Text emitted for a declaration or control location. | identity |
| program counter (`pc`) | State data that holds current control locations. | stack |
| procedure stack | State data that holds return control locations and procedure data. | pc |
| module | One TLA+ source unit. | bundle, closure |
| module closure | The resolved transitive modules for one root module. | directory |
| bundle | Rendered files, configuration, provenance, and ownership for a tool. | module closure |
| generated | Swift API emitted from a compiled specification for application code. | compiled, rendered |
| render | Convert compiled declarations to TLA+ or PlusCal text. | compile, export |
| serialize | Encode boundary data such as JSON, graph records, or manifests. | render |
| exploration | A bounded traversal of a compiled machine graph. | checking |
| finite graph case | One declared SwiftTLA and TLC comparison case. | core case, conformance case |
| finite graph manifest | The source-controlled list of finite graph cases. | cases registry |
| finite graph check | One execution of a declared finite graph case. | runner, gate |
| completed graph run | One complete or explicitly incomplete explored graph and its outcome. | canonical run, evidence |
| canonical graph | Deterministically ordered states and labeled edges. | evidence |
| graph comparison | The exact comparison of two completed graph runs. | conformance result |
| graph difference | One exact mismatch in observable names, initial states, states, edges, or outcome. | diagnostic result |
| TLC graph reader | The boundary decoder from TLC graph events to a completed graph run. | parser, adapter |
| Swift graph exporter | The boundary conversion from Swift exploration to a completed graph run. | adapter |
| rendered action | The declared correspondence between one source action call and its rendered TLA+ action name. | action normalization |
| evidence | Retained inputs, commands, outputs, and graphs from a check. | result |
| conformance | An exact SwiftTLA and TLC graph comparison for one finite case. | evidence |

## Compiler path

Builders create the source model. Compilation owns its meaning after that
point. Runtime, generated machine, and renderer consume the compiled
specification.

```text
source model → compiled specification → runtime / generated machine / rendered bundle
```

Source names belong to authoring and diagnostics. Compiled IDs and slots
belong to runtime execution. Rendered names belong to external text.

## Review rule

Use a preferred term from this document when it names the layer and job.
Add a term only when the compiler needs a distinct concept.
