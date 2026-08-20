import Testing
@testable import SwiftTLA

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
            states: Dictionary(
                uniqueKeysWithValues: values.map { identifier, value in
                    (identifier, fixtureProjection(["x": .int(value)]))
                }
            )
        )
    }

    private func analyze(
        _ graph: StateGraph,
        property: TemporalExpr,
        fairness: [FairnessCondition] = [],
        actions: [NamedAction] = [],
        initialStateIDs: [StateGraph.StateID],
        isComplete: Bool = true
    ) throws -> TemporalAnalysisResult {
        let spec = TLASpec(
            name: graph.specName,
            variables: [NamedVar(name: "x", initial: .int(0))],
            actions: actions,
            invariants: [],
            temporalProperties: [NamedTemporal(name: "property", expr: property)],
            fairness: fairness
        )
        let checker = LivenessChecker(compilation: try spec.compile(), graph: graph)
        return try #require(checker.analyze(
            initialStateIDs: initialStateIDs,
            isComplete: isComplete
        ).first)
    }

    @Test("reachable nonterminal avoiding subcycle has a canonical fair-lasso witness")
    func findsReachableNonterminalAvoidingSubcycle() throws {
        let initial = StateGraph.StateID(0)
        let left = StateGraph.StateID(1)
        let right = StateGraph.StateID(2)
        let terminal = StateGraph.StateID(3)
        let graph = StateGraph(
            specName: "nonterminal-subcycle",
            variableNames: ["x"],
            transitions: [
                initial: [.init(label: .init(.init(name: "enter")), target: left)],
                left: [.init(label: .init(.init(name: "right")), target: right), .init(label: .init(.init(name: "finish")), target: terminal)],
                right: [.init(label: .init(.init(name: "left")), target: left)],
                terminal: [.init(label: .init(.init(name: "done")), target: terminal)]
            ],
            states: [
                initial: fixtureProjection(["x": .int(0)]),
                left: fixtureProjection(["x": .int(1)]),
                right: fixtureProjection(["x": .int(2)]),
                terminal: fixtureProjection(["x": .int(3)])
            ]
        )
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

        let result = try analyze(
            graph,
            property: .alwaysEventually(property),
            fairness: [],
            actions: actions,
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [initial, left])
        #expect(result.witness?.cycle == [left, left])
    }

    @Test("the temporal form matrix returns fair-lasso violations")
    func temporalFormMatrix() throws {
        let graph = graph(transitions: [:], values: [initial: 0])
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
            let result = try analyze(graph, property: property, initialStateIDs: [initial])
            #expect(result.status == .violated, "Expected \(name) to have a stuttering counterexample")
            #expect(result.witness?.cycle == [initial, initial])
        }
    }

    @Test("leads-to lasso stays outside Q after its P and not-Q trigger")
    func leadsToPrefixNeverCrossesQ() throws {
        let qState = StateGraph.StateID(1)
        let trigger = StateGraph.StateID(2)
        let safe = StateGraph.StateID(3)
        let cycle = StateGraph.StateID(4)
        let graph = graph(
            transitions: [
                initial: [.init(label: .init(.init(name: "trigger")), target: trigger)],
                trigger: [.init(label: .init(.init(name: "A")), target: qState), .init(label: .init(.init(name: "B")), target: safe)],
                qState: [.init(label: .init(.init(name: "fromQ")), target: cycle)],
                safe: [.init(label: .init(.init(name: "safeCycle")), target: cycle)],
                cycle: [.init(label: .init(.init(name: "loop")), target: cycle)]
            ],
            values: [initial: 0, qState: 2, trigger: 1, safe: 0, cycle: 0]
        )
        let result = try analyze(
            graph,
            property: .leadsTo(predicate(1), predicate(2)),
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
        #expect(suffix.allSatisfy { graph.states[$0]?.formalValues["x"] != .int(2) })
    }

    @Test("canonical witness uses the globally shortest cycle entry")
    func canonicalWitnessUsesShortestCycleEntry() throws {
        let far = StateGraph.StateID(1)
        let near = StateGraph.StateID(2)
        let bridge = StateGraph.StateID(3)
        let graph = graph(
            transitions: [
                initial: [.init(label: .init(.init(name: "bridge")), target: bridge), .init(label: .init(.init(name: "near")), target: near)],
                bridge: [.init(label: .init(.init(name: "far")), target: far)],
                far: [.init(label: .init(.init(name: "toNear")), target: near)],
                near: [.init(label: .init(.init(name: "toFar")), target: far)]
            ],
            values: [initial: 1, far: 0, near: 0, bridge: 1]
        )
        let result = try analyze(
            graph,
            property: .alwaysEventually(predicate(1)),
            fairness: [],
            actions: [action("bridge"), action("far"), action("near"), action("toNear"), action("toFar")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [initial, near])
    }

    @Test("eventually is satisfied when P holds in the initial state")
    func eventuallyDoesNotTreatPostSatisfactionLoopAsAViolation() throws {
        let avoiding = StateGraph.StateID(1)
        let graph = graph(
            transitions: [initial: [.init(label: .init(.init(name: "leave")), target: avoiding)]],
            values: [initial: 1, avoiding: 0]
        )

        let result = try analyze(
            graph,
            property: .eventually(predicate(1)),
            fairness: [],
            actions: [action("leave")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .satisfied)
        #expect(result.witness == nil)
    }

    @Test("canonical witness chooses the shortest cycle after an equal prefix")
    func canonicalWitnessPrefersShortestCycleAfterEqualPrefix() throws {
        let longA = StateGraph.StateID(1)
        let longB = StateGraph.StateID(2)
        let longC = StateGraph.StateID(3)
        let shortA = StateGraph.StateID(10)
        let shortB = StateGraph.StateID(11)
        let graph = graph(
            transitions: [
                initial: [.init(label: .init(.init(name: "long")), target: longA), .init(label: .init(.init(name: "short")), target: shortA)],
                longA: [.init(label: .init(.init(name: "A")), target: longB)],
                longB: [.init(label: .init(.init(name: "A")), target: longC)],
                longC: [.init(label: .init(.init(name: "A")), target: longA)],
                shortA: [.init(label: .init(.init(name: "A")), target: shortB)],
                shortB: [.init(label: .init(.init(name: "A")), target: shortA)]
            ],
            values: [initial: 1, longA: 0, longB: 0, longC: 0, shortA: 0, shortB: 0]
        )

        let result = try analyze(
            graph,
            property: .alwaysEventually(predicate(1)),
            fairness: [.weakFairness("A")],
            actions: [action("long"), action("short"), action("A")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [initial, shortA])
        #expect(result.witness?.cycle == [shortA, shortB, shortA])
    }

    @Test("same-SCC fair-cycle search prefers the shorter valid action loop")
    func sameSCCFairCycleSearchPrefersShortLoop() throws {
        let longA = StateGraph.StateID(1)
        let longB = StateGraph.StateID(2)
        let longC = StateGraph.StateID(3)
        let short = StateGraph.StateID(4)
        let graph = graph(
            transitions: [
                initial: [.init(label: .init(.init(name: "A")), target: longA), .init(label: .init(.init(name: "A")), target: short)],
                longA: [.init(label: .init(.init(name: "loop")), target: longB)],
                longB: [.init(label: .init(.init(name: "loop")), target: longC)],
                longC: [.init(label: .init(.init(name: "loop")), target: initial)],
                short: [.init(label: .init(.init(name: "loop")), target: initial)]
            ],
            values: [initial: 0, longA: 0, longB: 0, longC: 0, short: 0]
        )

        let result = try analyze(
            graph,
            property: .alwaysEventually(predicate(1)),
            fairness: [.weakFairness("A")],
            actions: [action("A"), action("loop")],
            initialStateIDs: [initial]
        )

        #expect(result.status == .violated)
        #expect(result.witness?.prefix == [initial])
        #expect(result.witness?.cycle == [initial, short, initial])
    }

    @Test("disabled fairness alternative wins inside an SCC that also contains A")
    func disabledFairnessAlternativeWinsInsideMixedSCC() throws {
        let enabled = StateGraph.StateID(1)
        let graph = graph(
            transitions: [
                initial: [.init(label: .init(.init(name: "B")), target: enabled)],
                enabled: [.init(label: .init(.init(name: "A")), target: initial)]
            ],
            values: [initial: 0, enabled: 0]
        )
        let actions = [action("A"), action("B")]

        for fairness in [[FairnessCondition.weakFairness("A")], [.strongFairness("A")]] {
            let result = try analyze(
                graph,
                property: .alwaysEventually(predicate(1)),
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
    func changingEnablednessFairnessMatrix() throws {
        let disabled = StateGraph.StateID(1)
        let graph = graph(
            transitions: [
                initial: [.init(label: .init(.init(name: "A")), target: terminal), .init(label: .init(.init(name: "B")), target: disabled)],
                disabled: [.init(label: .init(.init(name: "C")), target: initial)],
                terminal: [.init(label: .init(.init(name: "done")), target: terminal)]
            ],
            values: [initial: 0, disabled: 0, terminal: 1]
        )
        let actions = [action("A"), action("B"), action("C"), action("done")]
        let property = TemporalExpr.alwaysEventually(predicate(1))
        let cases: [(String, [FairnessCondition])] = [
            ("none", []),
            ("weak", [.weakFairness("A")]),
            ("strong", [.strongFairness("A")])
        ]

        for (_, fairness) in cases {
            let result = try analyze(
                graph,
                property: property,
                fairness: fairness,
                actions: actions,
                initialStateIDs: [initial]
            )
            #expect(result.enabledActions["A"]?[initial] == true)
            #expect(result.enabledActions["A"]?[disabled] == false)
            #expect(result.status == .violated)
        }

        let weak = try analyze(
            graph,
            property: property,
            fairness: [.weakFairness("A")],
            actions: actions,
            initialStateIDs: [initial]
        )
        let strong = try analyze(
            graph,
            property: property,
            fairness: [.strongFairness("A")],
            actions: actions,
            initialStateIDs: [initial]
        )
        #expect(weak.fairComponents.contains(Set([initial, disabled])))
        #expect(strong.rejectedComponents.contains(Set([initial, disabled])))
    }

    @Test("unavailable evidence is explicit for unknown actions, evaluation errors, and incomplete exploration")
    func unavailableEvidenceMatrix() throws {
        let unknownActionGraph = graph(
            transitions: [initial: [.init(label: .init(.init(name: "unknown")), target: initial)]],
            values: [initial: 0]
        )
        let invalidProjectionGraph = StateGraph(
            specName: "liveness-conformance",
            variableNames: ["x"],
            transitions: [initial: [.init(label: .init(.init(name: "known")), target: initial)]],
            states: [initial: fixtureProjection(["other": .int(0)])]
        )
        let unavailable: [(String, TemporalAnalysisResult, TemporalDiagnosticReason)] = [
            (
                "unknown action",
                try analyze(unknownActionGraph, property: .eventually(predicate(1)), actions: [action("known")], initialStateIDs: [initial]),
                .unknownAction
            ),
            (
                "evaluation failure",
                try analyze(invalidProjectionGraph, property: .eventually(predicate(1)), actions: [action("known")], initialStateIDs: [initial]),
                .evaluationFailed
            ),
            (
                "incomplete exploration",
                try analyze(unknownActionGraph, property: .eventually(predicate(1)), actions: [action("known")], initialStateIDs: [initial], isComplete: false),
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

private func fixtureProjection(_ formalValues: [String: TLAValue]) -> TLAStateProjection {
    do {
        return try .init(formalValues: formalValues)
    } catch {
        preconditionFailure(String(describing: error))
    }
}
