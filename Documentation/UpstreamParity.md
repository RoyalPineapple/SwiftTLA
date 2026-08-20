# Upstream parity

SwiftTLA has two related but different TLC checks.

The parity corpus ports keep regression coverage through their in-process
tests: each port checks its expected distinct-state count and exported module
shape. Equal counts do not prove equal initial states, state values, action
labels, edges, or outcomes.

Core graph conformance is the stronger, bounded relation for the cases in
`Verification/CoreConformance/cases.json`. It compares canonical initial
states, state bindings, and the complete labeled transition multiset from an
independent Swift BFS run and a pinned TLC run.

GitHub Actions runs exact finite graph conformance, support admission, and
release qualification. It creates fresh temporal/symmetry and public-workflow
admission evidence below `.build/`. Local broad conformance commands require
explicit authorization; a local result is diagnostic-only.
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
| `KVsnap` | process families, function state, records, sequences, non-empty finite subset choice, local `LET … IN` operators, and real module instances | higher-order formal operator parameters and application; formal lambdas; standard `FoldFunction`; and a typed injective set-to-sequence choice |
| `EWD998PCal` | fair processes, `Either`, `When`, scoped choices, records | typed finite bags and bag-domain selection |
| `LeastCircularSubstring` | labeled loops, integer arithmetic, function updates, zero-based bounded sequences, modulo indexing, and bundled imported recursive operators | no current language dependency; it is a module-bundle conformance case |
| `TokenRing` | finite function state, parameterized actions, modulo, weak fairness, and `<>[]` properties | macro-side typed function-space preservation and an ordered finite-domain slice for the published `UniqueToken` property |
| `Quicksort` | finite sequences, loops, scoped choices | constrained finite function choice and multi-binding `with` |
| `Slush` | records, unions, `Either`, loops | typed sets of record variants and filtered record comprehensions |
| `Sailfish` | process families, nested `With`, sets and tuples | typed filtered comprehensions, tuple/record relations, and multi-binding `with` |

`EWD687aPlusCal` uses language forms that are mostly already present
(`Either`, `When`, nested `With`, and records), but the repository does not
provide a matching bounded configuration for that PlusCal module. It is not a
parity-corpus candidate until one exists.

The dependency order is deliberate. `KVsnap` is three real modules:
`Util` provides general operators, `ClientCentric` imports `Util`, and
`KVsnap` creates an instance of `ClientCentric`. The next implementation
trunk is therefore higher-order operator application and formal lambdas.
That unlocks `FoldFunction`, then `Util`, then `ClientCentric`, and only then
the `KVsnap` consumer. The exporter must write all three `.tla` files beside
the root module so TLC checks those imports and the named instance instead of
a flattened approximation.

After that chain, the next independent trunks are typed bags, constrained
function choice, and multi-binding scoped choice. Each addition must be used
by a bounded source port, pass the parser/builder fidelity gate, and run TLC
against its emitted module bundle.

## Temporal and symmetry executable reference

The hosted temporal and symmetry gate is a third, separate bounded check. It
reads the declared P3 cases, divergence ledger, and support surface from
`Verification/TemporalSymmetryConformance/`. It requires a current core
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
arbitrary scopes, combined temporal and symmetry reduction, multiple
collections, direct symmetry declarations, nested member values, or unbounded
formulas.

See [temporal and symmetry conformance](TemporalSymmetryConformance.md) for
the complete local command, exit classes, retained evidence, and diagnosis
steps.
