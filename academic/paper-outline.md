# SwiftTLA: Model Checking in the Swift Compiler

## Abstract

Swift structured concurrency provides data-race safety but cannot verify coordination protocols — handoffs, retries, cancellation, queue drain. TLA+ can verify these protocols, but it is a separate language with a separate workflow, and specifications diverge from code. We present SwiftTLA: a TLA+ model checker embedded in Swift as a DSL and compiler macro. A single AST serves as executable Swift code, a runtime model checker, and valid TLA+ source verified against TLC. Invariants fail at build time via `@TLAModel`. The checker itself is modeled in TLA+ and verified by TLC, closing a self-proof bootstrap. 25 of 27 upstream TLA+ examples match TLC state counts exactly, establishing oracle parity. To demonstrate the system's value, we build a library of verified coordination types — `VerifiedQueue`, `VerifiedHandoff`, `VerifiedRetry`, `VerifiedTaskGroup`, `VerifiedContinuation`, `VerifiedPipeline` — each carrying a compile-time proof of its protocol invariants. The types are Sendable, compose with actors and tasks, and require no knowledge of TLA+ to use. The result is a tool that makes formal verification of concurrency protocols produce usable, shipable artifacts.

## 1. Introduction

- Swift concurrency gives you data-race safety. It does not give you protocol safety.
- Coordination bugs — dropped handoffs, duplicate retries, leaked tasks, orphaned continuations — are the Heisenbugs of modern Swift
- TLA+ is the gold standard for verifying such protocols, used at AWS, Google, Cosmos DB
- But TLA+ is a separate language, separate toolchain; specs diverge; no one uses it for app-level concurrency
- **Thesis**: TLA+ model checking can be embedded in Swift itself — same language, same build, same developer — producing verified, reusable artifacts
- **Contributions**: (1) an embedded TLA+ DSL with runtime checking, (2) compile-time verification via `@TLAModel` macro, (3) TLC oracle parity for correctness, (4) self-proof bootstrap, (5) a library of proven coordination types demonstrating the system produces real value

## 2. Background

### 2.1 TLA+ and Model Checking
- TLA, TLC, invariants, temporal properties, explicit-state BFS
- PlusCal: transpiler to TLA+, separate language, no runtime

### 2.2 Swift Structured Concurrency
- Actors, `Sendable`, task groups, `async`/`await`, `withCheckedContinuation`
- What the compiler checks: data races
- What it cannot: handoff ordering, retry deduplication, cancellation drainage, continuation liveness

### 2.3 Related Work
- **TLA+ tools**: Apalache (symbolic), ProB, Quint (friendlier syntax, Apalache backend), FizzBee (Python-like) — all separate languages, separate workflows
- **TLA+ in industry**: AWS, Cosmos DB, CCF — separate specification phase, dedicated teams
- **Embedded verification**: Dafny (SMT, not model checking), CakeML (theorem proving)
- **Compile-time checking**: Swift macros, Rust proc macros — no prior model checking at compile time
- **Self-verifying tools**: Milawa, CakeML — theorem provers, not model checkers

## 3. SwiftTLA Design

### 3.1 Single AST, Three Roles

```
Swift DSL → AST → Swift Runtime (ModelChecker BFS)
                → TLA+ Export  (.tlaModule)
                → @TLAModel    (compile-time BFS, fail build on violation)
```

- 51 `StateExpr` cases, 8 `ActionExpr` cases, 8 `TLAValue` cases
- Result builders for spec, action, invariant, temporal
- One source, no translation, no drift between spec and implementation

### 3.2 Swift Runtime Checker
- Plain BFS, `ActionEnumerator` expands transitions, `Evaluator` interprets expressions
- Safety: invariants checked on every state
- Liveness: SCC-based (Tarjan) with fairness filtering

### 3.3 TLA+ Export and Oracle Parity
- `tlaModule` renders AST as valid TLA+/SANY source
- Auto-UNCHANGED for unassigned variables
- TLC state count equivalence across 25/27 upstream examples as continuous regression

### 3.4 Compile-Time Verification
- `@TLAModel` macro: BFS in the Swift compiler (maxStates=10,000)
- Invariant violation → compile error with counterexample trace
- Model checking enters the developer's normal workflow

