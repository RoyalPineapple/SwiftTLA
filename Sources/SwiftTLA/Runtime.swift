public protocol TLAMachine<Action>: Sendable {
    associatedtype Action: Sendable
    static var initial: Self { get }
    mutating func apply(_ action: Action)
}

public actor Runtime<M: TLAMachine> {
    private var machine: M

    public init(_ machine: M = M.initial) { self.machine = machine }

    @discardableResult
    public func schedule(_ action: M.Action) -> M {
        machine.apply(action)
        return machine
    }

    public func snapshot() -> M { machine }
}
