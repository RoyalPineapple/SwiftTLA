# Production readiness

SwiftTLA qualifies one exact released commit. Evidence for an earlier commit does
not qualify later source changes.

Accepted source has one path:

```text
typed source model → resolved program
                       ├→ generated machine → execution and exploration
                       └→ generated export → formal bundles
```

Native generation and formal export must preserve the same resolved meaning.
Applications use generated typed state and actions. Swift exploration uses the
same generated transitions. Formal text exists at export and external-tool boundaries.

The supported application execution API contains one generated-machine route.
The `@TLAModel` expansion emits native initialization, transitions, and property checks.
Generated machines do not compile or interpret source declarations at runtime.
Remaining formal-core interpreter callers require migration or an explicit boundary justification.
Their presence does not establish a second application backend or completion of the DSL migration.

## Qualify a release commit

1. Merge the candidate commit to `main`.
2. Record the full 40-character SwiftTLA commit SHA.
3. Wait for the required `ci.yml` jobs to pass for that SHA.
4. Make sure that `canonical-corpus-<SwiftTLA SHA>` exists for that SHA.
5. Run independent DSL/native and upstream TLC parity against that SHA.
6. Run temporal and symmetry comparison against that SHA.
7. Run PlusCal admission against that SHA.
8. Record the run URLs, repository SHAs, and corpus artifact digest.

Run the SwiftTLA comparisons:

```sh
gh workflow run validation-pipeline.yml \
  --repo RoyalPineapple/SwiftTLA \
  --ref main \
  -f swift_tla_sha="$swift_tla_sha" \
  -f admission_mode=admission

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
- Every declared generated-machine scenario matches its independent generated-TLA TLC check; complete runs match full graphs.
- Every declared upstream configuration matches generated TLA through independent TLC checks; complete runs match full graphs.
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

Production readiness requires evidence for the accepted DSL contract and every
required upstream configuration. The coverage ledger retains missing implementations,
incomplete configurations, and incomplete comparisons.
Finite TLC comparisons supply evidence for their exact configurations, not for
untested configurations or the entire language.
