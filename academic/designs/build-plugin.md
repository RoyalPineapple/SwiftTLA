# Spec Composition Build Plugin — Design

## What it is

A Swift Package Manager build tool plugin.  Runs automatically before compilation.
Reads `@TLAActor` specs, generates composed specs.  Generated code is regular
Swift with `@TLAActor`.  Existing macro verifies it.

```
swift build
  └── ComposePlugin (build tool) — scans Sources/, generates Compositions.swift
  └── SwiftTLA (macro targets) — compiles generated code
  └── @TLAActor macros — verify generated specs at compile time
```

## How it works

SPM build plugins are established Swift tooling.  swift-protobuf reads `.proto`
files and generates Swift stubs.  SwiftGen reads asset catalogs and generates
type-safe resource accessors.  Our ComposePlugin reads `@TLAActor` specs and
generates composed specifications.  Same pattern: structured input → generated
Swift source → compiled and verified.

### Package.swift

```swift
targets: [
    .plugin(
        name: "ComposePlugin",
        capability: .buildTool(),
        dependencies: ["SwiftTLA"]
    ),
]
```

### Plugin reads child specs

```
For each file in Sources/:
  if file contains @TLAActor + spec:
    extract: name, variables, actions, invariants
    register in lookup table
```

### Plugin finds parent specs

```
For each file containing #importSpec("ChildName"):
  resolve child from lookup table
  generate composed spec:
    - copy child's variables, actions, invariants
    - apply parent's cross-actor overrides (actions with same name)
    - add parent's invariants
```

### Plugin generates code

```
Output: Sources/Generated/Compositions.swift

@TLAActor
public actor MediaContract {
    public static var spec: TLASpec {
        TLASpec("MediaContract") {
            // ── From Capture ──
            let cPhase = Var<Int>("cPhase"); Variable(cPhase, 0)
            Action("cConfigure") { cPhase == 0 && cPhase.becomes(1) }
            // ... all child actions ...

            // ── Cross-actor overrides ──
            Action("cStop") { ... wPhase guard ... }
            Action("wStart") { ... cPhase guard ... }

            // ── Cross-actor invariants ──
            Invariant("writerRequiresCapture") { ... }
        }
    }
}
```

### Developer writes

```swift
// Sources/Capture.swift
@TLAActor
public actor Capture { ... }

// Sources/Writer.swift
@TLAActor
public actor Writer { ... }

// Sources/MediaContract.swift
@TLAActor
public actor MediaContract {
    public static var spec: TLASpec {
        TLASpec("MediaContract") {
            #importSpec("Capture")    // ← plugin resolves this
            #importSpec("Writer")     // ← plugin resolves this
            // cross-actor guards
        }
    }
}
```

## Build flow

1. Build plugin runs (before compilation)
2. Plugin scans all source files for `@TLAActor` declarations
3. Plugin finds `#importSpec` references
4. Plugin generates composed spec into `Sources/Generated/`
5. Swift compiler compiles generated code + original code
6. `@TLAActor` macro verifies composed spec at compile time
7. Invariants pass → build succeeds
