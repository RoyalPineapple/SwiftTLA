# Production readiness

SwiftTLA qualifies one exact released commit. That commit owns the meaning of
every source model that its `compile()` accepts.

Accepted source has one path:

```text
source model
  → compile
  → CompiledSpecification
       ├→ generated machine
       ├→ compiled runtime
       └→ rendered bundles
```

Compilation validates formal meaning; native generation additionally checks
that the model has a supported Swift representation. Applications execute
generated typed state and actions directly. The compiled runtime executes the
formal model for verification. Formal text exists at rendering and external-tool
boundaries.

The supported application execution API contains one generated-machine route.
A successful compilation supplies every executable model fact to that route.
The `@TLAModel` expansion uses an underscored compiler-support ABI whose state
is private inside each generated machine.

## Check a candidate

The finite-graph and temporal/symmetry workflows accept an exact candidate SHA
with `admission_mode=candidate`. Run the workflow from the candidate branch
when validating workflow changes:

```sh
gh workflow run finite-graph.yml --ref "$candidate_branch" \
  -f swift_tla_sha="$candidate_sha" -f admission_mode=candidate

gh workflow run temporal-symmetry-conformance.yml --ref "$candidate_branch" \
  -f swift_tla_sha="$candidate_sha" -f admission_mode=candidate
```

Candidate artifacts include `candidate` in their names. Release admission runs
from `main` and requires the requested SHA to be an ancestor of `main`.
Scheduled runs and manual runs without an explicit mode use admission.

## Qualify a release commit

1. Merge the candidate commit to `main`.
2. Record the full 40-character SwiftTLA commit SHA.
3. Wait for the required `ci.yml` jobs to pass for that SHA.
4. Make sure that `canonical-corpus-<SwiftTLA SHA>` exists for that SHA.
5. Run finite graph comparison against that SHA.
6. Run temporal and symmetry comparison against that SHA.
7. Run PlusCal admission against that SHA.
8. Record the run URLs, repository SHAs, and corpus artifact digest.

Run the SwiftTLA comparisons:

```sh
gh workflow run finite-graph.yml \
  --repo RoyalPineapple/SwiftTLA \
  --ref main \
  -f swift_tla_sha="$swift_tla_sha"

gh workflow run temporal-symmetry-conformance.yml \
  --repo RoyalPineapple/SwiftTLA \
  --ref main \
  -f swift_tla_sha="$swift_tla_sha"
```

Run the PlusCal admission:

```sh
gh workflow run pluscal-oracle.yml \
  --repo RoyalPineapple/SwiftTLA-ValidationEvidence \
  --ref main \
  -f swifttla_ref="$swift_tla_sha" \
  -f admission_mode=admission
```

## Required results

- The public products build on each advertised Swift and Apple platform.
- The Swift test jobs pass, including the README and generated-machine fixtures.
- Canonical corpus export publishes the artifact for the exact SwiftTLA SHA.
- Every declared finite graph case completes and matches TLC exactly.
- Every declared temporal and symmetry case completes and matches TLC.
- PlusCal admission uses the corpus artifact for the exact merged SHA.
- Public documentation describes the generated API in that commit.

An incomplete, bounded, unavailable, or warning-only conformance result cannot
satisfy a release requirement.

## Release record

Record these values:

```text
SwiftTLA SHA:
SwiftTLA CI run:
canonical corpus artifact digest:
ValidationEvidence SHA:
finite graph run:
temporal and symmetry run:
PlusCal admission run:
```

The three comparison runs identify their requested SwiftTLA SHA. Their artifact
names contain the resolved SHA, run ID, and run attempt.

## Scope

Production readiness covers fidelity for the language accepted by `compile()`.
Bounded TLC comparison supplies independent evidence for each declared finite
case.
