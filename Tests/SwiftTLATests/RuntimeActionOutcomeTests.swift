import Testing
@testable import SwiftTLA

@Suite("Runtime action outcomes")
struct RuntimeActionOutcomeTests {
    private let state: [String: TLAValue] = ["x": .int(0)]

    @Test("enabled actions retain their successors")
    func enabledAction() throws {
        let runtime = try runtime(action: .assign("x", .value(.int(1))))
        let successors: [[String: TLAValue]] = [["x": .int(1)]]

        #expect(runtime.actionOutcome(named: "Next", in: state) == .enabled(
            actionName: "Next", successors: successors))
    }

    @Test("disabled actions are distinct from evaluation failures")
    func disabledAction() throws {
        let runtime = try runtime(action: .guard_(.value(.bool(false))))

        #expect(runtime.actionOutcome(named: "Next", in: state) == .disabled(actionName: "Next"))
    }

    @Test("unknown actions report action not found")
    func actionNotFound() throws {
        let runtime = try runtime(action: .assign("x", .value(.int(1))))

        #expect(runtime.actionOutcome(named: "Missing", in: state) == .actionNotFound(actionName: "Missing"))
    }

    @Test("throwing action evaluation never becomes disabled")
    func actionEvaluationFailure() throws {
        let runtime = try runtime(action: .and(
            .assign("x", .value(.int(1))),
            .assign("x", .value(.int(2)))))

        #expect(runtime.actionOutcome(named: "Next", in: state) == .evaluationFailed(
            actionName: "Next",
            diagnostic: .init(code: .actionError, message: "Variable 'x' is assigned multiple times in one action branch")))
    }

    @Test("unavailable action evaluation remains explicit")
    func actionEvaluationUnavailable() throws {
        let runtime = try runtime(
            action: .assign("x", .value(.int(1))),
            actionEvaluator: { _, _, _ in throw SpecRuntime.RuntimeError.evaluationUnavailable("evaluator offline") })

        #expect(runtime.actionOutcome(named: "Next", in: state) == .evaluationUnavailable(
            actionName: "Next",
            diagnostic: .init(code: .evaluatorUnavailable, message: "evaluator offline")))
    }

    @Test("action reports retain safe state and explain an unavailable guard")
    func actionReportExplainsUnavailableAction() throws {
        let runtime = try runtime(action: .guard_(.value(.bool(false))))

        let report = runtime.actionReport(named: "Next", in: state)
        let xToken = try #require(TLAStateProjection.Token(validating: "x"))

        #expect(report.requested == .init(name: "Next"))
        #expect(report.stateCommitted == false)
        #expect(report.state.projection?.value(for: xToken) == .int(0))
        #expect(report.availability == .known([]))
        #expect(report.status == .unavailable(
            expected: "the guard for Next to be true",
            actual: "the action produced no successor from this state"
        ))
        #expect(report.nextSafeAction.contains("available actions"))
    }

    private func runtime(
        action: ActionExpr,
        actionEvaluator: SpecRuntime.ActionEvaluator? = nil
    ) throws -> SpecRuntime {
        let x = Var<Int>("x")
        let spec = TLASpec("RuntimeActionOutcome") {
            Variable(x, 0)
            Action("Next") { action }
        }
        if let actionEvaluator {
            return try SpecRuntime(spec: spec, actionEvaluator: actionEvaluator)
        }
        return try SpecRuntime(spec: spec)
    }
}