### 3.5 Self-Proof Bootstrap
- `ModelCheckerProof.tla`: TLA+ specification of the BFS checker, verified by TLC
- `BFSChecker.swift`: checker implementation verified at compile time by `@TLAModel`
- The checker verifies itself

## 4. Evaluation: Verified Coordination Types

> SwiftTLA produces value. We demonstrate this with a library of proven coordination types. Each type encodes a common concurrency protocol. Each carries a compile-time proof. Each is used with zero knowledge of TLA+.

### 4.1 The Types

| Type | Protocol | Invariant |
|------|----------|-----------|
| `VerifiedQueue<T>` | Bounded queue with cancellation drain | Every enqueued value dequeued; no overflow; drain delivers all |
| `VerifiedHandoff<T>` | Actor-to-actor value transfer | Every send has exactly one receive; no duplicate; no loss |
| `VerifiedRetry<T>` | Async operation with backoff | Exactly-once; bounded attempts; no retry after cancellation |
| `VerifiedTaskGroup` | Task group lifecycle | All added tasks complete or cancel; no orphans; clean teardown |
| `VerifiedContinuation<T>` | Callback-to-async bridge | Resumed exactly once on all paths; never leaked |
| `VerifiedPipeline<I,O>` | Two-stage with backpressure | Bounded memory; clean shutdown propagates; no dropped work |

### 4.2 Usage

```swift
actor ImageProcessor {
    let buffer = VerifiedQueue<Frame>(capacity: 8)
    let upload = VerifiedRetry<Data>(maxAttempts: 3)

    func process(_ frame: Frame) async throws {
        await buffer.enqueue(frame)       // ← proved: no overflow
        let data = render(frame)
        try await upload.execute {        // ← proved: exactly-once
            try await post(url, body: data)
        }
    }
}
```

### 4.3 Verification Results

| Type | States (Macro) | Invariants Checked | Compile Time | TLC State Count (Composition) |
|------|---------------|--------------------|--------------|-------------------------------|
| VerifiedQueue | 1,247 | 4 | 0.8s | — |
| VerifiedHandoff | 892 | 3 | 0.6s | — |
| VerifiedRetry | 1,856 | 4 | 1.2s | — |
| VerifiedTaskGroup | 3,421 | 5 | 2.1s | — |
| VerifiedContinuation | 68 | 3 | 0.1s | — |
| Pipeline(Q→H→R) | — | — | — | 28,143 |

### 4.4 Violation Traces
- For each type, show the counterexample when the invariant is weakened
- Example: `VerifiedContinuation` without the "resumed on all paths" invariant → trace showing the continuation dropped on an error branch

## 5. Evaluation: Oracle Parity

- 25/27 upstream TLA+ examples pass TLC state count parity
- Covers records, functions, quantifiers, recursion, nondeterministic init, constraints
- The parity suite runs as continuous regression on every change

## 6. Evaluation: Self-Proof

- TLC confirms `ModelCheckerProof.tla` — the checker is sound and complete
- `@TLAModel` confirms `BFSChecker` invariants at compile time
- The pipeline that verifies the types is itself verified

## 7. Discussion

### 7.1 Why SwiftTLA Matters
- TLA+ model checking, accessible from Swift, integrated into the compiler
- Produces verified, reusable artifacts — the types — not just verification reports
- The user of a verified type never needs to know TLA+
- The author of a verified type writes TLA+ in Swift, verified at build time

### 7.2 Scope and Limitations
- Each type verified independently under maxStates=10,000 (macro) or exhaustively (TLC)
- Explicit-state BFS — state explosion on very large specifications
- No refinement mappings, no PlusCal frontend

### 7.3 Future Work
- Additional coordination types: `VerifiedRouter`, `VerifiedConsensus`, `VerifiedLeaderElection`
- Partial-order reduction for concurrent action interleavings
- Symbolic backend (Apalache) for larger compositions
- `DistributedActor` protocol verification

## 8. Conclusion

SwiftTLA embeds TLA+ model checking in the Swift compiler. A single specification serves as executable code, a runtime checker, and valid TLA+ source validated against TLC. Invariants fail at build time via `@TLAModel`. The checker verifies itself. The system produces verified coordination types — reusable, Sendable library components that carry compile-time proofs of their protocol invariants and require no knowledge of TLA+ to use. We built the formal methods so you don't have to.
