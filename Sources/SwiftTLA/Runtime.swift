public protocol TLAMachine<Transition>: Sendable, CustomStringConvertible, Hashable {
    associatedtype Transition: Sendable, CustomStringConvertible, Hashable
    static var initial: Self { get }
    mutating func apply(_ transition: Transition)
    var availableTransitions: [Transition] { get }
}

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

public struct TLAMachineGraph<Machine: TLAMachine & Hashable>: Sendable {
    public struct Node: Identifiable, Sendable {
        public let state: Machine
        public init(state: Machine) { self.state = state }
        public var id: Machine { state }
        public var label: String { state.description }
    }

    public struct Edge: Identifiable, Sendable {
        public struct ID: Hashable, Sendable {
            public let source: Machine
            public let transition: Machine.Transition
            public let destination: Machine
            public init(source: Machine, transition: Machine.Transition, destination: Machine) {
                self.source = source; self.transition = transition; self.destination = destination
            }
        }
        public let source: Machine
        public let transition: Machine.Transition
        public let destination: Machine
        public init(source: Machine, transition: Machine.Transition, destination: Machine) {
            self.source = source; self.transition = transition; self.destination = destination
        }
        public var id: ID { ID(source: source, transition: transition, destination: destination) }
    }

    public let nodes: [Node]
    public let edges: [Edge]
    public init(nodes: [Node], edges: [Edge]) { self.nodes = nodes; self.edges = edges }
}
