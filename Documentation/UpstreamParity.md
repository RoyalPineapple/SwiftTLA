# Upstream parity

Upstream parity is repository validation tooling. It keeps one canonical
SwiftTLA source model for each selected example. Each corpus entry owns that
source model and its direct-TLA and authored-PlusCal configurations.
Compilation resolves the module closure and records compiled bundle provenance.

```text
Swift source model → compile → SwiftTLA exploration → canonical graph

pinned TLA+ fixture → TLC exploration → canonical graph

                         exact graph comparison
```

## Canonical corpus

The corpus entries are in
[`Sources/UpstreamParity/CanonicalCorpus`](../Sources/UpstreamParity/CanonicalCorpus).
Each entry provides one typed Swift source model and its two declared configurations.
Corpus export materializes the bundle from the compiled specification.

Typed `Import` and `Instance` declarations are linked during compilation and
become the compiled specification's module closure.

Pinned `.tla` and `.cfg` fixtures are a separate TLC boundary. The TLC adapter
reads the root, configuration, and import files declared by the case, validates
that external bundle, and stages exactly those files. These fixtures do not
become part of the Swift compilation.

## Exact finite graph conformance

Finite graph comparison runs a bounded SwiftTLA exploration and a pinned TLC run for
each case in
[`Verification/FiniteGraph/cases.json`](../Verification/FiniteGraph/cases.json).
SwiftTLA explores the compiled Swift source model. TLC explores the independent
TLA+ fixture and configuration declared by the manifest. Both explorations use
the canonical graph schema.

The comparator evaluates canonical initial states, state bindings, labeled
edge multiplicities, and outcomes.

GitHub Actions retains the tool invocation, raw TLC event stream, complete
`swift-graph.jsonl` and `tlc-graph.jsonl` streams, and one `comparison.json`
for each declared case. Each graph stream ends with its outcome and declared
record counts, and retains any diagnostics or counterexample traces. Missing,
truncated, failed, and bounded streams cannot match.
The comparison record reports exact equality or the first structured
difference. See
[Finite graph comparison](FiniteGraphComparison.md).

## Temporal and symmetry cases

Temporal and symmetry conformance uses cases in
[`Verification/TemporalSymmetryConformance`](../Verification/TemporalSymmetryConformance).
It retains the pinned tool identity, finite configuration, graph data, and
direct comparison. Every case must complete and match.

Temporal cases pair a typed Swift model with a pinned external TLA+ input.
Symmetry cases render unreduced and reduced TLC bundles from one compiled
specification.

See [Temporal and symmetry conformance](TemporalSymmetryConformance.md).

## Evidence scope

TLC supplies independent evidence for the declared finite model and
configuration. The exact comparison determines whether that case passes. The
declared case identifies the Swift source model and finite configuration. The
retained TLC invocation identifies the independent root module, configuration,
declared imports, and pinned tool. The graph streams retain the compared behavior.
