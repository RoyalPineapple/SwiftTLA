# SwiftTLA Repository Rules

## Host Safety

- GitHub Actions / SwiftTLA-ValidationEvidence remains the admission authority.
- Local validation is diagnostic-only and allowed only through `scripts/local-validation.sh`: `static`, a focused `swiftpm-test <filter>`, or a focused `xcode-test <identifier>`.
- The wrapper takes the repository-wide exclusive lock, serializes work, isolates build artifacts, and stops unsafe memory pressure. Do not invoke local `swift test`, `xcodebuild test`, `make ci*`, TLC, or broad compiler/test commands directly.
- Any mode outside the wrapper requires explicit user authorization for the exact command.

## Typed Boundaries

Treat string-keyed and otherwise untyped data as a guarded boundary.

- Do not expose raw `[String: TLAValue]` maps through application-facing public APIs.
- Keep raw TLA maps inside the formal engine, parser, renderer, or serialization boundary.
- At a public boundary, use a typed model API or a dedicated projection type that owns the raw map.
- A projection must validate keys and values before it returns typed data.
- Do not index a raw state map at an application call site.
- Use generated `State`, `Variables`, and `ActionLabel` types for application code.
- Name any unavoidable raw-TLA conversion explicitly. Do not present it as normal application state.

## Concurrency

- All public SwiftTLA values and generated APIs must have compiler-checked `Sendable` conformance.
- Do not use `@unchecked Sendable` in repository-owned source or tests.
- SwiftTLA model state is value data only. Do not add arbitrary instance storage to a model declaration.

## Model Authoring

- New application models, examples, and documentation use `#spec` with `Algorithm`, `SharedVar`, `LocalVar`, `Each`, and `Do`.
- Keep `Var`, `Variable`, and `Action` in the formal core for generated code, imported TLA+ modules, and parity fixtures. Do not introduce them as a second public authoring style.
- Remove compatibility spellings instead of preserving them. Migrate repository callers in the same change.

## Test Naming and Cleanliness

- Name a test suite and its cases for the behavior or compiler contract they prove, not for the implementation type, temporary migration, or refactor that introduced them.
- An upstream model name may appear only to identify the canonical corpus owner. Pair it with the tested contract, for example `VoteProofCorpusRenderingTests`, not `VoteProofMigrationTests`.
- Each implementation phase includes a Ponytail review and a cleanliness pass: delete obsolete paths, migrate callers, and reject compatibility shims, duplicate witnesses, and stale generated evidence.
