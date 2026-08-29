import SwiftTLA
import Testing
import UpstreamParity

struct CanonicalGraphTests {
    @Test("canonical graph preserves labels and repeated edge occurrences")
    func preservesParallelLabelsAndMultiplicityAcrossTraversalOrder() throws {
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
        #expect(forward.edgeOccurrences.count == 2)
        #expect(forward.edgeOccurrences[.init(source: first.key, action: "advance", target: second.key)] == 2)
        #expect(forward.edgeOccurrences[.init(source: first.key, action: "reset", target: second.key)] == 1)
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

    @Test("canonical functions reject duplicate keys")
    func rejectsDuplicateFunctionKeys() {
        #expect(throws: CanonicalValueError.self) {
            _ = try CanonicalValue.function([
                .init(key: .string("member"), value: .integer(1)),
                .init(key: .string("member"), value: .integer(2))
            ])
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
        let fixture = Var<Int>("fixture")
        let compilationIdentity = try TLASpec("NormalizedFixture") {
            Variable(fixture, 0)
        }.compile().identity
        let exploration = ModelExploration(
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
            result: .ok(statesCount: 2),
            compilationIdentity: compilationIdentity,
            configuration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled)
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

        let run = try SwiftGraphExporter().export(exploration, for: finiteGraphCase)
        let expectedFirst = CanonicalState(bindings: [
            "cars": .record(["carA": .integer(0), "carB": .integer(1)])
        ])
        let expectedSecond = CanonicalState(bindings: [
            "cars": .record(["carA": .integer(1), "carB": .integer(1)])
        ])

        #expect(Set(run.graph.states.values) == Set([expectedFirst, expectedSecond]))
        #expect(run.graph.initialStateKeys == Set([expectedFirst.key]))
        #expect(run.graph.edgeOccurrences == [
            CanonicalEdge(source: expectedFirst.key, action: "Move", target: expectedSecond.key): 1
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
            #expect(try SwiftGraphExporter().export(exploration).outcome == expected)
        }
    }
}
