# SwiftTLA language fragment (B v1)

SwiftTLA aims at **TLA+-compatible finite-state safety checking** for a
defined fragment, with TLC as the external oracle.

## Authoring surface

- **Primary:** Swift DSL → `TLASpec` → `ModelChecker` / `.tlaModule`
- **Macro:** `@TLAModel` re-parses a `TLASpec { }` body, checks it, emits
  nested `StateMachine`
- **Not v1:** parsing arbitrary `.tla` source into Swift

## Supported (v1)

| Area | Support |
|------|---------|
| Variables | Finite domain: int, bool, string, sets, tuples, records-as-functions |
| Init | Concrete values; nondeterministic via `Variable(v, in: range)` / `initialSet` |
| Actions | `/\` `\/`, assignment (`becomes`), `UNCHANGED` (auto-complete), guards |
| CHOOSE | Finite sets; **multi-choose is Cartesian product** (bindings accumulate) |
| Quantifiers | `\A` `\E` over finite sets |
| Safety | Invariants evaluated on every reached state |
| Deadlock | Opt-in `DeadlockCheck()` |
| ASSUME / CONSTANT | Substituted before explore; emitted in `.tlaModule` |
| Export | `.tlaModule` must be SANY/TLC-runnable for supported specs |
| Oracle | `scripts/validate_tlc.sh` operator matrix; `validate_upstream_parity.sh` vs [tlaplus/Examples](https://github.com/tlaplus/Examples) (see UpstreamParity.md) |
## Explicitly not v1

- Full liveness (`[]`, `<>`, `~>`, WF/SF) as product claims — `LivenessChecker` is experimental
- Symmetry reduction (no silent auto-symmetry)
- State constraint (TLC `CONSTRAINT`) — add only with correct polarity + oracle
- Refinement mappings / INSTANCE
- Infinite-state or TLAPS proofs
- Name-brand algorithms (Paxos, …) without TLC parity

## Bootstrap (self-hosting)

The checker lifecycle is itself a TLA+ model:

1. **`TLASpec.bfsChecker(maxStates:)`** — canonical lifecycle spec in core
2. **`@TLAModel struct BFSChecker`** (`SwiftTLAModels`) — checked + concrete machine
3. **Composition** — `checker.extending(user)` / `ModelChecker.checkComposed(user:)`
4. Production **BFS is plain** (queue/visited). The lifecycle model is for
   self-proof and composition, not a decorative driver with wrong counters.

`TLAModelType` marks `@TLAModel` types so callers can compose by type:

```swift
try ModelChecker.checkComposed(user: HourClock.spec)
// or
let g = try ModelChecker.compose(BFSChecker.spec, HourClock.spec).exploreGraph()
```

## Rule

**No feature without an oracle twin** (Swift test and/or TLC script) in the same change.

## Version

Fragment B v1 — 2026-08-06
