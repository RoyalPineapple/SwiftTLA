import Testing
import UpstreamParity

struct CoreConformanceCanonicalizationTests {
    @Test("canonical graph preserves labels and repeated edge occurrences")
    func preservesParallelLabelsAndMultiplicityAcrossTraversalOrder() throws {
        let first = CanonicalStateV1(bindings: ["counter": .integer(1)])
        let second = CanonicalStateV1(bindings: ["counter": .integer(2)])

        let forward = try CanonicalGraphV1(
            initialStates: [first],
            states: [first, second],
            edges: [
                .init(source: first.key, action: "advance", target: second.key),
                .init(source: first.key, action: "reset", target: second.key),
                .init(source: first.key, action: "advance", target: second.key)
            ]
        )
        let reversed = try CanonicalGraphV1(
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
        let left = CanonicalValueV1.record([
            "values": .set([.integer(2), .integer(1)]),
            "mapping": .function([.init(key: .string("b"), value: .boolean(false)), .init(key: .string("a"), value: .boolean(true))])
        ])
        let right = CanonicalValueV1.record([
            "mapping": .function([.init(key: .string("a"), value: .boolean(true)), .init(key: .string("b"), value: .boolean(false))]),
            "values": .set([.integer(1), .integer(2)])
        ])

        #expect(left == right)
        #expect(left.canonicalEncoding == right.canonicalEncoding)
    }
}
