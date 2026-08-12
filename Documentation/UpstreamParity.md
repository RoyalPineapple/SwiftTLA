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

Run all local required checks, including the conformance command, with:

```sh
make ci-local
```

The latter creates fresh conformance and admission evidence below `.build/`.
Committed passing baselines are under `Verification/CoreConformance/baselines`.
The same-count edge-mismatch and violation fixtures are deliberate negative
controls; their expected failures show that the comparison does not accept
count parity as graph parity. The support gate defines the small current
admitted surface and retains a report for every run. See [Core graph
conformance](CoreGraphConformance.md) and [core support](CoreSupport.md) for
the pin, evidence, scope, and report rules.

Neither command establishes temporal/liveness/fairness equivalence, symmetry
reduction equivalence, or correctness outside the finite cases it executes.

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
