import Testing
import SwiftTLA

@Suite(.serialized)
struct LivenessConformanceTests {
    private let initial = StateGraph.StateID(0)
    private let middle = StateGraph.StateID(1)
    private let terminal = StateGraph.StateID(2)

    private func action(_ name: String) -> NamedAction {
        NamedAction(name: name, body: .guard_(true))
    }

    private func predicate(_ value: Int) -> StateExpr {
        .equal(.variable("x"), .value(.int(value)))
    }

    private func graph(
        transitions: [StateGraph.StateID: [StateGraph.Transition]],
        values: [StateGraph.StateID: Int]
    ) -> StateGraph {
        StateGraph(
            specName: "liveness-conformance",
            variableNames: ["x"],
            transitions: transitions,
            states: Dictionary(uniqueKeysWithValues: values.map { ($0.key, ["x": .int($0.value)]) })
        )
    }

    @Test("reachable nonterminal avoiding subcycle has a canonical fair-lasso witness")
    func findsReachableNonterminalAvoidingSubcycle() {
        let initial = StateGraph.StateID(0)
        let left = StateGraph.StateID(1)
        let right = StateGraph.StateID(2)
        let terminal = StateGraph.StateID(3)
        let graph = StateGraph(
            specName: "nonterminal-subcycle",
            variableNames: ["x"],
            transitions: [
                initial: [.init(action: "enter", target: left)],
                left: [.init(action: "right", target: right), .init(action: "finish", target: terminal)],
                right: [.init(action: "left", target: left)],
                terminal: [.init(action: "done", target: terminal)]
            ],
            states: [
                initial: ["x": .int(0)],
                left: ["x": .int(1)],
                right: ["x": .int(2)],
                terminal: ["x": .int(3)]
            ]
        )
        let checker = LivenessChecker(graph: graph)
        let property: StateExpr = .or(
            .equal(.variable("x"), .value(.int(0))),
            .equal(.variable("x"), .value(.int(3)))
        )
        let actions = [
            NamedAction(name: "enter", body: .guard_(true)),
            NamedAction(name: "right", body: .guard_(true)),
            NamedAction(name: "left", body: .guard_(true)),
            NamedAction(name: "finish", body: .guard_(true)),
            NamedAction(name: "done", body: .guard_(true))
        ]

        let result = checker.analyze(
            .alwaysEventually(property),
            fairness: [],
            actions: actions,
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [initial, left])
        #expect(result.witness?.cycle == [left, left])
    }

    @Test("the temporal form matrix returns fair-lasso violations")
    func temporalFormMatrix() {
        let graph = graph(transitions: [:], values: [initial: 0])
        let checker = LivenessChecker(graph: graph)
        let falsePredicate = predicate(1)
        let truePredicate = predicate(0)
        let cases: [(String, TemporalExpr)] = [
            ("always", .always(falsePredicate)),
            ("eventually", .eventually(falsePredicate)),
            ("alwaysEventually", .alwaysEventually(falsePredicate)),
            ("eventuallyAlways", .eventuallyAlways(falsePredicate)),
            ("leadsTo", .leadsTo(truePredicate, falsePredicate))
        ]

        for (name, property) in cases {
            let result = checker.analyze(property, fairness: [], actions: [], initialStateIDs: [initial])
            #expect(result.status == .violated, "Expected \(name) to have a stuttering counterexample")
            #expect(result.witness?.cycle == [initial, initial])
        }
    }

