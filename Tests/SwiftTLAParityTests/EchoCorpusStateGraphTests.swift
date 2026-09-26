import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct EchoCorpusStateGraphTests {
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
        let message = EchoModel.Message(kind: .acknowledgement, sender: .b)
        #expect(message.tlaValue == .record(["kind": .string("c"), "sender": .string("b")]))
        #expect(EchoModel.Message(formalValue: message.tlaValue) == message)
        #expect(EchoModel.Message(formalValue: .record([
            "kind": .string("unknown"), "sender": .string("b")
        ])) == nil)
        #expect(EchoModel.Message(formalValue: .record([
            "kind": .string("c"), "sender": .string("b"), "extra": .int(1)
        ])) == nil)
    }
}
