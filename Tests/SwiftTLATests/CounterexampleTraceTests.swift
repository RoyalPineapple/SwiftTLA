import Testing
@testable import SwiftTLA

@Suite("counterexample trace roots")
struct CounterexampleTraceTests {
    @Test("a violating initial state is its own trace root")
    func violatingInitialStateIsTraceRoot() throws {
        try expectTrace(violating: 10, values: [10], actions: ["init"])
    }

    @Test("a violation reached from a later seed retains that seed")
    func reachedViolationUsesItsActualSeed() throws {
        try expectTrace(violating: 11, values: [10, 11], actions: ["init", "advance"])
    }

    private func expectTrace(violating: Int, values: [Int], actions: [String]) throws {
        let x = Var<Int>("x")
        let spec = TLASpec("CounterexampleTrace") {
            Variable(x, in: [0, 10])
            Action("advance") { x.becomes(11).when(x == 10) }
            Invariant("safe") { x != violating }
        }
        let outcome = try ModelChecker(
            compilation: spec.compile(),
            configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)
        ).check()
        guard case .invariantViolated(_, let failing, let trace) = outcome else {
            Issue.record("Expected an invariant counterexample, got \(outcome).")
            return
        }
        #expect(try value("x", in: failing) == .int(violating))
        #expect(try trace.map { try value("x", in: $0.state) } == values.map(TLAValue.int))
        #expect(trace.map(\.action) == actions)
    }
}
