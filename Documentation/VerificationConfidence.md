# Verification Confidence: From Spec to Generated Code

**Feature**: native-action-codegen
**Audience**: developers who do not know TLA+
**Purpose**: explain what SwiftTLA checks, what it proves, and what it does not prove

---

## What This System Does

You write a specification in the Swift DSL. The system does three things:

1. It runs a model checker on your specification at compile time. If the specification has an invariant violation, a deadlock, or a liveness failure, the build stops with an error.

2. It generates native Swift code from your specification. This code does the same state transitions as the specification.

3. It runs checks at test time (`swift test`) that make sure the generated code matches the specification.

The question this document answers: **how much confidence can you have that the generated code is correct?**

---

## The Four Checks

The system runs four kinds of checks. Each one is independent. When they all pass, you have strong evidence that the generated code is correct.

### Check 1: Compile-Time Model Checking (`verifySpec`)

**When it runs**: at compile time (in the macro) and at test time

**What it does**: the model checker reads your specification and explores every possible state. It checks three things:

- That no invariant is violated in any reachable state
- That the system does not deadlock (stop without reaching a final state)
- That liveness conditions hold

**What it proves**: your specification is free of the errors listed above, in the bounded state space.

**Level of independence**: full. This check uses only the interpreter. It does not use the generated code at all. This is the authoritative check. If `verifySpec` passes, you know that the specification itself is correct.

**Limits**: the model checker uses a maximum number of states. The default is 100,000 for the compile-time check and 100,000 for the test-time check. You can increase this limit by changing the `maxStates` parameter in your specification.

When the limit is reached before all states are explored, the model checker reports `depthExceeded`. At compile time, the macro reports the exact count (for example, "Depth exceeded: 100000/100000"). At test time, `verifySpec` reports "Spec verification failed" with the same details. When you see this, increase the limit and try again. The result is not a pass. You cannot assume the specification is correct when the limit is reached.

### Check 2: The Parser-Builder Equivalence Check

**When it runs**: at runtime, when `spec` is accessed

**What it does**: there are two separate systems that build the same data from your specification source:

- The **parser** (SpecParser) reads the Swift syntax at compile time and builds an AST (abstract syntax tree).
- The **builder** (result builder) runs your specification code at runtime and builds an AST.

The check compares the two ASTs. If they are different, there is a bug in one of the two systems.

**What it proves**: the parser and the builder produce the same AST. This catches bugs in either the parser or the builder. A mismatch stops the system before any further checks run.

**Level of independence**: strong. The two systems use completely different code paths. The parser walks Swift source syntax. The builder uses Swift result builders. A bug in one system cannot affect the other.

**Note**: this check has a known exception. Some specifications use bare `Var` references in the builder (for example, `let hr = Var<Int>("hr", 1)` followed by `hr` on its own line). The parser does not handle all patterns that the builder handles. For these specifications, the check prints a warning but does not stop. The warning tells you that the equivalence cannot be confirmed for that specification.

### Check 3: The Codegen-to-Interpreter Equivalence Check (`verifyTransitions`)

**When it runs**: at test time

**What it does**: the system first builds a BFS (breadth-first search) graph of all reachable states and transitions. This is the `transitionMatrix`. For every edge in that graph (from-state, action, expected-to-state), the system:

1. Creates an instance of your model type
2. Sets its state to the from-state
3. Calls the **native** action method (the generated Swift code)
4. Gets the result state
5. Compares the result state to the expected-to-state

If any result does not match, the test fails.

**What it proves**: for every reachable transition, the generated native code and the interpreter produce the same final state.

**Level of independence**: partial. Both the generated code and the interpreter work from the same AST. A bug that affects both systems equally would not be caught. Examples of bugs that this check CANNOT detect:

- A bug in `distributeOr` (the function that splits OR-branches). Both systems use this same function.
- A bug in `extractAssignments` (the function that extracts guards and assignments from a disjunct). Both systems use this same function.

Examples of bugs that this check CAN detect:

- A wrong operator mapping (for example, using `+` instead of `-`)
- A wrong operator precedence (for example, missing parentheses)
- An assignment to the wrong variable
- A guard condition that is inverted or wrong
- Any error in the TLAValue operator overload implementations

**One-directional limit**: this check only verifies that the interpreter-to-codegen direction is correct. If the generated code can produce a state transition that the BFS graph does not include, this check cannot detect it.

### Check 4: The Invariant Cross-Check (`verifyInvariants`)

**When it runs**: at test time

**What it does**: for every reachable transition, the system:

1. Runs the native action method to get the result state
2. Uses the **interpreter** to check every invariant on that result state
3. If any invariant fails, the test fails

**What it proves**: invariants hold on states produced by the native code.

**Level of independence**: mixed. The state transition check (step 1) has the same weak independence as Check 3. But the invariant evaluation (step 2) is a genuine cross-check: the interpreter evaluates invariants on states that were produced by native code. If the native code produces a wrong state, the interpreter's invariant check will detect it.

---

## Summary of Confidence

| What we claim | What proves it | How strong is the proof |
|---|---|---|
| The specification is correct | Check 1 (`verifySpec`) | Strong. The model checker is independent of the codegen. |
| The parser and the builder agree | Check 2 (tree equivalence) | Strong. Two independent code paths produce the same AST. |
| The native code produces correct transitions | Check 3 (`verifyTransitions`) | Partial. Catches codegen bugs but not bugs in shared infrastructure. |
| Invariants hold on native-produced states | Check 4 (`verifyInvariants`) | Mixed. State check is partial, invariant check is a genuine cross-check. |

**What we do NOT claim**:

- That the codegen is free of all bugs. A bug in shared infrastructure (functions that both the codegen and the interpreter use) cannot be detected by these checks.
- That the generated code is correct for transitions outside the BFS graph. The checks only cover reachable states.
- That nondeterministic actions are verified independently. Actions with `chooseAction` or `existsAction` use the interpreter in both the codegen path and the reference path. They are tautologies in these checks.
- That the BFS graph is correct. The `transitionMatrix` function is itself code-generated. A bug in its generator would corrupt Checks 3 and 4.
- That the checks cover every action. Actions with quantifier expressions (for example, `\E x \in S: ...`) in their guards use the interpreter. They are not checked by the native code.

---

## The Complete Verification Flow

```
User writes specification (Swift DSL)
    │
    ▼
┌─────────────────────────────────┐
│ Compile-time (macro expansion)   │
│                                  │
│ 1. SpecParser reads source       │
│ 2. Model checker runs (Check 1)  │
│ 3. AST comparison (Check 2)     │
│ 4. Codegen produces natives      │
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│ Test time (swift test)          │
│                                  │
│ 5. verifySpec (Check 1 again)    │
│ 6. verifyTransitions (Check 3)   │
│ 7. verifyInvariants (Check 4)    │
└─────────────────────────────────┘
```

All checks must pass at both compile time and test time. If any check fails, the build or tests stop.

---

## How to Read a Failure

| Failure | What it means |
|---|---|
| Compile fails with an invariant violation | Your specification has an error. Fix the specification. |
| Compile fails with a parser-builder mismatch | The parser and builder disagree. This is a bug in SwiftTLA. |
| `verifyTransitions` fails | The generated code does not match the interpreter. This is a bug in the codegen. |
| `verifyInvariants` fails | An invariant is violated on a state produced by native code. This can be a codegen bug or a specification bug that Check 1 did not catch (for example, a bug outside the bounded state space). |
| `verifySpec` fails at test time | The model checker found an error in your specification. This cannot happen after compile-time checking, unless the test uses different settings. |
