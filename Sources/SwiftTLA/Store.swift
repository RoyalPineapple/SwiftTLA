import Observation

@MainActor
/// An `@Observable` wrapper around a `TLAMachine`. Publishes state changes to SwiftUI.
/// Schedule actions via `store.schedule(.action)`. Read state via `store.machine.property`.
///
/// ```swift
/// @State private var store = Store(Lock.Machine.initial)
/// Button("Lock") { store.schedule(.lock) }
///     .disabled(!store.machine.enabledActions.contains(.lock))
/// ```
@Observable
public final class Store<M: TLAMachine> {
    public private(set) var machine: M

    public init(_ machine: M = M.initial) {
        self.machine = machine
    }

    public func schedule(_ action: M.Action) {
        machine.apply(action)
        machine = machine
    }
}
