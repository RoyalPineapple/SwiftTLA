# SwiftTLA Architecture

## System Flow

```mermaid
graph TD
    subgraph Compile["Compile Time"]
        direction TB
        DSL["@TLAModel struct { var spec: TLASpec { ... } }"]
        PARSER["SpecParser.parseSpecClosure()<br/>→ ParsedSpecComponents<br/>variables, actions, invariants, constants, temporal, fairness"]
        SPEC["TLASpec init<br/>14 SpecComponent types handled<br/>auto-UNCHANGED via completeAction"]
        CHECK["ModelChecker.check()<br/>maxStates=10k, BFS"]
        EMIT["emit: runtime property"]
        DSL --> PARSER --> SPEC --> CHECK -->|pass| EMIT
        CHECK -->|fail| ERROR["compile error + invariant trace"]
    end

    subgraph Data["Data Types"]
        SE["StateExpr — 51 cases<br/>value, variable, arithmetic(7), comparison(6), logic(4), ifThenElse,<br/>sets(11), tuples(7), records/functions(6), quantifiers(4), enabledAction,<br/>sequenceFromSet, setSum, recursiveCall"]
        AE["ActionExpr — 8 cases<br/>assign, unchanged, guard_, chooseAction, existsAction, ifElse, and, or"]
        TV["TLAValue — 8 cases<br/>int, bool, string, set, tuple, record, function, constant"]
        AE --> SE
    end

    subgraph BFS["ModelChecker BFS"]
        direction TB
        SUB["substituteConstants()<br/>inlines CONSTANT values<br/>also handles temporals via substituteInTemporal"]
        INIT["computeInitialStates()<br/>shared between ModelChecker + SpecRuntime<br/>nondet sets → cartesian → initExpr"]
        LOOP["BFS loop: queue, visited set"]
        EXPAND["buildExpander:<br/>for each action: ActionEnumerator.enumerate()<br/>→ filter successors by constraint (Evaluator)"]
        DIST["distributeOr()<br/>single canonical function<br/>or→split, and→distribute, ifElse→guard+split, exists→pushInto"]
        PDIS["processDisjunct()<br/>1. extractExistsActions → expand<br/>2. extractChooseActions → cartesian<br/>3. extractAssignments + guards → evaluate → new state"]
        EVAL["Evaluator.evaluate()<br/>recursive interpreter for all 51 cases<br/>substituteVariable for _x binding<br/>recursiveCall: Sum + SeqFromSet builtins"]
        INV["check invariants<br/>Evaluator.evaluateBool()"]
        RESULT["CheckResult<br/>.ok | .invariantViolated | .deadlocked | .depthExceeded | .error"]
        GRAPH["StateGraph<br/>states + transitions + variableNames"]

        SUB --> INIT --> LOOP --> EXPAND --> DIST --> PDIS --> EVAL
        LOOP --> INV --> EVAL
        LOOP --> RESULT --> GRAPH
    end

    subgraph Runtime["Interactive Runtime"]
        direction TB
        SR["SpecRuntime<br/>init(spec:)<br/>initialStates(), apply(actionName:to:),<br/>availableActions(in:), check(_:in:), step(_:from:)"]
        SR --> AE2["ActionEnumerator.enumerate()"]
        SR --> EVAL2["Evaluator.evaluateBool()"]
    end

    subgraph Export["Export"]
        TLA["tlaModule<br/>→ TLA+ source<br/>1. MODULE 2. EXTENDS 3. CONSTANTS/ASSUME<br/>4. VARIABLES 5. definitions/recursive<br/>6. invariants 7. constraint 8. Init<br/>9. actions 10. Next 11. Spec 12. temporal 13. THEOREM"]
        TLASPEC["TLASpec"] --> TLA
    end

    subgraph Parity["Upstream Parity"]
        EX["Example.all: 27 entries<br/>id, upstreamModule, expectedDistinct, spec"]
        RUN["ModelChecker.exploreGraph().states.count == expectedDistinct<br/>+ make parity: TLC via tlaModule"]
        EX --> RUN
    end

    subgraph Self["Self-Proof"]
        BFSGEN["TLASpec.bfsChecker(maxStates:)<br/>generates BFS lifecycle spec"]
        BFSCK["@TLAModel struct BFSChecker<br/>hardcoded maxStates=20"]
        BFSGEN --> CHECK
        BFSCK --> CHECK
    end
```