    @Test("leads-to lasso stays outside Q after its P and not-Q trigger")
    func leadsToPrefixNeverCrossesQ() {
        let qState = StateGraph.StateID(1)
        let trigger = StateGraph.StateID(2)
        let safe = StateGraph.StateID(3)
        let cycle = StateGraph.StateID(4)
        let graph = graph(
            transitions: [
                initial: [.init(action: "trigger", target: trigger)],
                trigger: [.init(action: "A", target: qState), .init(action: "B", target: safe)],
                qState: [.init(action: "fromQ", target: cycle)],
                safe: [.init(action: "safeCycle", target: cycle)],
                cycle: [.init(action: "loop", target: cycle)]
            ],
            values: [initial: 0, qState: 2, trigger: 1, safe: 0, cycle: 0]
        )
        let checker = LivenessChecker(graph: graph)
        let result = checker.analyze(
            .leadsTo(predicate(1), predicate(2)),
            fairness: [.weakFairness("A")],
            actions: [action("trigger"), action("A"), action("B"), action("fromQ"), action("safeCycle"), action("loop")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        guard let witness = result.witness else {
            Issue.record("Expected a fair-lasso witness")
            return
        }
        #expect(witness.prefix == [initial, trigger, safe])
        guard let triggerIndex = witness.prefix.firstIndex(of: trigger) else {
            Issue.record("Expected the leads-to trigger in the witness prefix")
            return
        }
        let suffix = witness.prefix[triggerIndex...] + witness.cycle.dropFirst()
        #expect(suffix.allSatisfy { graph.states[$0]?["x"] != .int(2) })
    }

    @Test("canonical witness uses the globally shortest cycle entry")
    func canonicalWitnessUsesShortestCycleEntry() {
        let far = StateGraph.StateID(1)
        let near = StateGraph.StateID(2)
        let bridge = StateGraph.StateID(3)
        let graph = graph(
            transitions: [
                initial: [.init(action: "bridge", target: bridge), .init(action: "near", target: near)],
                bridge: [.init(action: "far", target: far)],
                far: [.init(action: "toNear", target: near)],
                near: [.init(action: "toFar", target: far)]
            ],
            values: [initial: 1, far: 0, near: 0, bridge: 1]
        )
        let result = LivenessChecker(graph: graph).analyze(
            .alwaysEventually(predicate(1)),
            fairness: [],
            actions: [action("bridge"), action("far"), action("near"), action("toNear"), action("toFar")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [initial, near])
    }

    @Test("eventually is satisfied when P holds in the initial state")
    func eventuallyDoesNotTreatPostSatisfactionLoopAsAViolation() {
        let avoiding = StateGraph.StateID(1)
        let graph = graph(
            transitions: [initial: [.init(action: "leave", target: avoiding)]],
            values: [initial: 1, avoiding: 0]
        )

        let result = LivenessChecker(graph: graph).analyze(
            .eventually(predicate(1)),
            fairness: [],
            actions: [action("leave")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .satisfied)
        #expect(result.witness == nil)
    }

    @Test("canonical witness chooses the shortest cycle after an equal prefix")
    func canonicalWitnessPrefersShortestCycleAfterEqualPrefix() {
        let longA = StateGraph.StateID(1)
        let longB = StateGraph.StateID(2)
        let longC = StateGraph.StateID(3)
        let shortA = StateGraph.StateID(10)
        let shortB = StateGraph.StateID(11)
        let graph = graph(
            transitions: [
                initial: [.init(action: "long", target: longA), .init(action: "short", target: shortA)],
                longA: [.init(action: "A", target: longB)],
                longB: [.init(action: "A", target: longC)],
                longC: [.init(action: "A", target: longA)],
                shortA: [.init(action: "A", target: shortB)],
                shortB: [.init(action: "A", target: shortA)]
            ],
            values: [initial: 1, longA: 0, longB: 0, longC: 0, shortA: 0, shortB: 0]
        )

        let result = LivenessChecker(graph: graph).analyze(
            .alwaysEventually(predicate(1)),
            fairness: [.weakFairness("A")],
            actions: [action("long"), action("short"), action("A")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [initial, shortA])
        #expect(result.witness?.cycle == [shortA, shortB, shortA])
    }

    @Test("same-SCC fair-cycle search prefers the shorter valid action loop")
    func sameSCCFairCycleSearchPrefersShortLoop() {
        let longA = StateGraph.StateID(1)
        let longB = StateGraph.StateID(2)
        let longC = StateGraph.StateID(3)
        let short = StateGraph.StateID(4)
        let graph = graph(
            transitions: [
                initial: [.init(action: "A", target: longA), .init(action: "A", target: short)],
                longA: [.init(action: "loop", target: longB)],
                longB: [.init(action: "loop", target: longC)],
                longC: [.init(action: "loop", target: initial)],
                short: [.init(action: "loop", target: initial)]
            ],
            values: [initial: 0, longA: 0, longB: 0, longC: 0, short: 0]
        )

        let result = LivenessChecker(graph: graph).analyze(
            .alwaysEventually(predicate(1)),
            fairness: [.weakFairness("A")],
            actions: [action("A"), action("loop")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [initial])
        #expect(result.witness?.cycle == [initial, short, initial])
    }

    @Test("disabled fairness alternative wins inside an SCC that also contains A")
    func disabledFairnessAlternativeWinsInsideMixedSCC() {
        let enabled = StateGraph.StateID(1)
        let graph = graph(
            transitions: [
                initial: [.init(action: "B", target: enabled)],
                enabled: [.init(action: "A", target: initial)]
            ],
            values: [initial: 0, enabled: 0]
        )
        let checker = LivenessChecker(graph: graph)
        let actions = [action("A"), action("B")]

        for fairness in [[FairnessCondition.weakFairness("A")], [.strongFairness("A")]] {
            let result = checker.analyze(
                .alwaysEventually(predicate(1)),
                fairness: fairness,
                actions: actions,
                initialStateIDs: [initial]
            )

            #expect(result.status == .violated)
            #expect(result.witness?.prefix == [initial])
            #expect(result.witness?.cycle == [initial, initial])
        }
    }

    @Test("enabledness and fairness are reported for changing action availability")
    func changingEnablednessFairnessMatrix() {
        let disabled = StateGraph.StateID(1)
        let graph = graph(
            transitions: [
                initial: [.init(action: "A", target: terminal), .init(action: "B", target: disabled)],
                disabled: [.init(action: "C", target: initial)],
                terminal: [.init(action: "done", target: terminal)]
            ],
            values: [initial: 0, disabled: 0, terminal: 1]
        )
        let checker = LivenessChecker(graph: graph)
        let actions = [action("A"), action("B"), action("C"), action("done")]
        let property = TemporalExpr.alwaysEventually(predicate(1))
        let cases: [(String, [FairnessCondition])] = [
            ("none", []),
            ("weak", [.weakFairness("A")]),
            ("strong", [.strongFairness("A")])
        ]

        for (_, fairness) in cases {
            let result = checker.analyze(property, fairness: fairness, actions: actions, initialStateIDs: [initial])
            #expect(result.enabledActions["A"]?[initial] == true)
            #expect(result.enabledActions["A"]?[disabled] == false)
            #expect(result.status == .violated)
        }

        let scc = Set([initial, disabled])
        #expect(checker.fairTerminalSCCs([scc], fairness: [.weakFairness("A")], actions: actions).count == 1)
        #expect(checker.fairTerminalSCCs([scc], fairness: [.strongFairness("A")], actions: actions).isEmpty)
    }

    @Test("unavailable evidence is explicit for unknown actions, evaluation errors, and incomplete exploration")
    func unavailableEvidenceMatrix() {
        let graph = graph(
            transitions: [initial: [.init(action: "unknown", target: initial)]],
            values: [initial: 0]
        )
        let checker = LivenessChecker(graph: graph)
        let unavailable: [(String, TemporalAnalysisResult, TemporalDiagnosticReason)] = [
            (
                "unknown action",
                checker.analyze(.eventually(predicate(1)), fairness: [], actions: [action("known")], initialStateIDs: [initial]),
                .unknownAction
            ),
            (
                "evaluation failure",
                checker.analyze(.eventually(.variable("missing")), fairness: [], actions: [action("unknown")], initialStateIDs: [initial]),
                .evaluationFailed
            ),
            (
                "incomplete exploration",
                checker.analyze(.eventually(predicate(1)), fairness: [], actions: [action("unknown")], initialStateIDs: [initial], isComplete: false),
                .incompleteExploration
            )
        ]

        for (name, result, reason) in unavailable {
            #expect(result.status == .unavailable, "Expected \(name) to be unavailable")
            #expect(result.reason == reason)
        }
    }

    @Test("ModelChecker keeps liveness and incomplete-exploration results compatible")
    func modelCheckerCompatibility() throws {
        let x = Var<Int>("x")
        let livenessSpec = TLASpec("liveness") {
            Variable(x, 0)
            Eventually("reachesOne", x == 1)
        }
        let liveness = try ModelChecker(spec: livenessSpec).checkLiveness()
        if case .livenessViolated = liveness.underlyingOutcome {
        } else {
            Issue.record("Expected liveness violation, got \(liveness)")
        }

        let completeSpec = TLASpec("incomplete") {
            Variable(x, in: 0...2)
            Action("step") { x.becomes(x + 1).when(x < 2) }
            Eventually("reachesTwo", x == 2)
        }
        let incomplete = try ModelChecker(spec: completeSpec, maxStates: 1).checkLiveness()
        if case .depthExceeded = incomplete.underlyingOutcome {
        } else {
            Issue.record("Expected depth-exceeded result, got \(incomplete)")
        }
    }
}
