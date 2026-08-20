/// Legacy streaming was removed in favor of ``TLALiveMachine.observe()``.
/// A stream created from a value-model copy could not inspect an already
/// running machine. The live runtime is now the only supported source of
/// current state, ordered updates, and lifecycle information.
