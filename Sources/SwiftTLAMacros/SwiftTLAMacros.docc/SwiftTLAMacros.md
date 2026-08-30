# ``SwiftTLAMacros``

Generate typed Swift machines from a `TLASpec` declaration.

## Overview

Apply ``TLAModel()`` to a source model declaration. The generated machine
includes an `Actor` type for serialized access.

During expansion, `@TLAModel` parses the supported builder syntax into typed
source declarations, compiles them, and derives the public machine surface from
that compilation. Generated machine creation compiles `Self.spec` and requires
its `CompilationIdentity` to equal the identity recorded during expansion. A
mismatch throws `CompilationDiagnostic` before machine creation.

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
rendering and bounded checking. Generated machines compile internally before
they create typed state. A `CompilationDiagnostic` names the failed stage and
safe next action.
Use bounded exploration before you make a broader behavior claim.

## Topics

### Macros

- ``TLAModel()``
