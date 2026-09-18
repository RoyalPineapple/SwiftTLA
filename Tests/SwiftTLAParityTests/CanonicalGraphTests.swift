@testable import SwiftTLA
import Testing
import UpstreamParity

struct CanonicalGraphTests {
    @Test("large shared state prefixes retain deterministic edge ordering")
    func sortsLongStateKeys() {
        let count = 16_384
        let prefix = String(repeating: "x", count: 4096)
        let target = CanonicalStateKey(canonicalEncoding: "target")
        let edges = (0..<count).map { index in
            CanonicalEdge(source: .init(canonicalEncoding: prefix + String(count + (index * 4051) % count)),
                action: "step", target: target)
        }
        let ordered = edges.sorted().map { $0.source.canonicalEncoding.suffix(5) }
        #expect(ordered == (count..<(2 * count)).map { Substring(String($0)) })
    }

    @Test("Edge ordering preserves wire bytes, including prefix keys and Unicode actions")
    func edgeOrderingMatchesEncoding() {
        let states = ["", "a", "a!", "a-", "a--", "é", "e\u{301}", "\0", "\u{E000}", "😀"]
            .map { CanonicalStateKey(canonicalEncoding: $0) }
        let actions = ["", "a", "a!", "aa", "é", "e\u{301}", "\0", String(repeating: "step-", count: 8)]
        let edges = states.flatMap { source in
            actions.flatMap { action in
                states.map { target in CanonicalEdge(source: source, action: action, target: target) }
            }
        }
        for left in edges {
            for right in edges {
                let wireOrder = left.canonicalEncoding.utf8.lexicographicallyPrecedes(right.canonicalEncoding.utf8)
                #expect((left < right) == wireOrder)
            }
        }
        let composed = CanonicalEdge(source: states[1], action: "é", target: states[1])
        let decomposed = CanonicalEdge(source: states[1], action: "e\u{301}", target: states[1])
        #expect(composed != decomposed)
        #expect(Set([composed, decomposed, composed]).count == 2)
    }

    @Test("canonical graph preserves action labels and collapses repeated witnesses")
    func preservesParallelLabelsAcrossTraversalOrder() throws {
        let first = CanonicalState(bindings: ["counter": .integer(1)])
        let second = CanonicalState(bindings: ["counter": .integer(2)])

        let forward = try CanonicalGraph(
            initialStates: [first],
            states: [first, second],
            edges: [
                .init(source: first.key, action: "advance", target: second.key),
                .init(source: first.key, action: "reset", target: second.key),
                .init(source: first.key, action: "advance", target: second.key)
            ]
        )
        let reversed = try CanonicalGraph(
            initialStates: [first],
            states: [second, first],
            edges: [
                .init(source: first.key, action: "advance", target: second.key),
                .init(source: first.key, action: "reset", target: second.key),
                .init(source: first.key, action: "advance", target: second.key)
            ].reversed()
        )

        #expect(forward == reversed)
        #expect(forward.edges.count == 2)
        #expect(forward.edges.contains(.init(source: first.key, action: "advance", target: second.key)))
        #expect(forward.edges.contains(.init(source: first.key, action: "reset", target: second.key)))
    }

