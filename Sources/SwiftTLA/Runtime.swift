public protocol TLAMachine<Action>: Sendable, CustomStringConvertible {
    associatedtype Action: Sendable, CustomStringConvertible, Hashable
    static var initial: Self { get }
    mutating func apply(_ action: Action)
    var availableActions: [Action] { get }
}

/// A concurrency boundary around a `TLAMachine`. Serializes all action delivery.
/// Use `schedule(_:)` to apply an action and `snapshot()` to read current state.
///
/// ```swift
/// let lock = Runtime(Lock.Machine.initial)
/// await lock.schedule(.unlock)
/// ```
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
