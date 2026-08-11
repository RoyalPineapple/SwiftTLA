# TLC Graph Bridge

`LosslessStateWriter` is a version-bound transport adapter for TLC v1.8.0. It
records the complete `IStateWriter` callback surface as append-only
`TLCGraphEventV1` JSONL. It does not evaluate expressions, infer successors,
canonicalize values, or compare graphs.

Run the bounded spike with:

```sh
Tools/TLCGraphBridge/spike/run.sh --output /tmp/tlc-bridge-spike
```

The spike requires the pinned TLC JAR and Temurin JDK cached below
`Tools/TLCGraphBridge/.tool-cache`. The script verifies their SHA-256 digests
before compilation or execution.
