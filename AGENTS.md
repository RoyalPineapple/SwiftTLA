# SwiftTLA Repository Rules

## Host Safety

- GitHub Actions / SwiftTLA-ValidationEvidence remains the admission authority.
- Local validation is diagnostic-only and allowed only through `scripts/local-validation.sh`: `static`, `port-build` for the local corpus CLI, a focused `swiftpm-test <filter>`, or a focused `xcode-test <identifier>`.
- Focused Xcode checks on distinct packages can overlap with private DerivedData. The wrapper serializes checks of the same package and allows up to one heavy validation job per logical CPU, reserving one CPU for other work on multicore hosts. An exclusive holder of the repository-wide Xcode lock waits for all active Xcode checks and blocks new ones. Additional slots require enough current memory headroom for another guarded process tree. Product SwiftPM builds and tests serialize on their worktree’s product cache. Proof commands retain their repository lock. Proof preparation that uses SwiftPM products also takes the worktree product lock and reuses its validated compiler build. Heavy jobs share capacity slots. Static checks take a worktree-local lock. Keep the per-process-tree and system memory guards enabled. Do not invoke local `swift test`, `xcodebuild test`, `make ci*`, TLC, or broad compiler/test commands directly.
- Any mode outside the wrapper requires explicit user authorization for the exact command.

## Typed Boundaries

Treat string-keyed and otherwise untyped data as a guarded boundary.

- Do not expose raw `[String: TLAValue]` maps through application-facing public APIs.
- Keep raw TLA maps inside the formal engine, parser, renderer, or serialization boundary.
- At a public boundary, use a typed model API or a dedicated projection type that owns the raw map.
- A projection must validate keys and values before it returns typed data.
- Do not index a raw state map at an application call site.
- Use generated `State` and `Action` types for application code.
- Name any unavoidable raw-TLA conversion explicitly. Do not present it as normal application state.

## Concurrency

- All public SwiftTLA values and generated APIs must have compiler-checked `Sendable` conformance.
- Do not use `@unchecked Sendable` in repository-owned source or tests.
- SwiftTLA model state is value data only. Do not add arbitrary instance storage to a model declaration.

## Model Authoring

- New application models, examples, and documentation use `#spec` with scoped `Algorithm`, `scope.sharedVar`, process or procedure `scope.localVar`, `Each`, and `Do`.
- Keep `Var`, `Variable`, and `Action` in the formal core for generated code, imported TLA+ modules, and parity fixtures. Do not introduce them as a second public authoring style.
- Remove compatibility spellings instead of preserving them. Migrate repository callers in the same change.

## Test Naming and Cleanliness

- Name each test suite file after its suite. Keep shared fixture declarations in separate fixture files.

- Name a test suite and its cases for the behavior or compiler contract they prove, not for the implementation type, temporary migration, or refactor that introduced them.
- An upstream model name may appear only to identify the canonical corpus owner. Pair it with the tested contract, for example `VoteProofCorpusRenderingTests`, not `VoteProofMigrationTests`.
- Each implementation phase includes a Ponytail review and a cleanliness pass: delete obsolete paths, migrate callers, and reject compatibility shims, duplicate witnesses, and stale generated evidence.
