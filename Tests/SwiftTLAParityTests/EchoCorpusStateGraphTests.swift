import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct EchoCorpusStateGraphTests {
    @Test("Echo initial state preserves the upstream parent sentinel and neighbor domains")
    func initialStateMatchesUpstreamShape() throws {
        let machine = try #require(EchoModel.initialMachines().first)
        let state = try machine.formalProjection(of: machine.snapshot)
        let parent = try #require(TLAStateProjection.Token(validating: "parent"))
        let rcvd = try #require(TLAStateProjection.Token(validating: "rcvd"))
        let nbrs = try #require(TLAStateProjection.Token(validating: "nbrs"))
        #expect(state.value(for: parent) == .function([
            .string("a"): .constant("NoNode"),
            .string("b"): .constant("NoNode"),
            .string("c"): .constant("NoNode")
        ]))
        #expect(state.value(for: rcvd) == .function([
            .string("a"): .int(0), .string("b"): .int(0), .string("c"): .int(0)
        ]))
        #expect(state.value(for: nbrs) == .function([
            .string("a"): .set([.string("b"), .string("c")]),
            .string("b"): .set([.string("a"), .string("c")]),
            .string("c"): .set([.string("a"), .string("b")])
        ]))
    }

    @Test("Echo ordinary messages preserve the complete three-node formal graph")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try EchoModel.spec.compile()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: .init(maximumStateLimit: 1_000, symmetryReduction: .disabled)
        ).explore()
        try #require(exploration.isComplete)
        #expect(exploration.graph.states.count == 75)
        let native = try ReachabilityGraph(
            initialMachines: EchoModel.initialMachines(), maximumStates: 1_000
        )
        #expect(native.safetyViolations.isEmpty)
        let exported = try CanonicalGraph(native)
        let formal = try FormalGraphExporter().export(exploration)
        #expect(exported == formal.graph)
    }

    @Test("Echo message projection preserves field names and enum wire values")
    func messageProjection() {
        let message = EchoModel.Message(kind: .acknowledgement, sndr: .b)
        #expect(message.tlaValue == .record(["kind": .string("c"), "sndr": .string("b")]))
        #expect(EchoModel.Message(formalValue: message.tlaValue) == message)
        #expect(EchoModel.Message(formalValue: .record([
            "kind": .string("unknown"), "sndr": .string("b")
        ])) == nil)
        #expect(EchoModel.Message(formalValue: .record([
            "kind": .string("c"), "sndr": .string("b"), "extra": .int(1)
        ])) == nil)
    }
}
