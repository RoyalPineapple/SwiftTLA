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
