# TLC Graph Bridge

`LosslessStateWriter` is a version-bound transport adapter for TLC v1.8.0. It
records the complete `IStateWriter` callback surface as append-only
`TLCGraphEvent` JSONL. It does not evaluate expressions, infer successors,
canonicalize values, or compare graphs.

The supported schema is `swifttla.tlc.graph-events` version 1. It has a
header, state and transition callback records, completion/failure records, and
a footer that authenticates the exact body bytes. The consumer validates
strict UTF-8, exact record schemas, sequence/order rules, the footer digest,
and the pinned provenance before it turns the stream into TLC graph evidence.
Unknown or malformed fields are rejected.

This boundary is deliberately transport-only. TLC remains responsible for its
own exploration. SwiftTLA's independent adapter canonicalizes the verified
stream and the Swift graph comparator decides the bounded relation.

## Build lock

`Verification/CoreConformance/toolchain.json` locks the TLC source tag and
commit, JAR SHA-256, Temurin Java archive SHA-256 per architecture, and this
bridge's class/source/binary SHA-256 values. The setup script compiles this
source against only those verified files. A digest mismatch is an error.

`Tools/TLCGraphBridge/.tool-cache` may contain the exact locked JAR and Java
archive for local reproducibility. It is not a distribution mechanism. If a
fresh machine cannot retrieve or provide the exact pinned artifacts, setup
fails instead of accepting a changed artifact.

Use `make core-conformance` for exact graph comparison. The bridge spike below
is a focused schema and provenance transport check, not a complete comparison.

Run the bounded spike with:

```sh
Tools/TLCGraphBridge/spike/run.sh --output /tmp/tlc-bridge-spike
```

The spike requires the pinned TLC JAR and Temurin JDK cached below
`Tools/TLCGraphBridge/.tool-cache`. The script verifies their SHA-256 digests
before compilation or execution.
