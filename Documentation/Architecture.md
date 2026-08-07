# SwiftTLA Architecture

## System Flow

```mermaid
graph TD
    subgraph "Compile Time"
        DSL["Swift DSL Source<br/>@TLAModel struct { spec: TLASpec { ... } }"]
        DSL --> PARSER["SpecParser.parseSpecClosure()<br/>StateMethod / TemporalMethod / FairnessMethod enums"]
        PARSER --> MACRO["ModelMacro.expansion()<br/>→ ParsedSpecComponents"]
        MACRO --> SPEC["TLASpec(name, variables, actions, invariants, ...)"]
        SPEC --> SELFCHECK["ModelChecker.check()<br/>compile-time BFS"]
        SELFCHECK -->|"pass"| EMIT["emit: public static var runtime: SpecRuntime"]
        SELFCHECK -->|"fail"| ERROR["compile error with trace"]
    end

    subgraph "Data Types"
        SE["StateExpr<br/>50 cases<br/>value, variable, add, equal, and,<br/>setLiteral, tupleHead, forAll, choose,<br/>recordAccess, functionApply, except,<br/>sequenceFromSet, setSum, recursiveCall, ..."]
        AE["ActionExpr<br/>8 cases<br/>assign, unchanged, guard_,<br/>chooseAction, existsAction,<br/>ifElse, and, or"]
        TV["TLAValue<br/>8 cases<br/>int, bool, string, set,<br/>tuple, record, function, constant"]
        SG["StateGraph<br/>states: [ID → State]<br/>transitions: [ID → [Transition]]"]
        AE --> SE
    end

    TLASPEC["TLASpec<br/>variables, actions, invariants,<br/>constants, constraint, assume,<br/>recursiveDefs, recursiveFuncs,<br/>fairness, temporalProperties"]
    TLASPEC --> SE
    TLASPEC --> AE
    TLASPEC --> TV

    subgraph "ModelChecker BFS"
        SUB["substituteConstants(spec)<br/>inline CONSTANT values"]
        INIT["computeInitialStates()<br/>nondeterministic sets → cartesian product<br/>then apply initExpr computations"]
        BFS["BFS Loop<br/>queue-based, visited set"]
        EXPAND["buildExpander: for each action:<br/>ActionEnumerator.enumerate()<br/>→ filter successors by constraint"]
        PDIS["processDisjunct()<br/>1. expand existsAction (substitute + distOr)<br/>2. expand chooseAction (cartesian product)<br/>3. extractAssignments + guards"]
        DIST["distOr()<br/>distribute OR over AND<br/>ifElse → guard-then, guard-else"]
        EVAL["Evaluator.evaluate()<br/>recursive StateExpr interpreter<br/>substituteVariable for bound vars (_x)"]
        CHECK["check invariants<br/>Evaluator.evaluateBool()"]
        RESULT["CheckResult<br/>.ok | .invariantViolated<br/>.deadlocked | .depthExceeded | .error"]
        GRAPH["StateGraph<br/>states + transitions from BFS"]

        TLASPEC --> SUB --> INIT --> BFS
        BFS --> EXPAND --> AE["ActionEnumerator.enumerate()"]
        AE --> DIST --> PDIS --> EVAL
        BFS --> CHECK --> EVAL
        BFS --> RESULT --> GRAPH
    end

    subgraph "Interactive Runtime"
        SR["SpecRuntime<br/>init(spec:) → wraps ActionEnumerator + Evaluator"]
        STEP["step(actionName, from: state)<br/>availableActions → apply → check"]
        APPLY["apply(actionName, to: state)<br/>ActionEnumerator.enumerate()"]
        AVAIL["availableActions(in: state)<br/>try-enumerate, return enabled names"]

        TLASPEC --> SR
        SR --> STEP --> APPLY --> AVAIL
        APPLY --> AE
        STEP --> EVAL
    end

    subgraph "Export"
        TLA["tlaModule<br/>→ TLA+ source with SANY-compatible syntax<br/>CONSTANTS, ASSUME, RECURSIVE,<br/>Invariants, Init, Actions, Spec"]
        BAS["base64JSON<br/>→ RoundTrip test serialization"]
        TLASPEC --> TLA
        TLASPEC --> BAS
    end

    subgraph "Self-Proof"
        BFSGEN["bfsChecker(maxStates:)<br/>generates lifecycle spec"]
        BFSCK["@TLAModel struct BFSChecker<br/>hardcoded maxStates=20"]
        BFSGEN --> MACRO
        BFSCK --> MACRO
    end

    subgraph "Upstream Parity"
        EX["Example.all: 27 entries<br/>id, expectedDistinct, spec"]
        PARITY["UpstreamParityTests<br/>ModelChecker.exploreGraph().states.count<br/>== expectedDistinct<br/>+ ModelChecker.check() == .ok"]
        EX --> PARITY --> GRAPH
    end
```

