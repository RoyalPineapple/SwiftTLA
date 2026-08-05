public protocol TLAMachine<Transition>: Sendable, CustomStringConvertible {
    associatedtype Transition: Sendable, CustomStringConvertible, Hashable
    static var initial: Self { get }
    mutating func apply(_ transition: Transition)
    var availableTransitions: [Transition] { get }
}

/// A concurrency boundary around a `TLAMachine`.
public actor Runtime<M: TLAMachine> {
    private var machine: M

    public init(_ machine: M = M.initial) { self.machine = machine }

    @discardableResult
    public func schedule(_ action: M.Transition) -> M {
        machine.apply(action)
        return machine
    }

    public func snapshot() -> M { machine }
}
