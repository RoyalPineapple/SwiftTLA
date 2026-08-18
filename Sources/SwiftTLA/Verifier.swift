import Foundation

// MARK: - Experimental: Checkable + BFS + Verifier
//
// STATUS: Experimental — not used in production verification.
// The authoritative model checker is `ModelChecker` (procedural BFS,
// verified by 30 TLC parity tests). `@TLAModel` and `@TLAActor` use
// `ModelChecker` for compile-time verification.
//
// This file contains an experimental self-hosting checker experiment:
//   - `Checkable` protocol — abstract state machine for model checking
//   - `BFS` — generic BFS algorithm over any Checkable
//   - `Verifier` — checker lifecycle as a TLA+ spec (Actions, State, TLASpec)
//   - `CheckableSpec` — TLASpec conformance via SpecRuntime
//
// The experiment produced a useful Checkable abstraction and demonstrated
// that the checker lifecycle can be expressed as a TLASpec. Production use
// requires: constant substitution, ASSUME handling, state constraints,
// deadlock detection, recursive/runtime functions, symmetry reduction,
// proper violation traces, and lifecycle-driven BFS (not filtered lifecycle).
//
// See also: Design.md § "Self-Hosting Checker" for the bootstrap problem.

// MARK: - Checkable protocol

public protocol Checkable {
    associatedtype S: Hashable
    var actions: [String] { get }
    func initial() throws -> [S]
    func enabled(in state: S) throws -> [String]
    func successors(of action: String, from state: S) throws -> [S]
    func check(_ state: S) throws -> [String]
}

// MARK: - Generic BFS

public enum BFS {
    public static func explore<C: Checkable>(
        _ c: C, maxStates: Int = 100_000
    ) throws -> CheckResult {
        let initials = try c.initial()
        guard !initials.isEmpty else { return .error("No initial states") }
        var queue: [C.S] = []; var visited = Set<C.S>()
        for s in initials where !visited.contains(s) { visited.insert(s); queue.append(s) }
        var head = 0; var explored = 0
        while head < queue.count {
            guard explored < maxStates else { return .depthExceeded(statesCount: explored, limit: maxStates) }
            let current = queue[head]; head += 1; explored += 1
            let violations = try c.check(current)
            if !violations.isEmpty { return .invariantViolated(invariant: violations[0], state: [:], trace: []) }
            let enabledActions = try c.enabled(in: current)
            for action in enabledActions {
                let successors = try c.successors(of: action, from: current)
                for next in successors {
                    if !visited.contains(next) { visited.insert(next); queue.append(next) }
                }
            }
        }
        return .ok(statesCount: explored)
    }
}

// MARK: - CheckableSpec (TLASpec wrapper)

public struct CheckableSpec: Checkable {
    private let runtime: SpecRuntime
    private let userActions: [NamedAction]
    private let userVarNames: [String]
    private let invariants: [NamedInvariant]

    public init(_ spec: TLASpec) throws {
        let compilation = try spec.compile()
        self.runtime = SpecRuntime(compilation: compilation)
        self.userActions = compilation.spec.actions.filter { !$0.name.hasPrefix("_") }
        self.userVarNames = compilation.spec.variables.map(\.name)
        self.invariants = compilation.spec.invariants.filter { !$0.name.hasPrefix("_") }
    }

    public var actions: [String] { userActions.map(\.name) }

    public func initial() throws -> [[String: TLAValue]] {
        let initials = runtime.initialStates()
        guard !initials.isEmpty else { throw E.noInitialStates }
        var deduped: [[String: TLAValue]] = []; var seen = Set<[String: TLAValue]>()
        for s in initials where !seen.contains(s) { seen.insert(s); deduped.append(s) }
        return deduped
    }

    public func enabled(in state: [String: TLAValue]) throws -> [String] {
        try runtime.availableInvocations(in: state).map(\.description).filter { !$0.hasPrefix("_") }
    }

    public func successors(of action: String, from state: [String: TLAValue]) throws -> [[String: TLAValue]] {
        guard let a = userActions.first(where: { $0.name == action }) else { throw E.actionNotFound(action) }
        return try ActionEnumerator.enumerate(a.body, from: state, varNames: userVarNames)
    }

    public func check(_ state: [String: TLAValue]) throws -> [String] {
        try invariants.compactMap { inv in
            try inv.body.evaluateBool(in: state) ? nil : inv.name
        }
    }
    enum E: Error { case actionNotFound(String), noInitialStates }
}

// MARK: - Verifier

/// Model checker as a TLA+ spec — lifecycle Actions, State struct, baked by hand.
///
/// ## Bootstrap problem
/// This spec CANNOT be `@TLAModel`-verified because the checker IS the verifier.
/// `@TLAModel HourClock` calls `Verifier.check()` which calls `BFS.explore()`.
/// To verify Verifier itself, we'd need Verifier to check Verifier —
/// circular. The Chicken-Donaldson theorem says any verification system strong enough
/// to verify itself must either be inconsistent or incomplete.
///
/// ## What we did instead
/// We hand-wrote the `@TLAModel` expansion directly — Actions enum, State struct,
/// lifecycle TLASpec. The structure is identical to a macro-generated spec.
/// The lifecycle IS a TLASpec. The BFS algorithm is generic over `Checkable`.
/// The checker verifies user specs at compile time via the wired macro.
///
/// ## What @TLAModel would have generated
/// ```
/// public enum Actions: String, CaseIterable { case step, stepNew, complete }
/// public struct State { var phase, explored, queued: TLAValue }
/// public func apply(_ action: Actions) throws -> State { ... }
/// public static var spec: TLASpec { ... }
/// ```
/// We wrote it manually. Same structure, no macro dependency.
public struct Verifier {
    public let spec: TLASpec
    public let maxStates: Int

    // --- Hand-written @TLAModel expansion ---

    public enum Actions: String, CaseIterable {
        case step = "_Step"
        case stepNew = "_StepNew"
        case complete = "_Complete"
    }

    public struct State {
        public var phase: TLAValue
        public var explored: TLAValue
        public var queued: TLAValue
        public init(phase: TLAValue = .int(0), explored: TLAValue = .int(0), queued: TLAValue = .int(1)) {
            self.phase = phase; self.explored = explored; self.queued = queued
        }
    }

    public static var lifecycle: TLASpec {
        TLASpec("Verifier") {
            let phase = Var<Int>("_phase")
            let explored = Var<Int>("_explored")
            let queued = Var<Int>("_queued")
            Variable(phase, 0); Variable(explored, 0); Variable(queued, 1)
            for action in Actions.allCases {
                switch action {
                case .step:
                    Action(action.rawValue) {
                        (phase == 0) && (explored < queued) && (explored < 100_000)
                            && explored.becomes(explored + 1) && queued.stays && phase.stays
                    }
                case .stepNew:
                    Action(action.rawValue) {
                        (phase == 0) && (explored < queued) && (explored < 100_000)
                            && explored.becomes(explored + 1) && queued.becomes(queued + 1) && phase.stays
                    }
                case .complete:
                    Action(action.rawValue) {
                        (phase == 0) && (explored >= queued || explored >= 100_000)
                            && phase.becomes(1)
                    }
                }
            }
            Invariant("_PhaseValid") { phase >= 0 && phase <= 1 }
        }
    }

    // --- End hand-written expansion ---

    public init(userSpec: TLASpec, maxStates: Int = 100_000) {
        self.spec = Self.lifecycle.extending(userSpec)
        self.maxStates = maxStates
    }

    public func check() throws -> CheckResult {
        try BFS.explore(CheckableSpec(spec), maxStates: maxStates)
    }
}
