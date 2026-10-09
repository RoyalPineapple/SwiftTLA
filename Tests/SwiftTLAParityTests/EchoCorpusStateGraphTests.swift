import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct EchoCorpusStateGraphTests {
    @Test("Echo configuration checks the published invariants and default deadlock")
    func configuredChecks() throws {
        let scenario = try #require(EchoModel.validationScenarios().first)
        #expect(scenario.name == "MCEcho")
        let run = try NativeScenarioRun(scenario, maximumStates: 1_000)
        try run.validateExpectations()
        #expect(run.native.rendered.checkNames == ["TypeOK", "AncestorProperties"])
        #expect(run.native.checks.properties["TypeOK"] == .satisfied)
        #expect(run.native.checks.properties["AncestorProperties"] == .satisfied)
        #expect(run.native.checks.deadlock == .satisfied)
        #expect(try #require(run.native.graph).graph.states.count == 75)
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

    @Test("Echo projection preserves upstream message fields and NoNode")
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
        #expect(EchoModel.NoNode.noNode.tlaValue == .constant("NoNode"))
        #expect(EchoModel.NoNode(formalValue: .string("NoNode")) == nil)
    }
}