## Component Inventory

| Component | File | Input | Output |
|-----------|------|-------|--------|
| `StateExpr` | StateExpr.swift | — | 51-case expression AST |
| `ActionExpr` | ActionExpr.swift | — | 8-case action AST |
| `TLAValue` | TLAValue.swift | — | 8-case runtime value |
| `Var<T>` | Var.swift | name | `.becomes`, `.stays`, `@dynamicMemberLookup` |
| `TLASpec` | TLASpec.swift | DSL builder | immutable spec with 14 component types |
| `Evaluator` | Evaluator.swift | StateExpr + state | TLAValue |
| `ActionEnumerator` | ActionEnumerator.swift | ActionExpr + state | successor states |
| `ModelChecker` | ModelChecker.swift | TLASpec | CheckResult + StateGraph |
| `SpecRuntime` | SpecRuntime.swift | TLASpec | StepResult (6 methods) |
| `SpecParser` | SpecParser.swift | SwiftSyntax | DSL types (7 public methods) |
| `ModelMacro` | ModelMacro.swift | struct source | extension + runtime property |
| `PrettyPrint` | TLASpec+PrettyPrint.swift | TLASpec | .tla string (13-step generation) |
| `distributeOr` | TLASpec+PrettyPrint.swift | ActionExpr | [[ActionExpr]] disjuncts |
| `completeAction` | TLASpec+PrettyPrint.swift | ActionExpr + vars | completed ActionExpr with per-branch UNCHANGED |
| `computeInitialStates` | TLASpec.swift | TLASpec | [[String: TLAValue]] |
| `substituteConstants` | TLASpec.swift | TLASpec | TLASpec with constants inlined |

## Package Structure

```
SwiftTLA (library)
├── SwiftParser, SwiftBasicFormat, SwiftSyntaxBuilder (swift-syntax 600)
│
├── SwiftTLAPlugin (macro)
│   └── SwiftTLA, SwiftCompilerPlugin, SwiftSyntax, SwiftSyntaxMacros
│
├── SwiftTLAMacros (library)
│   └── @attached(member) @attached(extension) macro TLAModel
│
├── SwiftTLAModels (library)
│   └── BFSChecker (@TLAModel), BFSExplorer
│
├── UpstreamParity (library)
│   └── Example.all + 27 port files
│
├── tlc-validate (executable)
│   └── emits .tlaModule for parity validation
│
└── SwiftTLATests (tests)
    └── 133 tests in 30 suites
```

## All Issues Resolved

| # | Issue | Resolution |
|---|-------|-----------|
| 1 | ComputedInitDecl dead code | Removed |
| 2 | SymmetryDecl dead code | Removed |
| 3 | Duplicate init state computation | Extracted shared `computeInitialStates()` |
| 4 | substituteConstants skipped temporals | Added `substituteInTemporal` |
| 5 | Two OR-distribution algorithms | Consolidated to single `distributeOr` |
| 6 | Var.init `value:` parameter | Intentional — type documentation |
| 7 | recursiveCall in substituteVariable | Already handled |
| 8 | SpecBuilder missing overloads | Removed with dead types |

## State (2026-08-07)

- **25/25** TLC parity
- **133** tests in **30** suites
- **51** StateExpr cases, **8** ActionExpr cases, **8** TLAValue cases
- **27** upstream parity ports
- **14** SpecComponent types handled by builder init
