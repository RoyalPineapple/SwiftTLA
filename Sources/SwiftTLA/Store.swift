import Observation

@MainActor
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
