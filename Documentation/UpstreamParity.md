# Upstream parity

SwiftTLA has two related but different TLC checks.

Legacy upstream parity is a diagnostic suite. It checks selected Swift ports
against their expected distinct-state counts and can run exported modules with
TLC. It is useful regression coverage, but equal counts do not prove equal
initial states, state values, action labels, edges, or outcomes.

Core graph conformance is the stronger, bounded relation for the cases in
`Verification/CoreConformance/cases.json`. It compares canonical initial
states, state bindings, and the complete labeled transition multiset from an
independent Swift BFS run and a pinned TLC run.

Run the legacy diagnostics with:

```sh
make parity
./scripts/validate_upstream_parity.sh
```

Run exact finite graph conformance with:

```sh
make core-conformance
```

Run the support-admission gate with:

```sh
make core-support-gate
```

Run the release qualification, including the temporal/symmetry and
public-workflow gates, with:

```sh
make ci-release-qualification
```

The release qualification creates fresh temporal/symmetry and public-workflow
admission evidence below `.build/`. Run `make core-conformance` and
`make core-support-gate` directly when refreshing core graph evidence.
Committed passing baselines are under `Verification/CoreConformance/baselines`.
The same-count edge-mismatch and violation fixtures are deliberate negative
controls; their expected failures show that the comparison does not accept
count parity as graph parity. The support gate defines the small current
admitted surface and retains a report for every run. See [Core graph
conformance](CoreGraphConformance.md) and [core support](CoreSupport.md) for
the pin, evidence, scope, and report rules.

Neither command establishes temporal/liveness/fairness equivalence, symmetry
reduction equivalence, or correctness outside the finite cases it executes.

## PlusCal porting inventory

The ports in `Sources/UpstreamParity/Examples/` use `#spec`, `Algorithm`,
`Each`, and labeled `Do` blocks when the upstream source contains PlusCal.
The remaining upstream PlusCal sources identify the next language work. This
is a source-driven roadmap: a port is added only when its bounded upstream
configuration and its required typed surface are both available.

| Upstream example | SwiftTLA can already express | Missing typed surface |
| --- | --- | --- |
| `KVsnap` | process families, function state, records, sequences, and non-empty finite subset choice | typed set-to-sequence enumeration, operation-log record comprehensions, and the external ClientCentric property interface |
| `EWD998PCal` | fair processes, `Either`, `When`, scoped choices, records | typed finite bags and bag-domain selection |
| `LeastCircularSubstring` | labeled loops, integer arithmetic, function updates | zero-indexed bounded sequences and modulo indexing |
| `Quicksort` | finite sequences, loops, scoped choices | constrained finite function choice and multi-binding `with` |
| `Slush` | records, unions, `Either`, loops | typed sets of record variants and filtered record comprehensions |
| `Sailfish` | process families, nested `With`, sets and tuples | typed filtered comprehensions, tuple/record relations, and multi-binding `with` |

`EWD687aPlusCal` uses language forms that are mostly already present
(`Either`, `When`, nested `With`, and records), but the repository does not
provide a matching bounded configuration for that PlusCal module. It is not a
parity-corpus candidate until one exists.

The immediate order is: typed set-to-sequence enumeration and record
comprehensions; typed bags; zero-indexed sequences; then multi-binding scoped
choice. Each addition must be used by a bounded source port and checked
through the parser/builder gate and TLC.

## Temporal and symmetry executable reference

The temporal and symmetry gate is a third, separate bounded check. Run it
locally with:

```sh
make temporal-symmetry-release-check
```

The gate reads the declared P3 cases, divergence ledger, and support surface
from `Verification/TemporalSymmetryConformance/`. It requires a current core
admission and writes a retained P3 admission report under
`.build/temporal-symmetry-support-gate/`.

Published TLA+ temporal and symmetry semantics are authoritative. TLC v1.8.0
at the declared commit is pinned executable-reference evidence. TLC source,
tests, and the graph bridge are white-box diagnostic evidence. They do not
create a hidden checker or oracle.

Each P3 case pins its TLC JAR, Java runtime, bridge source and binary, module,
configuration, arguments, and finite bound. A changed bridge requires new
pins and a fresh run. The gate rejects stale or mixed pin evidence.

The requested P3 entries are the declared three-state temporal cases and one
binary-valued symmetric collection at scopes 2, 3, and 4. The report alone
states which entries are admitted in a current run. It does not support
arbitrary scopes, combined temporal and symmetry reduction, multiple or
legacy symmetry declarations, nested member values, or unbounded formulas.

See [temporal and symmetry conformance](TemporalSymmetryConformance.md) for
the complete local command, exit classes, retained evidence, and diagnosis
steps.
