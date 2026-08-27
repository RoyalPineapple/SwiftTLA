# TLC Graph Bridge

`LosslessStateWriter` is a version-bound transport adapter for TLC v1.8.0. It
records the complete `IStateWriter` callback surface as append-only
`TLCGraphEvent` JSONL. TLC owns graph exploration. The Swift reader validates
the event stream and constructs the TLC graph. The graph comparator decides
formal equality.

The supported schema is `swifttla.tlc.graph-events` version 2. It has a
header, state and transition callback records, and a footer whose SHA-256
covers the exact body bytes. The consumer validates
strict UTF-8, exact record schemas, sequence/order rules, the footer digest,
and closure counts before it turns the stream into TLC graph evidence. Unknown
or malformed fields are rejected. Tool, bridge, module, and configuration pins
are validated against the launched files before TLC runs.

## Build lock

`Verification/FiniteGraph/toolchain.json` locks the TLC source tag and
commit, JAR SHA-256, Temurin Java archive SHA-256 per architecture, and this
bridge's class/source/binary SHA-256 values. The setup script compiles this
source against only those verified files. A digest mismatch is an error.

`Tools/TLCGraphBridge/.tool-cache` may contain the exact locked JAR and Java
archive for local reproducibility. It is not a distribution mechanism. If a
fresh machine cannot retrieve or provide the exact pinned artifacts, setup
fails instead of accepting a changed artifact.

Use `./scripts/run_finite_graph_check.sh --case all --output .build/finite-graph-evidence`
for exact graph comparison.
