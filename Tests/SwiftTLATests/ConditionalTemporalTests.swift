import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ConditionalTemporalTests {
    private typealias Condition = TemporalCondition<@Sendable (Int) throws -> Bool>
    private enum PredicateError: Error { case evaluated }

    private func checker() -> LivenessChecker<Int, Int, Int> {
        let transitions = [0: [2], 1: [2]]
        return .init(states: [0, 1, 2], transitions:
            Dictionary(uniqueKeysWithValues: transitions.map { source, targets in
                (source, targets.map { GraphEdge(source: source, action: 0, target: $0) })
            }),
            fairness: [], matches: { $0 == $1 }, actionOrder: { $0 < $1 }, stateOrder: { $0 < $1 })
    }

    @Test("conditional properties select each initial state's branch across merged paths")
    func retainsInitialBranch() throws {
        let condition = Condition.conditional({ $0 == 0 },
            then: .eventually { $0 == 0 }, else: .eventually { $0 == 1 })
        let result = try checker().analyze(condition, initialStates: [0, 1], renderScope: String.init)
        #expect(result.status == .satisfied)
    }

    @Test("a conditional counterexample starts in the initial state that selected its branch")
    func retainsWitnessOrigin() throws {
        let condition = Condition.conditional({ $0 == 0 },
            then: .eventually { $0 == 1 }, else: .eventually { $0 == 1 })
        let result = try checker().analyze(condition, initialStates: [0, 1], renderScope: String.init)
        #expect(result.status == .violated)
        #expect(result.witness?.prefix.first == 0)
    }

    @Test("unselected branches and states unreachable from a selected branch are not evaluated")
    func skipsUnselectedEvaluation() throws {
        let condition = Condition.conditional({ $0 == 0 }, then: .all([
            .always { state in
                if state == 1 { throw PredicateError.evaluated }
                return true
            },
            .conditional({ $0 == 0 }, then: .eventually { $0 == 0 },
                else: .always { _ in throw PredicateError.evaluated })
        ]), else: .always { _ in true })
        #expect(try checker().analyze(condition, initialStates: [0, 1], renderScope: String.init).status == .satisfied)
    }

    @Test("conditional guard failures propagate and incomplete graphs remain unavailable")
    func preservesFailures() throws {
        let condition = Condition.conditional({ _ in throw PredicateError.evaluated },
            then: .all([]), else: .all([]))
        #expect(throws: PredicateError.self) {
            try checker().analyze(condition, initialStates: [0], renderScope: String.init)
        }
        let result = try checker().analyze(condition, initialStates: [0], isComplete: false, renderScope: String.init)
        #expect(result.status == .unavailable)
        #expect(result.reason == .incompleteExploration)
    }

    @Test("generated conditional claims preserve typed identities, fairness, export, and actionable traces")
    func generatedClaims() throws {
        let scenario = try #require(try ConditionalTemporalClaims.validationScenarios().first)
        let run = try NativeScenarioRun(scenario, maximumStates: 20)
        try run.validateExpectations()
        let graph = try scenario.explore(maximumStates: 20)
        #expect(graph.temporalResults[.startsHere]?.status == .satisfied)
        let failure = try #require(graph.temporalResults[.missesOtherInitial])
        #expect(failure.status == .violated)
        #expect(failure.witness?.prefix.first?.state.value == 0)
        guard case .violated(let trace) = run.native.checks.properties["missesOtherInitial"] else {
            Issue.record("Expected the conditional counterexample")
            return
        }
        try trace.validate(in: run.native.graph.graph)
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.tla.contains("IF (value = 0) THEN"))
        #expect(rendered.tlaBundle.tla.contains("ELSE (IF (value = 1) THEN"))
    }

    @Test("malformed temporal conditions fail compilation", arguments: [
        ".conditional(1, then: .always(true), else: .always(false))",
        ".conditional(true, then: .always(true))",
        ".conditional(true, then: .eventually(1), else: .always(false))",
        ".all([.always(true), .unknown(false)])"
    ])
    func rejectsMalformedCondition(_ expression: String) throws {
        let spec = SpecParser.parseSpecClosure(named: "Invalid", try parseSpecTestClosure("""
        {
            let claim = Temporal()
            claim(\(expression))
            Validation("Check") {}
        }
        """))
        #expect(throws: (any Error).self) {
            let compiled = try spec.compile()
            _ = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        }
    }
}
