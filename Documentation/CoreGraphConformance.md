# Core graph conformance

Core graph conformance compares a finite SwiftTLA run with a pinned TLC run.
It compares the complete labeled transition relation, not only state counts.

The retained evidence records the input files, toolchain identities, command
arguments, canonical graphs, logs, and comparison result.

Run the maintained command:

```bash
make core-conformance
```

The command uses the locked TLC, Java, and bridge artifacts. It fails when an
artifact identity, input, graph stream, or comparison result does not match.

The current claim has limits. It applies only to the listed finite core cases.
It does not prove arbitrary finite bounds, liveness, fairness, or unsupported
TLA+ constructs.

The retained controls include a same-count graph mismatch and an invariant
violation with trace and replay evidence. These controls make sure that the
comparison rejects a false match.
