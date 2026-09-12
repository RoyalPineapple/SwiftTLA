# Compiler design

SwiftTLA is a Swift-native DSL for state machines. It generates native Swift
implementations, checks those same implementations, and exports equivalent TLA+
for independent TLC validation. It is not a Swift spelling of arbitrary raw TLA+.

```text
Typed Swift DSL
      ↓
Resolve and validate once
      ↓
Typed model
      ├── Native Swift generation
      │       ├── Application execution
      │       └── Swift model checking
      └── TLA+ export
              └── Separate TLC validation
```

## One semantic pipeline

`#spec`, scoped `Algorithm`, `scope.sharedVar`, process or procedure
`scope.localVar`, `Each`, and `Do` describe the model. Resolve lexical bindings,
types, control flow, and declarations once. Preserve that information in the
typed model consumed by both code generation and export. Backends must not
reconstruct types or independently reinterpret the source specification.

Application execution selects generated transitions. Swift model checking
explores all generated successors and evaluates generated properties. They use
the same Swift transition functions, including guards, simultaneous assignments,
choices, checked arithmetic, constraints, and failures. An expression interpreter
is not a second implementation of Swift model checking.

An exploration key includes the complete execution state, including control
locations and procedure storage. The application-facing `State` can omit those
implementation details; the generated `Snapshot` cannot. Equal application
projections alone do not establish equal execution states.

## Independent validation

TLC runs only in separate validation infrastructure. Applications, Swift model
checking, and ordinary Swift tests must not invoke it. Tests of the validation
protocol may use recorded data and process fixtures without executing TLC.

For each DSL model and finite configuration, derive native exploration, TLA+
export, state mappings, and canonical comparison data automatically. Compare
initial-state sets and complete labeled transition graphs, together with invariant
violations, deadlocks, and temporal-property results. Preserve fairness,
stuttering, and termination semantics. State counts alone are not equivalence.

Generate actionable mismatch traces. Timeouts, truncated exploration, unsupported
constructs, missing data, and decoding failures are failures or incomplete
results, never successful validation. Complete graph construction alone is not a
verdict about safety or temporal properties. Finite comparisons provide evidence
for the tested configurations, not a universal proof of compiler correctness.

## Corpus membership

The target is every TLC-marked family in the **Validated Examples** table of
[`tlaplus/Examples` at `ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10`](https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/README.md),
including applicable modules and TLC configurations within each family.
Membership comes from that pinned upstream source, never the Swift implementation
registry. “Other Examples” are excluded. At this pin, Einstein's Riddle, TLA+
Level Checking, and Condition-Based Consensus have no TLC model and are excluded.

There are 78 required families. Track three independent gaps: missing Swift
implementations, incomplete variants/configurations, and missing native/TLC
equivalence evidence. A source file, simplified port, or one passing configuration
does not establish whole-family coverage. Features required by the corpus are
implementation work; they do not justify removing families from the target.

## Current migration boundary

Generated machines expose their complete typed snapshots and all native
successors. `ReachabilityGraph` explores those successors and returns a complete
graph or throws; it does not issue a model-checking verdict.

The earlier `ModelChecker`, expression evaluator, and formal-call representation
remain in existing validation paths. They are migration work, not a parallel
architecture to preserve. Move property evaluation, temporal analysis, and
canonical export consumers onto the typed model and generated semantics, migrate
callers, then delete those execution paths. Additional representations must
justify why the existing pipeline cannot serve their purpose.
