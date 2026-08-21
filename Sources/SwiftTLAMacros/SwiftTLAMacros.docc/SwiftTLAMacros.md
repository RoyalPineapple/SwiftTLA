# ``SwiftTLAMacros``

Generate typed Swift machines from a `TLASpec` declaration.

## Overview

Apply ``TLAModel()`` to a model declaration. Nest ``TLAActor()`` or
``TLAObservable()`` inside that declaration when an actor or observable adapter
is required.

The macro parses the supported builder syntax, lowers it once to `TLASpec`,
compiles that model, and generates the public machine surface described in the
`SwiftTLA` DocC catalog. After lowering, `TLASpec` is the only formal semantic
model. Swift-only facts provide generated Swift type names and source labels.
They do not contain a second action or invariant representation.

## Supported authoring form

New application models use `#spec` and `Algorithm`. Use `SharedVar` for shared
state. Use `LocalVar` inside `Each` for process-local state. Use `Do` for each
labeled atomic step.

```swift
@TLAModel
struct Counter {
    enum Process: Int, FiniteDomainKey {
        case worker = 1

        static let formalDomain: [Self] = [.worker]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "docs.counter.process")
    }

    enum Step: String, PlusCalLabel, CaseIterable {
        case advance
    }

    static var spec: TLASpec {
        #spec("Counter") {
            Algorithm("Counter") {
                let count = SharedVar(initial: 0)

                Each(Process.all) { _ in
                    let attempts = LocalVar(initial: 0)

                    Do(Step.advance) {
                        When(count < 1)
                        Assign(count, to: count + 1)
                        Assign(attempts, to: attempts + 1)
                    }
                }
            }
        }
    }
}
```

`Var`, `Variable`, and `Action` remain formal-core tools for imported modules
and parity fixtures. They are not a second application authoring style.

## Compiler outcomes

`try Model.spec.compile()` returns the compiled specification used by formal
rendering and bounded checking. Generated machines compile internally before
they create typed state. A `CompilationDiagnostic` names the failed stage and
safe next action.
`SwiftTLA` before you make a broader behavior claim.

## Topics

### Macros

- ``TLAModel()``
- ``TLAActor()``
- ``TLAObservable()``