## Component Inventory

| Component | File | Input | Output |
|-----------|------|-------|--------|
| `StateExpr` | StateExpr.swift | — | 50-case expression AST |
| `ActionExpr` | ActionExpr.swift | — | 8-case action AST |
| `TLAValue` | TLAValue.swift | — | 8-case runtime value |
| `Var<T>` | Var.swift | name | `.becomes`, `.stays`, `@dynamicMemberLookup` |
| `TLASpec` | TLASpec.swift | DSL builder | immutable spec struct |
| `Evaluator` | Evaluator.swift | StateExpr + state | TLAValue |
| `ActionEnumerator` | ActionEnumerator.swift | ActionExpr + state | [[String: TLAValue]] |
| `ModelChecker` | ModelChecker.swift | TLASpec | CheckResult + StateGraph |
| `SpecRuntime` | SpecRuntime.swift | TLASpec | StepResult |
| `SpecParser` | SpecParser.swift | SwiftSyntax AST | DSL types + ParsedSpecComponents |
| `ModelMacro` | ModelMacro.swift | struct source | extension + runtime property |
| `PrettyPrint` | TLASpec+PrettyPrint.swift | TLASpec | .tla string |
| `StateGraph` | StateGraph.swift | BFS data | states + transitions |

## Found Issues

1. **`ComputedInitDecl` dead code.** The `for comp in components` loop in `TLASpec`'s builder init has no handler for `ComputedInitDecl`. Created by `ComputedVariable()`, never converted to a `NamedVar`.

2. **`SymmetryDecl` dead code.** Same issue — no handler in builder loop. `SymmetrySet.canonicalize()` exists but `canonicalKey` is identity.

3. **Duplicate initial state computation.** `ModelChecker.computeInitialStates()` and `SpecRuntime.computeInitialStateMaps()` are identical (~20 lines each). Changes risk divergence.

4. **`substituteConstants` skips temporal properties.** Constants are inlined in variables, actions, invariants, assume, constraint — but `temporalProperties` passes through unsubstituted.

5. **Two OR-distribution algorithms.** `ActionEnumerator.distOr()` and `completeAction`'s `distributeActionOr()` are near-duplicates. The differs: `distributeActionOr` wraps existAction on each branch; `distOr` delegates expansion to `processDisjunct`.

6. **`Var.init` ignores the `value` parameter.** `init(_ name: String? = nil, value: T? = nil)` stores only `name`. The `value` parameter is unused. Intentional (init values go through `Variable()`) but misleading.

→ Fix by removing the `value` parameter from Var.init or adding a deprecation warning. Actually, Var is `@_disfavoredOverload`, but the `value` arg should just be removed since it's never stored.

7. **`SpecBuilder` missing overloads.** `buildExpression` is defined for `ComputedInitDecl` and `SymmetryDecl` at lines 226-227, but these components are never consumed in the builder init loop (see #1, #2).

→ Fix by adding handlers in the `for comp in components` loop, or remove the unused types.

8. **`Evaluator.substituteVariable` doesn't handle `.recursiveCall` args.** `recursiveCall` passes through but its args could reference the bound variable being substituted.
