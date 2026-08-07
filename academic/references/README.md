# Related Work for SwiftTLA

## Paper Mapping: Related Work → SwiftTLA Contribution

### 1. TLA+ Frontends / DSLs

| Prior Work | What It Does | How SwiftTLA Differs |
|---|---|---|
| **PlusCal** (Lamport 2009) | Imperative-like language that transpiles to TLA+ | Separate language/compiler. SwiftTLA is an **embedded DSL** — the spec IS Swift code. No runtime execution, no oracle parity, no self-proof. |
| **PGo / Modular PlusCal** (Hackett et al. 2023) | Compiles PlusCal → TLA+ + Go. Compiles spec to implementation, traces back to spec states. | Goes spec→code direction. SwiftTLA goes code-is-spec. No runtime model checker embedded in the host language. |
| **FizzBee** | Python-inspired TLA+ frontend | Similar "friendlier TLA+" spirit, but no Swift integration, no compile-time macro, no oracle parity, no checker-in-checker. |
| **SpecEdit** (Cuinat & Teodorov 2020) | Projectional IDE for TLA+ | Editor tooling, not a DSL or checker. |

### 2. Alternative TLA+ Model Checkers

| Prior Work | What It Does | How SwiftTLA Differs |
|---|---|---|
| **TLC** (Yu et al. 1999) | The reference explicit-state model checker for TLA+ (Java) | SwiftTLA uses TLC as an **oracle** for validation. TLC is the gold standard; SwiftTLA is a new checker validated against it. |
| **Apalache** (Konnov et al. 2019) | Symbolic (SMT-based) model checker for TLA+ | Different algorithmic approach (symbolic vs explicit-state). No DSL, no compile-time integration. |
| **ProB** (Leuschel & Butler 2008) | Animation and model checking for B, also supports TLA+ | General-purpose tool, not a Swift DSL. |

### 3. TLA+ in Industry

| Prior Work | What It Does | How SwiftTLA Differs |
|---|---|---|
| **AWS** (Newcombe et al. 2015) | Documents AWS's production use of TLA+/TLC for distributed systems design | Standard TLA+ workflow: write spec, check with TLC, implement separately. No code-is-spec. |
| **Azure Cosmos DB** (Howard et al. 2023) | TLA+ models of Cosmos DB consistency levels | Standard TLA+/TLC workflow. |
| **CCF** (Howard et al. 2025) | "Smart casual verification" — TLA+ models bound to implementation | Binds specs to C++ via trace checking. Different language, different binding approach. |

### 4. Compile-Time Verification via Macros

| Prior Work | What It Does | How SwiftTLA Differs |
|---|---|---|
| **Swift Macros** (Apple 2023) | General-purpose compile-time code generation in Swift | Provides the infrastructure. SwiftTLA is the first to use Swift macros for **model checking at compile time** — BFS runs in the compiler, invariants fail the build. |
| **Rust procedural macros** | Compile-time code generation in Rust | No known use for embedded model checking. |
| **constexpr/consteval (C++)** | Compile-time evaluation | Computes values, doesn't do state-space exploration. |

### 5. Self-Verifying Systems

| Prior Work | What It Does | How SwiftTLA Differs |
|---|---|---|
| **CakeML** (Kumar et al. 2014) | Verified ML compiler in HOL4 | Self-verification via theorem proving, not model checking. No oracle parity. |
| **Milawa** (Davis & Myreen 2015) | Self-verifying theorem prover | Theorem proving domain. Related bootstrap philosophy. |
| **TLC Safety Checking (Kuppe 2024)** | TLA+ spec of TLC's own safety algorithm | Models the checker in TLA+ (similar to SwiftTLA's `ModelCheckerProof.tla`) but does NOT implement it in a host language, does not provide oracle parity, and does not run at compile time. |

### 6. Oracle-Based / Differential Validation

| Prior Work | What It Does | How SwiftTLA Differs |
|---|---|---|
| **Differential testing of analyzers** (Kaindlstorfer et al. 2024) | Cross-validation of program analyzers | General technique. SwiftTLA's **TLC oracle parity** is a specific instance: state count equivalence between Swift runtime and TLC guarantees behavioral equivalence. Novel in the TLA+ ecosystem. |
| **Compilomorphic Fuzzing** (Klimis 2026) | Compiler tested against itself | Self-reference approach. Related to SwiftTLA's checker-modelling-itself bootstrap. |

## Key Gaps SwiftTLA Fills

1. **Single-source, two-backend embedded DSL**: One AST produces both a live Swift runtime checker AND valid TLA+ source. Not a transpiler (PlusCal generates TLA+ but has no runtime), not an external tool. The spec *is* the implementation.

2. **Oracle parity as a correctness criterion**: TLC state-count equivalence. A concrete, machine-checkable validation strategy. If the Swift checker produces the same number of states as TLC for 27 benchmark specs, it's correct.

3. **Compile-time model checking**: `@TLAModel` runs BFS in the Swift compiler. Invariant failure = build failure. No prior system embeds model checking into a production compiler's macro pipeline.

4. **Self-proof bootstrap**: The checker is itself modeled in TLA+ (`ModelCheckerProof.tla`, `BFSChecker.swift`) and verified by TLC. The checker verifies itself. TLC Safety Checking modeled the algorithm but didn't implement or run it.

## Venue Suggestions

- **OOPSLA** — PL venue, embedded DSL + macro story fits
- **ICSE / FSE** — Software engineering, compile-time verification angle
- **CAV / TACAS** — Formal methods, model checking implementation story
- **NFM / FM** — Formal methods in industry, Swift concurrency connection
