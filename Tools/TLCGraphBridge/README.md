# TLC Graph Bridge

`LosslessStateWriter` is a version-bound transport adapter for TLC v1.8.0. It
records the complete `IStateWriter` callback surface as append-only evidence.
The independent validation pipeline writes `STLAGRF2` binary records; JSONL
remains available for bridge diagnostics. TLC owns graph exploration. The Swift reader validates
the event stream and constructs the TLC graph. The graph comparator decides
formal equality.

Producer IDs are local to each run. The two producers independently encode
complete values with the `STLASV01` typed byte contract. The comparator
partitions by a digest, sorts the full values within each partition, and
compares those bytes exactly before assigning shared ranks.
It rewrites every edge to a 12-byte `(source rank, action ID, target rank)`
record, partitions by source rank, sorts each partition, and compares the
complete edge sets. Neither TLC fingerprints nor Swift hash values establish
state equality. Property and deadlock verdicts are compared separately.

`STLASV01` state bytes are the eight-byte version marker, a big-endian `u32`
binding count, then UTF-8 names (`u32` byte length plus bytes) and typed values
in name-byte order. Every value is a one-byte tag, big-endian `u32` payload
length, and payload: `1` signed 64-bit integer, `2` boolean byte, `3` UTF-8
string, `4` UTF-8 model constant, `5` set, `6` tuple, `7` record, or `8`
function. Collections start with a `u32` item count; nested values use the
same framing. Set members and function keys sort by their complete encoded
bytes; record fields sort by UTF-8 name bytes. Tuple order is retained.
Empty records and functions, integer-keyed functions over `1..n`, and
string-keyed functions normalize to the corresponding tuple or record form.
The reader rejects malformed framing, invalid UTF-8, duplicate or out-of-order
unordered members, and incomplete records.

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
`resolvedActions` array. Each binary action record retains the selected
callback action name and the resolved leaf invocation location, then edges
reference its numeric ID. The comparator uses the selected action identity
when declared by the generated model, otherwise the named leaf invocation;
conflicting declarations fail instead of silently choosing one.
For an `INSTANCE` substitution, the bridge resolves the disjunction and finite existential prefix through TLC's semantic nodes and contexts.
It preserves substitutions, then asks TLC which leaf predicates admit the original source and target states.
Bound domains that depend on the source state are resolved per transition rather than cached across states.
State-dependent invocation arguments are evaluated against TLC's source and target states and likewise never cached across states.
Every matching named invocation becomes an edge, including distinct invocations with the same source and target.
No native predicate or native action list participates in this resolution.

The reader rejects missing, duplicate, unnamed, and undeclared resolved invocations.
The diagnostic JSON retains the original callback and sequence; both formats
have a completion digest.
Unsupported decomposition produces an explicit failure, not an unverified or guessed label.
Named instance namespaces and recursive action prefixes still require additional identity support.
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
