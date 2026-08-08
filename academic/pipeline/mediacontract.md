# MediaContract — Cross-Actor Verification

## What it proves

Two invariants that single-actor specs cannot check:
1. `WriterRequiresCapture`: Writer only records when Capture is running
2. `PlayerRequiresWriter`: Player only plays after Writer has finished

## TLC Results

```
211 states generated, 66 distinct states found, 0 states left on queue.
The depth of the complete state graph search is 10.
```

Both invariants hold after fixing cross-actor guards.

## Bugs Found by Cross-Actor Verification

TLC found violations that single-actor verification (Capture alone, Writer alone,
Player alone) could never catch:

| Bug | Violation | Fix |
|-----|-----------|-----|
| Writer starts before Capture runs | `wPhase=2, cPhase=0` | Add `cPhase=2` guard to `WStart` |
| Capture stops while Writer records | `wPhase=2, cPhase→0` | Add `wPhase≠2,3` guard to `CStop` |
| Capture interrupts while Writer records | `wPhase=2, cPhase→3` | Add `wPhase≠2,3` guard to `CInterrupt` |

## Why this matters

Single-actor specs (Capture, Writer, Player individually) verify internal state
machines. But they can't reason about dependencies BETWEEN actors. Cross-actor
verification finds interleaving bugs that ship to production.

This is the thesis: SwiftTLA proves cross-actor invariants at compile time,
catching bugs that single-component testing and single-actor verification miss.
