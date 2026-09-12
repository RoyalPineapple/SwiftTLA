# ``SwiftTLAMacros``

Generate typed Swift machines from a `TLASpec` declaration.

## Overview

Apply ``TLAModel()`` to a source model declaration. The generated machine
includes an `Actor` type for serialized access.

During expansion, `@TLAModel` parses the supported builder syntax into typed
source declarations, compiles them, and derives the public machine surface from
that compilation. Generated initialization and transitions execute typed Swift
directly. The macro-parsed specification is authoritative for generated machines;
unsupported native constructs produce build-time diagnostics.

Swift-only enum metadata supplies generated Swift type names and source labels.
Transition and property meaning comes from compiled declarations.

## Supported authoring form

New application models use `#spec` and `Algorithm`. Declare shared state with
`scope.sharedVar` and process-local state with the scope supplied by `Each`.
Use `Do` for each labeled atomic step.

```swift
@TLAModel
struct Counter {
    enum Step: String, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("Counter") {
            Algorithm("Counter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)

                Do(Step.advance) {
                    When(count < 1)
                    Assign(count, to: count + 1)
                }
            })
        }
    }
}
```

`Var`, `Variable`, and `Action` are direct formal-declaration builders for
imported modules and parity fixtures. They are not an application authoring
style.

## Compiler outcomes

`try Model.spec.compile()` returns the compiled specification used by formal
rendering and bounded checking. `makeMachine()` evaluates generated initialization
and constructs typed state without compiling `Self.spec`. A `CompilationDiagnostic`
names a failed compilation stage and the next safe action.
Use bounded exploration before you make a broader behavior claim.

## Topics

### Macros

- ``TLAModel()``
