# Finite graph comparison

Finite graph comparison is a bounded, executable comparison between one
SwiftTLA BFS run and one TLC run. For each declared case, it compares the
canonical initial-state set, canonical state bindings, and complete labeled
transition multiset. It is stronger than matching a state count.

Published TLA+ semantics are authoritative. Pinned TLC is the external
executable reference. Its source and tests provide diagnostic evidence.

The declared semantic source and retained hosted evidence are authoritative.
GitHub Actions runs exact finite graph comparison.
Local use provides diagnostic evidence through the approved narrow validation
wrapper. Hosted GitHub Actions provides admission evidence.

## What is pinned

`Verification/FiniteGraph/toolchain.json` locks TLC v1.8.0, its source
commit and JAR digest, an architecture-specific Temurin 17 archive digest,
and the bridge class/source/binary digests. `cases.json` locks every case's
module, configuration, and Swift exploration policy. Setup
fails closed when a required digest does not match.

The setup script can seed an exact, digest-matching artifact from
`Tools/TLCGraphBridge/.tool-cache`. The published artifact source supplies the
locked files to a fresh machine. Setup accepts only the declared digests.

## Evidence and diagnosis

The command writes fresh evidence under `.build/finite-graph-evidence`.
Each case retains the TLC invocation and raw output, one complete canonical
graph stream from each explorer, and one exact comparison record.

```text
swift-graph.jsonl ─┐
                   ├→ exact canonical comparison → comparison.json
tlc-graph.jsonl ───┘
```

Each graph stream contains a header, sorted initial states, sorted states,
sorted labeled edges with multiplicity, diagnostics, counterexample traces,
and a final completion record. The completion record declares the outcome and
exact record counts. A missing, truncated, failed, or bounded completion cannot
represent an exact result.

`comparison.json` records whether the two complete graphs match and includes
the first structured differences when they do not. Exact equality is decided
directly from the in-memory completed graph runs; the retained graph streams explain
that decision.

When a run fails, inspect `comparison.json`, then `swift-graph.jsonl`,
`tlc-graph.jsonl`, and `logs/` in that case's evidence directory. A graph
mismatch is classified by relation, such as observable names, initial state,
state binding, edge, or outcome.

Counterexample traces explain an invariant or other checker failure. Complete
graph evidence comes from a successful, exhaustive declared run and its bridge
stream.

## Controls and limits

Each case declares one `exploration` value with `maximumStateLimit` and an
explicit disabled symmetry mode. A run that requires more states than its limit
is bounded and cannot produce an exact comparison. The retained TLC process
record contains the same exploration value.

Finite graph comparison has three shell outcomes. Exit `0` means every declared case
completed and its exact graphs matched. Exit `1` means the complete graphs
differ. Exit `2` means setup, execution, or evidence validation failed.

The claim covers the finite cases named in `cases.json`, their declared bounds,
and the compared safety graph relation. Temporal, fairness, and symmetry claims
have their own declared conformance cases.
