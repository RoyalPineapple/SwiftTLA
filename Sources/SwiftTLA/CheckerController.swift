/// Manually implemented BFS controller. Semantics verified by:
/// - CheckerMachine spec (Specifications/BFSExplorer/CheckerMachine.swift)
/// - CheckerSelfProofTests (11 invariants)
/// - TLA+ BFSExplorer model (Specifications/BFSExplorer/BFSExplorer.tla)
public enum CheckerPhase: Int { case exploring = 0, ok = 1, violation = 2, deadlock = 3 }

public struct CheckerController: Equatable, Hashable, Codable, Sendable, TLAMachine {
    public var phase: Int
    public var step: Int
    public var count: Int

    public init(phase: Int, step: Int, count: Int) {
        self.phase = phase; self.step = step; self.count = count
    }

    public static let initial = CheckerController(phase: 0, step: 0, count: 1)

    public enum Transition: String, CaseIterable, Identifiable, Codable, Sendable, CustomStringConvertible {
        case explore; case exploreNoNew; case finish; case violate; case deadlock
        public var id: Self { self }
        public var description: String { rawValue }
    }

    public var transitions: [(transition: Transition, target: CheckerController)] {
        switch (phase, step, count) {
        case (0, let s, let c) where s < c:
            return [(.explore, CheckerController(phase: 0, step: s+1, count: c+1)),
                    (.exploreNoNew, CheckerController(phase: 0, step: s+1, count: c))]
        case (0, let s, let c) where s >= c && c > 0:
            return [(.finish, CheckerController(phase: 1, step: s, count: c)),
                    (.deadlock, CheckerController(phase: 3, step: s, count: c))]
        case (0, _, _):
            return [(.violate, CheckerController(phase: 2, step: step, count: count))]
        default:
            return []
        }
    }

    public var availableTransitions: [Transition] { transitions.map(\.transition) }

    public mutating func apply(_ t: Transition) {
        guard let next = transitions.first(where: { $0.transition == t })?.target else { return }
        self = next
    }

    public var description: String { "p=\(phase) s=\(step) c=\(count)" }
}
