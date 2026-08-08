import Foundation

// MARK: - Checkable protocol

/// A state machine that can be model-checked.
/// `TLASpec` conforms via `SpecRuntime`; custom specs can conform directly.
public protocol Checkable {
    associatedtype S: Hashable
    var actions: [String] { get }
    func initial() -> [S]
    func enabled(in state: S) -> [String]
    func successors(of action: String, from state: S) throws -> [S]
    func check(_ state: S) -> [String]
}

// MARK: - Generic BFS

/// BFS model checker — works on ANY Checkable instance.
public enum BFS {
    public static func explore<C: Checkable>(
        _ c: C,
        maxStates: Int = 100_000
    ) throws -> CheckResult {
        let initials = c.initial()
        guard !initials.isEmpty else { return .error("No initial states") }

        var queue: [C.S] = []
        var visited = Set<C.S>()
        for s in initials where !visited.contains(s) {
            visited.insert(s); queue.append(s)
        }

        var head = 0; var explored = 0
        while head < queue.count {
            guard explored < maxStates else {
                return .depthExceeded(statesCount: explored, limit: maxStates)
            }
            let current = queue[head]; head += 1; explored += 1

            let violations = c.check(current)
            if !violations.isEmpty {
                return .invariantViolated(invariant: violations[0], state: [:], trace: [])
            }

            for action in c.enabled(in: current) {
                for next in try c.successors(of: action, from: current) {
                    if !visited.contains(next) {
                        visited.insert(next); queue.append(next)
                    }
                }
            }
        }
        return .ok(statesCount: explored)
    }
}

// MARK: - TLASpec conformance

/// Wrapping TLASpec so it conforms to Checkable.
/// `SpecRuntime` provides `enabled`/`successors`/`check`.
public struct CheckableSpec<S: Hashable>: Checkable {
    public let actions: [String]
    private let runtime: SpecRuntime
    private let userActions: [NamedAction]
    private let userVarNames: [String]
    private let checkedInvariants: [NamedInvariant]
    private let initFn: () -> [[String: TLAValue]]

    public init(_ spec: TLASpec) where S == [String: TLAValue] {
        self.runtime = SpecRuntime(spec: spec)
        self.actions = spec.actions.map(\.name).filter { !$0.hasPrefix("_") }
        self.userActions = spec.actions.filter { !$0.name.hasPrefix("_") }
        self.userVarNames = spec.variables.map(\.name)
        self.checkedInvariants = spec.invariants.filter { !$0.name.hasPrefix("_") }
        self.initFn = { computeInitialStates(spec) }
    }

    public func initial() -> [[String: TLAValue]] {
        let initials = initFn()
        var deduped: [[String: TLAValue]] = []
        var seen = Set<[String: TLAValue]>()
        for s in initials where !seen.contains(s) { seen.insert(s); deduped.append(s) }
        return deduped
    }

    public func enabled(in state: [String: TLAValue]) -> [String] {
        runtime.availableActions(in: state).filter { !$0.hasPrefix("_") }
    }

    public func successors(of action: String, from state: [String: TLAValue]) throws -> [[String: TLAValue]] {
        guard let a = userActions.first(where: { $0.name == action }) else {
            throw CheckableError.actionNotFound(action)
        }
        return try ActionEnumerator.enumerate(a.body, from: state, varNames: userVarNames)
    }

    public func check(_ state: [String: TLAValue]) -> [String] {
        checkedInvariants.compactMap { inv in
            (try? inv.body.evaluateBool(in: state)) == false ? inv.name : nil
        }
    }

    enum CheckableError: Error { case actionNotFound(String) }
}

// MARK: - RuntimeChecker (spec-based checker lifecycle)

/// The checker lifecycle as a TLASpec — verified by @TLAModel.
/// Composed with any user spec via `extending()`.
public struct RuntimeChecker {
    public let spec: TLASpec
    public let maxStates: Int

    public static func lifecycle(maxStates: Int) -> TLASpec {
        let phase = Var<Int>("_phase")
        let explored = Var<Int>("_explored")
        let queued = Var<Int>("_queued")
        return TLASpec("RuntimeChecker") {
            Variable(phase, 0); Variable(explored, 0); Variable(queued, 1)
            Action("_Step") {
                (phase == 0) && (explored < queued) && (explored < maxStates)
                    && explored.becomes(explored + 1)
                    && queued.stays && phase.stays
            }
            Action("_StepNew") {
                (phase == 0) && (explored < queued) && (explored < maxStates)
                    && explored.becomes(explored + 1)
                    && queued.becomes(queued + 1) && phase.stays
            }
            Action("_Complete") {
                (phase == 0) && (explored >= queued || explored >= maxStates)
                    && phase.becomes(1)
            }
            Invariant("_PhaseValid") { phase >= 0 && phase <= 1 }
        }
    }

    public init(userSpec: TLASpec, maxStates: Int = 100_000) {
        self.spec = Self.lifecycle(maxStates: maxStates).extending(userSpec)
        self.maxStates = maxStates
    }

    /// Check using generic BFS algorithm.
    public func check() throws -> CheckResult {
        let checkable = CheckableSpec(spec)
        return try BFS.explore(checkable, maxStates: maxStates)
    }
}
