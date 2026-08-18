# Test targets

All local test execution goes through `scripts/local-validation.sh`, which
takes the repository-wide lock, isolates build artifacts, and stops unsafe
memory pressure. Hosted CI remains the admission authority; local runs are
diagnostic.

`SwiftTLATests` is the fast semantic-core target. It has no dependency on
`UpstreamParity`; use it for parser, scope, operator, simultaneous-update,
structured-value, runtime, and generated-machine work:

```sh
./scripts/local-validation.sh swiftpm-test "FormalOperatorTests"
```

The filter matches suite and test identifiers the way `swift test --filter`
does. SwiftPM still builds every test target before running the selected
suites; the wrapper's isolated scratch directory keeps that build out of the
working tree.

`SwiftTLAParityTests` contains the slower upstream corpus, TLC/oracle,
core-governance, temporal/symmetry, and public-workflow checks:

```sh
./scripts/local-validation.sh swiftpm-test "UpstreamParityTests"
```

The fast PR path (`make ci-pr`) runs the smoke suite through the same
wrapper; use `scripts/run_pr_smoke_tests.sh` to run it directly.
