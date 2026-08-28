# Production readiness

SwiftTLA is production ready when a released commit can own the behavior of an
application within the language accepted by `compile()`.

Accepted source has one path:

```text
typed Swift source
  → compile
  → compiled specification
  → generated machine / private runtime / rendered bundles
```

Compilation rejects a declaration when SwiftTLA cannot preserve its meaning
through every supported output. There is no text-only executable declaration,
alternate evaluator, compatibility runtime, or application-facing string-keyed
state path.

## Release requirements

A release commit is ready when all of these facts hold for that exact commit:

1. Every public product builds on each advertised Swift and Apple platform
   configuration.
2. The complete Swift test job passes, including the README workflow fixtures.
3. Canonical corpus export succeeds and publishes
   `canonical-corpus-<SwiftTLA SHA>`.
4. Every declared finite graph case completes and its SwiftTLA and TLC initial
   states, states, and labeled edge multisets match exactly.
5. Every declared temporal and symmetry case completes and matches its pinned
   TLC reference.
6. PlusCal candidate validation runs in admission mode against the canonical
   corpus artifact for the merged SwiftTLA SHA.
7. The generated machine, actor, and SwiftUI surfaces use the same generated
   value machine through typed state and action APIs.
8. The README and architecture documentation describe the shipped API and
   compiler path.

An incomplete, bounded, unavailable, or warning-only conformance run does not
satisfy a release requirement.

Finite graph and temporal-symmetry qualification accept the exact merged
SwiftTLA SHA:

```sh
gh workflow run finite-graph.yml --ref main -f swift_tla_sha="$swift_tla_sha"
gh workflow run temporal-symmetry-conformance.yml --ref main -f swift_tla_sha="$swift_tla_sha"
```

Scheduled runs qualify the `main` revision that triggered the workflow. Each
retained artifact name contains the resolved SwiftTLA SHA, run ID, and attempt.

## Readiness record

The release record contains only the identities needed to reproduce the
decision:

```text
SwiftTLA SHA:
SwiftTLA CI run:
canonical corpus artifact digest:
ValidationEvidence SHA:
finite graph admission run:
temporal and symmetry admission run:
PlusCal candidate admission run:
```

GitHub Actions retains commands, logs, runner metadata, and uploaded evidence.
The readiness record links to those authoritative runs instead of duplicating
their provenance.

## Scope of the claim

Production readiness is not a claim that SwiftTLA implements every TLA+
construct. It is a claim about the supported language boundary:

```text
accepted → compiled once and preserved through every supported output
unsupported → rejected with a precise compiler diagnostic
```

TLC provides independent bounded evidence for the cases declared by the
repository. Exact graph equality establishes agreement for those models and
finite configurations; it does not turn a bounded run into a universal proof.
