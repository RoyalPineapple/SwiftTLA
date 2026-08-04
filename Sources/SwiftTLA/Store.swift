import Observation

@MainActor
@Observable
public final class Store<M: TLAMachine> {
    private var machine: M
    public private(set) var state: M

    public init(_ machine: M = M.initial) {
        self.machine = machine
        self.state = machine
    }

    public func schedule(_ action: M.Action) {
        machine.apply(action)
        state = machine
    }
}
