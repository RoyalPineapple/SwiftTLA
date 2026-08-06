/// BFS model checker state machine. Bounded by a `limit` — the checker
/// stops processing when `processed >= limit`, mirroring the TLA+ pattern
/// `CONSTANT MaxExplore / Cardinality(explored) < MaxExplore`.
///
/// Generated from the DSL spec in CheckerModel.swift; regenerate there.
public struct CheckerController: Equatable, Hashable, Codable, Sendable, TLAMachine {
    public static let phaseExploring  = 0
    public static let phaseComplete   = 1
    public static let phaseViolated   = 2
    public static let phaseDeadlocked = 3

    public var phase: Int
    public var processed: Int
    public var queued: Int
    public var limit: Int

    public var isExploring:  Bool { phase == Self.phaseExploring }
    public var isComplete:   Bool { phase == Self.phaseComplete }
    public var isViolated:   Bool { phase == Self.phaseViolated }
    public var isDeadlocked: Bool { phase == Self.phaseDeadlocked }

    public init(phase: Int = Self.phaseExploring, processed: Int = 0, queued: Int = 1, limit: Int = 100) {
        self.phase = phase
        self.processed = processed
        self.queued = queued
        self.limit = limit
    }

    public static func initial(limit: Int = 100) -> CheckerController {
        CheckerController(phase: phaseExploring, processed: 0, queued: 1, limit: limit)
    }

    public static let initial = CheckerController(phase: phaseExploring, processed: 0, queued: 1, limit: 100)

    public enum Transition: String, CaseIterable, Identifiable, Codable, Sendable, CustomStringConvertible {
        case stepDiscover
        case stepNoNew
        case complete
        case violate
        case deadlock
        public var id: Self { self }
        public var description: String { rawValue }
    }

    public var transitions: [(action: Transition, target: Self)] {
        let canProcess = processed < queued && processed < limit

        switch phase {
        case Self.phaseExploring where canProcess:
            return [
                (.stepDiscover, CheckerController(phase: Self.phaseExploring, processed: processed + 1, queued: queued + 1, limit: limit)),
                (.stepNoNew,   CheckerController(phase: Self.phaseExploring, processed: processed + 1, queued: queued,     limit: limit)),
            ]
        case Self.phaseExploring where processed >= queued && queued > 0 && processed < limit:
            return [
                (.complete, CheckerController(phase: Self.phaseComplete, processed: processed, queued: queued, limit: limit)),
                (.deadlock, CheckerController(phase: Self.phaseDeadlocked, processed: processed, queued: queued, limit: limit)),
            ]
        case Self.phaseExploring where processed >= limit:
            return [
                (.complete, CheckerController(phase: Self.phaseComplete, processed: processed, queued: queued, limit: limit)),
            ]
        case Self.phaseExploring where queued == 0:
            return [
                (.violate, CheckerController(phase: Self.phaseViolated, processed: processed, queued: queued, limit: limit)),
            ]
        default:
            return []
        }
    }

    public var availableTransitions: [Transition] { transitions.map { $0.action } }
    public var enabledTransitions: [Transition] { availableTransitions }

    public mutating func apply(_ transition: Transition) {
        guard let next = transitions.first(where: { $0.action == transition })?.target else { return }
        self = next
    }

    public var description: String { "phase=\(phase) p=\(processed) q=\(queued) L=\(limit)" }
}
