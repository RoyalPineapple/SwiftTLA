# TLC Graph Bridge

`LosslessStateWriter` is a version-bound transport adapter for TLC v1.8.0. It
records the complete `IStateWriter` callback surface as append-only evidence.
The independent validation pipeline writes `STLAGRF1` binary records; JSONL
remains available for bridge diagnostics. TLC owns graph exploration. The Swift reader validates
the event stream and constructs the TLC graph. The graph comparator decides
formal equality.

Producer IDs are local to each run. The comparator sorts complete canonical
state values and compares them byte-for-byte before assigning shared ranks.
It rewrites every edge to a 12-byte `(source rank, action ID, target rank)`
record, partitions by source rank, sorts each partition, and compares the
complete edge sets. Neither TLC fingerprints nor Swift hash values establish
state equality. Property and deadlock verdicts are compared separately.

The diagnostic schema is `swifttla.tlc.graph-events` version 3. The binary
pipeline records full values for each
initial or newly discovered reachable state, but only fingerprints for known
sources, seen targets, and excluded targets. Excluded callbacks retain their
flags and original action without resolving actions that cannot become graph
edges. The binary stream keeps every reachable labeled edge as a 21-byte event
with numeric source, action, and target IDs. Both formats have a
header, state and transition callback records, and a footer whose SHA-256
covers the exact body bytes. The consumer validates
strict UTF-8, record order and identity rules, the footer digest,
and closure counts before it turns the stream into TLC graph evidence. Unknown
or malformed fields are rejected. Tool, bridge, module, and configuration pins
are validated against the launched files before TLC runs.

The diagnostic JSON transition retains the original callback action and a
`resolvedActions` array. The binary stream stores each resolved named action
once, then references its numeric ID on every labeled edge.
For an `INSTANCE` substitution, the bridge resolves the disjunction and finite existential prefix through TLC's semantic nodes and contexts.
It preserves substitutions, then asks TLC which leaf predicates admit the original source and target states.
Every matching named invocation becomes an edge, including distinct invocations with the same source and target.
No native predicate or native action list participates in this resolution.

The reader rejects missing, duplicate, unnamed, and undeclared resolved invocations.
The diagnostic JSON retains the original callback and sequence; both formats
have a completion digest.
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

The hosted independent validation workflow runs both parity comparisons and
retains their evidence. Local diagnostic checks run only through
`scripts/local-validation.sh` with a focused test filter.