    @Test("prebuilt edge sets and state views preserve the complete labeled relation")
    func preservesStateViewsAndEdgeSets() throws {
        let first = CanonicalState(bindings: ["counter": .integer(1)])
        let second = CanonicalState(bindings: ["counter": .integer(2)])
        let table = try canonicalStateTable([first, second])
        let edges = [
            CanonicalEdge(source: first.key, action: "advance", target: second.key),
            CanonicalEdge(source: first.key, action: "reset", target: second.key),
            CanonicalEdge(source: first.key, action: "advance", target: second.key),
            CanonicalEdge(source: second.key, action: "stay", target: second.key)
        ]
        let arrayGraph = try CanonicalGraph(initialStates: [first, second], states: [first, second], edges: edges)
        let setGraph = try CanonicalGraph(initialStates: [second, first], states: table.values, edges: Set(edges))
        #expect(setGraph == arrayGraph)
        #expect(setGraph.initialStateKeys == Set(table.keys))
        #expect(setGraph.states == table)
        #expect(setGraph.edges == Set(edges))
        #expect(setGraph.edges.count == 3)
        #expect(setGraph.observedActions == ["advance", "reset", "stay"])
        #expect(throws: GraphRunError.graphActionUndeclared("stay")) {
            try GraphRun(isComplete: true, graph: setGraph, observableActions: ["advance", "reset"], outcome: .noViolation)
        }
        let declared = setGraph.observedActions.union(["unused"])
        let run = try GraphRun(isComplete: true, graph: setGraph, observableActions: declared, outcome: .noViolation)
        #expect(run.graph == setGraph)
        #expect(run.observableActions == declared)
    }

    @Test("prebuilt edge sets still reject missing initial states and endpoints")
    func rejectsMissingStateReferences() throws {
        let present = CanonicalState(bindings: ["counter": .integer(1)])
        let missing = CanonicalState(bindings: ["counter": .integer(2)])
        let table = try canonicalStateTable([present])
        #expect(throws: CanonicalGraphError.initialStateMissing(missing.key)) {
            try CanonicalGraph(initialStates: [missing], states: table.values, edges: Set<CanonicalEdge>())
        }
        for edge in [CanonicalEdge(source: missing.key, action: "step", target: present.key),
                     CanonicalEdge(source: present.key, action: "step", target: missing.key)] {
            #expect(throws: CanonicalGraphError.edgeStateMissing(missing.key)) {
                try CanonicalGraph(initialStates: [present], states: table.values, edges: Set([edge]))
            }
        }
    }

    @Test("state views reject missing and different variable names")
    func rejectsInconsistentStateBindings() throws {
        let first = CanonicalState(bindings: ["counter": .integer(1)])
        let alternatives: [[String: CanonicalValue]] = [["other": .integer(1)], [:]]
        for bindings in alternatives {
            let table = try canonicalStateTable([first, CanonicalState(bindings: bindings)])
            #expect(throws: CanonicalGraphError.self) {
                try CanonicalGraph(initialStates: [first], states: table.values, edges: Set<CanonicalEdge>())
            }
        }
    }

    @Test("canonical values are stable across unordered collection insertion")
    func canonicalizesNestedUnorderedValues() throws {
        let left = CanonicalValue.record([
            "values": .set([.integer(2), .integer(1)]),
            "mapping": try .function([.init(key: .string("b"), value: .boolean(false)), .init(key: .string("a"), value: .boolean(true))])
        ])
        let right = CanonicalValue.record([
            "mapping": try .function([.init(key: .string("a"), value: .boolean(true)), .init(key: .string("b"), value: .boolean(false))]),
            "values": .set([.integer(1), .integer(2)])
        ])

        #expect(left == right)
        #expect(left.canonicalEncoding == right.canonicalEncoding)
    }

    @Test("formal strings retain distinct Unicode encodings in nested collections")
    func preservesUnicodeValueIdentity() throws {
        let composed = CanonicalValue.string("é")
        let decomposed = CanonicalValue.string("e\u{301}")
        #expect(composed != decomposed)
        #expect(Set([composed, decomposed]).count == 2)
        let members = CanonicalValue.set([composed, decomposed, composed])
        guard case .orderedSet(let values) = members else {
            Issue.record("Expected a canonical set")
            return
        }
        #expect(values.count == 2)
        let function = try CanonicalValue.function([
            .init(key: composed, value: .integer(1)),
            .init(key: decomposed, value: .integer(2))
        ])
        guard case .orderedRecord(let fields) = function else {
            Issue.record("Expected a canonical string-keyed function")
            return
        }
        #expect(fields.count == 2)
        #expect(CanonicalValue.set([.tuple([composed]), .tuple([decomposed])])
            != .set([.tuple([composed])]))
    }

    @Test("canonical functions reject duplicate keys")
    func rejectsDuplicateFunctionKeys() {
        #expect(throws: CanonicalValueError.self) {
            _ = try CanonicalValue.function([
                .init(key: .string("member"), value: .integer(1)),
                .init(key: .string("member"), value: .integer(2))
            ])
        }
    }

    @Test("sequence functions and tuples share one canonical value")
    func canonicalizesSequenceFunctionsAsTuples() throws {
        let empty = CanonicalValue.tuple([])
        #expect(try CanonicalValue.function([]) == empty)
        #expect(CanonicalValue.record([:]) == empty)
        #expect(try CanonicalValue.function([
            .init(key: .integer(2), value: .string("second")),
            .init(key: .integer(1), value: .string("first"))
        ]) == .tuple([.string("first"), .string("second")]))
    }

    @Test("canonical sets collapse extensionally equal members")
    func deduplicatesCanonicalSetMembers() throws {
        let sequence = CanonicalValue.tuple([.integer(1)])
        let sequenceFunction = try CanonicalValue.function([
            .init(key: .integer(1), value: .integer(1))
        ])
        let empty = CanonicalValue.tuple([])

        #expect(CanonicalValue.set([sequence, sequenceFunction]) == .set([sequence]))
        #expect(CanonicalValue.set([empty, try .function([]), .record([:])]) == .set([empty]))
    }

    @Test("other function domains retain function identity")
    func preservesNonSequenceFunctions() throws {
        let noncontiguous = try CanonicalValue.function([
            .init(key: .integer(1), value: .string("first")),
            .init(key: .integer(3), value: .string("third"))
        ])
        let noninteger = try CanonicalValue.function([
            .init(key: .boolean(true), value: .string("value"))
        ])
        let zeroBased = try CanonicalValue.function([
            .init(key: .integer(0), value: .string("value"))
        ])

        guard case .orderedFunction = noncontiguous else {
            Issue.record("A noncontiguous integer domain must remain a function.")
            return
        }
        guard case .orderedFunction = noninteger else {
            Issue.record("A non-integer domain must remain a function.")
            return
        }
        guard case .orderedFunction = zeroBased else {
            Issue.record("A zero-based integer domain must remain a function.")
            return
        }
    }

    @Test("canonical graphs reject duplicate states")
    func rejectsDuplicateStates() {
        let state = CanonicalState(bindings: ["counter": .integer(1)])

        #expect(throws: CanonicalGraphError.duplicateState(state.key)) {
            _ = try CanonicalGraph(initialStates: [state], states: [state, state], edges: [])
        }
    }

    @Test("string-keyed functions and records share one canonical value")
    func canonicalizesStringKeyedFunctionsAsRecords() throws {
        let record = CanonicalValue.record(["member": .integer(1)])
        let function = try CanonicalValue.function([
            .init(key: .string("member"), value: .integer(1))
        ])
        let constantFunction = try CanonicalValue.function([
            .init(key: .constant("member"), value: .integer(1))
        ])

        #expect(function == record)
        #expect(constantFunction != record)
        #expect(try CanonicalValue.function([
            .init(key: .string("nested"), value: function)
        ]) == .record(["nested": record]))
    }

    @Test("Swift canonicalization preserves complete graph state references")
    func normalizesStatesEdgesAndObservations() throws {
        let first = StateGraph.StateID(0)
        let second = StateGraph.StateID(1)
        let firstCars: TLAValue = .function([.string("carA"): .int(0), .string("carB"): .int(1)])
        let secondCars: TLAValue = .function([.string("carA"): .int(1), .string("carB"): .int(1)])
        let compilation = try TLASpec(
            name: "NormalizedFixture", variables: [.init(name: "cars", initialization: .value(firstCars), origin: .compiler)],
            actions: [], invariants: []
        ).compile()
        let exploration = FiniteExploration(
            graph: StateGraph(
                specName: "NormalizedFixture",
                variableNames: ["cars"],
                transitions: [first: [.init(label: .init(.init(name: "move")), target: second)]],
                states: [
                    first: try projection([("cars", firstCars)]),
                    second: try projection([("cars", secondCars)])
                ]
            ),
            initialStateIDs: [first],
            completion: .ok(statesCount: 2),
            compilationIdentity: compilation.identity,
            configuration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled),
            compiledStates: [
                first: try CompiledState(values: [.init(formal: firstCars)], layout: compilation.layout, identity: compilation.identity),
                second: try CompiledState(values: [.init(formal: secondCars)], layout: compilation.layout, identity: compilation.identity)
            ]
        )
        let finiteGraphCase = try FiniteGraphCase(
            id: "normalized-fixture",
            exploration: exploration.configuration,
            moduleSHA256: String(repeating: "a", count: 64),
            cfgSHA256: String(repeating: "b", count: 64),
            arguments: [],
            environment: [:],
            pin: try testReferencePin(),
            renderedActions: [
                RenderedAction(sourceName: "move", arguments: [], renderedName: "Move")
            ]
        )

        let run = try FormalGraphExporter().export(exploration, for: finiteGraphCase)
        let expectedFirst = CanonicalState(bindings: [
            "cars": .record(["carA": .integer(0), "carB": .integer(1)])
        ])
        let expectedSecond = CanonicalState(bindings: [
            "cars": .record(["carA": .integer(1), "carB": .integer(1)])
        ])

        #expect(Set(run.graph.states.values) == Set([expectedFirst, expectedSecond]))
        #expect(run.graph.initialStateKeys == Set([expectedFirst.key]))
        #expect(run.graph.edges == [
            CanonicalEdge(source: expectedFirst.key, action: "Move", target: expectedSecond.key)
        ])
    }

    @Test("finite graph cases require unique rendered action identities and names")
    func rejectsDuplicateRenderedActions() throws {
        #expect(throws: FiniteGraphCaseError.invalidRenderedActions) {
            _ = try fixtureCase(try testReferencePin(), renderedActions: [
                RenderedAction(sourceName: "Move", arguments: [], renderedName: "MoveA"),
                RenderedAction(sourceName: "Move", arguments: [], renderedName: "MoveB")
            ])
        }
        #expect(throws: FiniteGraphCaseError.invalidRenderedActions) {
            _ = try fixtureCase(try testReferencePin(), renderedActions: [
                RenderedAction(sourceName: "MoveA", arguments: [], renderedName: "Move"),
                RenderedAction(sourceName: "MoveB", arguments: [], renderedName: "Move")
            ])
        }
    }

    @Test("typed checker failures become graph boundary outcomes")
    func exportsTypedCheckerFailures() throws {
        let value = Var<Int>("value")
        let configuration = try FiniteExplorationConfiguration(
            maximumStateLimit: 10,
            symmetryReduction: .disabled
        )
        let cases: [(TLASpec, GraphRunOutcome)] = [
            (
                TLASpec("EmptyInitialStateRelation") {
                    Variable(value, in: [Int]())
                },
                .executionError("the compiled initial-state relation is empty")
            ),
            (
                TLASpec("FalseCompiledAssumption") {
                    Assume(false)
                    Variable(value, 0)
                },
                .executionError("the compiled assumption evaluated to false")
            )
        ]

        for (specification, expected) in cases {
            let exploration = try ModelChecker(
                compilation: specification.compile(),
                configuration: configuration
            ).explore()
            #expect(try FormalGraphExporter().export(exploration).outcome == expected)
        }
    }
}
