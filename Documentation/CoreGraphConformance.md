# Core graph conformance

Core graph conformance is a bounded, executable comparison between one
SwiftTLA BFS run and one TLC run. For each declared case, it compares the
canonical initial-state set, canonical state bindings, and complete labeled
transition multiset. It is stronger than matching a state count.

Published TLA+ semantics are authoritative. TLC is a pinned executable
reference; its source and tests are diagnostic evidence. SwiftTLA does not
claim a hidden checker or oracle.

The authority is the declared semantic source and retained hosted evidence,
not this document. GitHub Actions runs exact core conformance.
Local use is diagnostic-only: use the approved narrow validation wrapper, or
obtain explicit authorization for a broader command. Do not treat a local run
as admission evidence.

## What is pinned

`Verification/CoreConformance/toolchain.json` locks TLC v1.8.0, its source
commit and JAR digest, an architecture-specific Temurin 17 archive digest,
and the bridge class/source/binary digests. `cases.json` locks every case's
module, configuration, arguments, mappings, and upstream reference. Setup
fails closed when a required digest does not match.

The setup script can seed an exact, digest-matching artifact from
`Tools/TLCGraphBridge/.tool-cache`. That cache is a local convenience, not a
published artifact source. A fresh machine must obtain the exact locked files
or setup fails; it must not silently accept a changed upstream release asset.

## Evidence and diagnosis

The command writes fresh evidence under `.build/core-conformance-evidence`.
Each case retains the TLC invocation and raw output, one complete canonical
graph stream from each engine, and one exact comparison record.

```text
swift-graph.jsonl ─┐
                   ├→ exact canonical comparison → comparison.json
tlc-graph.jsonl ───┘
```

Each graph stream contains a header, sorted initial states, sorted states,
sorted labeled edges with multiplicity, and a final completion record. The
completion record declares the outcome and exact record counts. A missing,
truncated, failed, or bounded completion cannot represent an exact result.

`comparison.json` records whether the two complete graphs match and includes
the first structured differences when they do not. Exact equality is decided
directly from the in-memory canonical runs; the retained graph streams explain
that decision.

When a run fails, inspect `comparison.json`, then `swift-graph.jsonl`,
`tlc-graph.jsonl`, and `logs/` in that case's evidence directory. A graph
mismatch is classified by relation, such as initial state, state binding,
edge, outcome, or mapping difference.

Counterexample traces have a different job. They explain an invariant or
other checker failure and may be replayed, but they are not proof that the
complete graph was explored. Complete-graph evidence comes from a successful,
exhaustive declared run and its bridge stream.

## Controls and limits

Core conformance has three shell outcomes. Exit `0` means every declared case
completed and its exact graphs matched. Exit `1` means the complete graphs
differ. Exit `2` means setup, execution, or evidence validation failed.

This claim applies only to the finite cases named in `cases.json` and only to
the compared safety graph relation. It does not establish arbitrary bounds,
temporal properties, liveness, fairness, symmetry reduction, or unsupported
TLA+ constructs.
