# Example architecture

Examples must use SwiftTLA as the behavioral source of truth.

- Put formal state, legal transitions, and invariants in a `TLASpec`.
- Use a generated machine or generated `Actor` for executable state.
- Keep SwiftUI and Apple framework code as thin event and rendering adapters.
- Do not duplicate formal state in `@State`, delegates, view models, timers,
  or ad-hoc schedulers.
- Do not independently decide whether a transition is legal in the adapter.
  Dispatch the generated action and render its generated transition.
- Do not add an imperative fallback for DSL behavior the model cannot yet
  express. Extend the typed DSL and test parser, builder, emitted TLA, and
  runtime fidelity instead.
- Keep concrete platform handles at the edge, mapped by a typed formal ID.
- Keep generated verification checks in Swift tests beside the model.
