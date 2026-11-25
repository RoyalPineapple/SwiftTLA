# Test targets

All local test execution goes through `scripts/local-validation.sh`, which
locks the resources each command writes, isolates build artifacts, and stops unsafe
memory pressure. Hosted CI remains the admission authority; local runs are
diagnostic.

`SwiftTLATests` is the fast semantic-core target. Use it for parser, scope, operator, simultaneous-update,
structured-value, runtime, and generated-machine work:

```sh
./scripts/local-validation.sh swiftpm-test "FormalOperatorTests"
```

The filter matches suite and test identifiers the way `swift test --filter`
does. SwiftPM still builds every test target before running the selected
suites. The wrapper keeps SwiftPM's incremental build cache in the worktree’s Git
directory and records a source-content key. Product builds and tests share
that cache lock. Other worktrees and proof jobs can run concurrently within
the host capacity and memory guards. Per-run scratch files stay outside the
working tree.

During the corpus migration, build the validation CLI once per batch:

```sh
cli="$(./scripts/local-validation.sh port-build)" || exit 1
"$cli" native list
```

This builds the debug `tlc-validate` product and its dependencies in the
same guarded cache. To trial four compiler jobs on a batch, pass
`port-build 4`. The default is one job. Both use the same lock and memory
watchdog. Before compiling, check each configuration against its pinned TLC
capture. Record its selected properties, expected outcome and deadlock setting.
For an exhaustive graph comparison, the state limit must cover all reachable
states in the original. Build output goes to stderr. Stdout gives the executable
path. Use that executable for each case with separate output directories.
Finish comparisons before another build replaces the executable, or retain a
copy for the batch. Run focused tests before publication. Remove this mode and its documentation when the migration ends.

`SwiftTLAParityTests` contains the slower upstream corpus, finite-graph,
and temporal/symmetry conformance checks:

```sh
./scripts/local-validation.sh swiftpm-test "UpstreamParityTests"
```

GitHub Actions runs both test targets as the required `swift-tests` job. The
job also builds the valid and invalid external-consumer targets exercised by
the test suites. Run focused local diagnosis through the approved wrapper.
