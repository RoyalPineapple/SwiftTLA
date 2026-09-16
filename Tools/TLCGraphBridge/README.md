# TLC Graph Bridge

`LosslessStateWriter` is a version-bound transport adapter for TLC v1.8.0. It
records the complete `IStateWriter` callback surface as append-only
`TLCGraphEvent` JSONL. TLC owns graph exploration. The Swift reader validates
the event stream and constructs the TLC graph. The graph comparator decides
formal equality.

The supported schema is `swifttla.tlc.graph-events` version 3. It has a
header, state and transition callback records, and a footer whose SHA-256
covers the exact body bytes. The consumer validates
strict UTF-8, exact record schemas, sequence/order rules, the footer digest,
and closure counts before it turns the stream into TLC graph evidence. Unknown
or malformed fields are rejected. Tool, bridge, module, and configuration pins
are validated against the launched files before TLC runs.

Each transition retains the original callback action and a `resolvedActions` array.
Ordinary actions retain their original identity in that array.
For an `INSTANCE` substitution, the bridge resolves the disjunction and finite existential prefix through TLC's semantic nodes and contexts.
It preserves substitutions, then asks TLC which leaf predicates admit the original source and target states.
Every matching named invocation becomes an edge, including distinct invocations with the same source and target.
No native predicate or native action list participates in this resolution.

The reader rejects missing, duplicate, unnamed, and undeclared resolved invocations.
The original callback remains in the retained stream, with its original sequence and completion digest.
Unsupported decomposition produces an explicit failure, not a coarse `Next` edge or a guessed label.
Named instance namespaces, recursive action prefixes, and state-dependent invocation arguments still require additional identity support.
These cases remain required corpus work and cannot pass through a fallback.

Hosted setup runs `check-instance-actions.py` against the locked TLC build.
The regression covers nested variable and constant substitutions, complete graphs, and multiple matching action identities.
Local diagnostics do not run this TLC regression.

## Build lock

`Verification/FiniteGraph/toolchain.json` locks the TLC source revision and the
hosted build artifact. It records the build run, build revision, archive SHA-256,
and JAR SHA-256. The rebuilt JAR uses the original source revision, but its bytes
differ from the unavailable release asset.

Setup validates the archive and JAR digests, source revision, manifest, and
standard-module inventory. It extracts only the named JAR, not arbitrary archive
paths. The lock also records each Temurin archive digest and every bridge source
digest. Setup rebuilds the bridge against those inputs. Each validation run records
the bridge digest and validates it before execution.

The hosted build retains its artifact for 90 days. Missing, expired, or changed
artifacts fail setup. A replacement requires a hosted source build, provenance
inspection, and an explicit lock update. Setup never accepts the moving release
as a fallback. The setup token requires Actions read permission for the build
repository.

`Tools/TLCGraphBridge/.tool-cache` can contain the exact locked Java archive.
The tool directory caches the digest-validated build archive. Neither cache
changes the accepted input identities.

The hosted finite-graph workflow runs the complete comparison and retains its
evidence. Local diagnostic checks run only through
`scripts/local-validation.sh` with a focused test filter.
