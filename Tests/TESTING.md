# Test targets

`SwiftTLATests` is the fast semantic-core target. It has no dependency on
`UpstreamParity`; use it for parser, scope, operator, simultaneous-update,
structured-value, runtime, and generated-machine work:

```sh
swift build --target SwiftTLATests --scratch-path .build/semantic-core
```

SwiftPM currently has no test-target selector: `swift test --filter
FormalOperatorTests` executes that focused suite, but still builds every test
target first. Use the core-only build command above to validate the fast target
without compiling `UpstreamParity`; use the filtered test command when an
executed XCTest run is required.

```sh
swift test --filter FormalOperatorTests
```

`SwiftTLAParityTests` contains the slower upstream corpus, TLC/oracle,
core-governance, temporal/symmetry, and public-workflow checks:

```sh
swift test --filter SwiftTLAParityTests
swift test --filter UpstreamParityTests
```

`swift test` without a filter continues to run both targets.
