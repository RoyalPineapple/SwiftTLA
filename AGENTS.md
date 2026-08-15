# SwiftTLA Repository Rules

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
