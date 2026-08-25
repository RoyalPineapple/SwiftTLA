# Upstream parity

Upstream parity keeps one canonical SwiftTLA source model for each selected
example. The canonical corpus owns its source model, module closure,
configuration, and provenance.

```text
canonical Swift source model → compile → rendered module bundle
                                      ├→ SwiftTLA exploration
                                      └→ TLC exploration
                                             ↓
                                    canonical graph comparison
```

## Canonical corpus

The corpus entries are in
[`Sources/UpstreamParity/CanonicalCorpus`](../Sources/UpstreamParity/CanonicalCorpus).
Each entry provides one typed Swift source model and its declared configuration.
Corpus export materializes the bundle from the compiled specification.

Upstream `.tla` and `.cfg` files are external formal input. The compiler
links them as named modules in a module closure. The closure preserves module
ownership, import edges, configuration, and provenance.

## Exact finite graph conformance

Core conformance runs a bounded SwiftTLA exploration and a pinned TLC run for
each case in
[`Verification/CoreConformance/cases.json`](../Verification/CoreConformance/cases.json).
Both explorations use the canonical graph schema.

The comparator evaluates canonical initial states, state bindings, labeled
edge multiplicities, and outcomes.

GitHub Actions retains the provenance, tool identity, raw TLC event stream,
canonical runs, and `core-decision.json` for each declared case.
The decision record references the exact run and graph chunks by digest. Its
reader reconstructs both graphs and repeats the comparison. The retained
canonical records locate the first difference. See
[Core graph conformance](CoreGraphConformance.md).

## Temporal and symmetry cases

Temporal and symmetry conformance uses cases in
[`Verification/TemporalSymmetryConformance`](../Verification/TemporalSymmetryConformance).
It retains the pinned tool identity, finite configuration, graph data, and
direct comparison. Every case must complete and match.

See [Temporal and symmetry conformance](TemporalSymmetryConformance.md).

## Evidence scope

TLC supplies independent evidence for the declared finite model and
configuration. The exact comparison supplies the admission fact for that
case. The evidence record names the source model, compilation identity,
configuration, module closure, tool identity, and retained graph data.
