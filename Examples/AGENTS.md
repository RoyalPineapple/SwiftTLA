# Example architecture

Examples must use SwiftTLA as the behavioral source of truth.

- Put formal state, legal transitions, and invariants in a `TLASpec`.
- Use a generated machine or generated `Actor` for executable state.
- Keep SwiftUI and Apple framework code as thin event and rendering adapters.
- Keep formal state solely in the generated machine; `@State`, delegates, view
  models, timers, and ad-hoc schedulers retain only platform state.
- Delegate transition legality to the generated machine. Dispatch the
  generated action and render its generated transition.
- Extend the typed DSL for new behavior and test parser, builder, emitted TLA,
  and compiled-runtime fidelity together.
- Keep concrete platform handles at the edge, mapped by a typed formal ID.
- Keep generated verification checks in Swift tests beside the model.
