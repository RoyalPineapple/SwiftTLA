import SwiftTLA
import Testing
import UpstreamParity

struct CoreConformanceCanonicalizationTests {
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
    func canonicalizesNestedUnorderedValues() {
        let left = CanonicalValue.record([
            "values": .set([.integer(2), .integer(1)]),
            "mapping": .function([.init(key: .string("b"), value: .boolean(false)), .init(key: .string("a"), value: .boolean(true))])
        ])
        let right = CanonicalValue.record([
            "mapping": .function([.init(key: .string("a"), value: .boolean(true)), .init(key: .string("b"), value: .boolean(false))]),
            "values": .set([.integer(1), .integer(2)])
        ])

        #expect(left == right)
        #expect(left.canonicalEncoding == right.canonicalEncoding)
    }

    @Test("Swift normalization canonicalizes complete graph state references")
    func normalizesStatesEdgesAndObservations() throws {
        let first = StateGraph.StateID(0)
        let second = StateGraph.StateID(1)
        let firstCars: TLAValue = .record(["carA": .int(0), "carB": .int(1)])
        let secondCars: TLAValue = .record(["carA": .int(1), "carB": .int(1)])
        let exploration = ModelExplorationResult(
            graph: StateGraph(
                specName: "NormalizedFixture",
                variableNames: ["cars"],
                transitions: [first: [.init(label: .init(.init(name: "move")), target: second)]],
                states: [first: ["cars": firstCars], second: ["cars": secondCars]]
            ),
            initialStateIDs: [first],
            result: .ok(statesCount: 2)
        )
        let declaredCase = try CoreConformanceCase(
            id: "normalized-fixture",
            moduleSHA256: String(repeating: "a", count: 64),
            cfgSHA256: String(repeating: "b", count: 64),
            arguments: [],
            argumentsSHA256: CoreConformanceCase.argumentsDigest([]),
            workers: 1,
            fingerprintPolynomial: 1,
            deadlock: false,
            operatingSystem: "macos",
            architecture: "arm64",
            environment: [:],
            pin: .fixture,
            valueNormalizations: [
                try CoreConformanceValueNormalization(
                    binding: "cars", functionKeys: ["\"carA\"": "carA", "\"carB\"": "carB"])
            ]
        )

        let run = try SwiftGraphAdapter().adapt(
            SwiftExplorationEvidence(
                caseID: declaredCase.id,
                exploration: exploration,
                compiledModelIdentity: "fixture-model",
                maximumStateLimit: 10
            ),
            for: declaredCase
        )
        let expectedFirst = CanonicalState(bindings: [
            "cars": .record(["carA": .integer(0), "carB": .integer(1)])
        ])
        let expectedSecond = CanonicalState(bindings: [
            "cars": .record(["carA": .integer(1), "carB": .integer(1)])
        ])

        #expect(Set(run.graph.states.values) == Set([expectedFirst, expectedSecond]))
        #expect(run.graph.initialStateKeys == Set([expectedFirst.key]))
        #expect(run.graph.edgeOccurrences == [
            .init(source: expectedFirst.key, action: "move", target: expectedSecond.key): 1
        ])
        #expect(run.graph.observations[expectedFirst.key]?.enabledActions == ["move"])
    }
}
