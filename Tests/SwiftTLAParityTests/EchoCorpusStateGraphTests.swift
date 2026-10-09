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

    @Test("Echo ancestor property rejects a cycle through the initiator")
    func ancestorCycle() throws {
        let compilation = try EchoModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let invariant = try #require(runtime.behavior.invariants.first { $0.name == "AncestorProperties" })
        let pc = try #require(compilation.layout.variables.first { $0.declaration.name == "pc" }).id
        let parent = try #require(compilation.layout.variables.first { $0.declaration.name == "parent" }).id
        let done = try #require(compilation.layout.controlLocations.first { $0.renderedName == "Done" }).id
        var state = try #require(runtime.initialStates().first)
        state = try state.updating(pc, to: .function([
            .string("a"): .controlLocation(done),
            .string("b"): .controlLocation(done),
            .string("c"): .controlLocation(done)
        ]))
        state = try state.updating(parent, to: .function([
            .string("a"): .string("b"),
            .string("b"): .string("a"),
            .string("c"): .string("a")
        ]))
        #expect(try !runtime.invariantHolds(invariant, in: state))
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
