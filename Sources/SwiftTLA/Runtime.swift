public protocol TLAMachine<Transition>: Sendable, CustomStringConvertible, Hashable {
    associatedtype Transition: Sendable, CustomStringConvertible, Hashable
    static var initial: Self { get }
    static var graph: TLAMachineGraph<Self> { get }
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

extension TLAMachine {
    public static var graph: TLAMachineGraph<Self> { Self.initial.exploreGraph() }

    public func explore(maxStates: Int = 10_000) -> [Self] {
        var visited: [Self] = [Self.initial]
        var head = 0
        while head < visited.count, visited.count < maxStates {
            let state = visited[head]; head += 1
            for t in state.availableTransitions {
                var next = state; next.apply(t)
                if !visited.contains(next) { visited.append(next) }
            }
        }
        return visited
    }

    public func exploreGraph(maxStates: Int = 10_000) -> TLAMachineGraph<Self> {
        var states: [Self] = [Self.initial]
        var seenIDs: Set<Self> = [Self.initial]
        var edges: [TLAMachineGraph<Self>.Edge] = []
        var head = 0
        while head < states.count, states.count < maxStates {
            let source = states[head]; head += 1
            for t in source.availableTransitions {
                var dest = source; dest.apply(t)
                if seenIDs.insert(dest).inserted { states.append(dest) }
                edges.append(TLAMachineGraph<Self>.Edge(source: source, transition: t, destination: dest))
            }
        }
        return TLAMachineGraph(nodes: states.map { TLAMachineGraph<Self>.Node(state: $0) }, edges: edges)
    }
}

public struct TLAMachineGraph<Machine: TLAMachine & Hashable>: Sendable {
    public struct Node: Identifiable, Sendable {
        public let state: Machine
        public var id: Machine { state }
        public var label: String { state.description }
    }

    public struct Edge: Identifiable, Sendable {
        public struct ID: Hashable, Sendable {
            public let source: Machine
            public let transition: Machine.Transition
            public let destination: Machine
        }
        public let source: Machine
        public let transition: Machine.Transition
        public let destination: Machine
        public var id: ID { ID(source: source, transition: transition, destination: destination) }
    }

    public let nodes: [Node]
    public let edges: [Edge]
}
