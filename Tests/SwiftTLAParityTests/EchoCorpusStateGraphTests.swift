import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct EchoCorpusStateGraphTests {
    @Test("MCEcho binds its initiator and checks every generated claim over a complete graph")
    func configuredChecking() throws {
        let scenario = try #require(EchoModel.validationScenarios().first)
        #expect(scenario.name == "MCEcho")
        #expect(scenario.configuration.initiator == .a)
        let run = try NativeScenarioRun(scenario, maximumStates: 1_000)
        try run.validateExpectations()
        #expect(run.coverage.coversCompleteScenario)
        #expect(run.native.checks.properties["TypeOK"] == .satisfied)
        #expect(run.native.checks.properties["AncestorProperties"] == .satisfied)
        #expect(run.native.checks.properties.keys.contains { $0.hasPrefix("__pcal_assert_") })
        #expect(run.native.checks.properties.values.allSatisfy { $0 == .satisfied })
        #expect(run.native.checks.deadlock == .satisfied)
        let configuredGraph = try #require(run.native.graph?.graph)
        #expect(configuredGraph.states.count == 75)
        let alternate = try ReachabilityGraph(
            initialMachines: EchoModel.initialMachines(configuration: .init(initiator: .b)),
            maximumStates: 1_000
        )
        #expect(alternate.safetyViolations.isEmpty)
        #expect(try CanonicalGraph(alternate) != configuredGraph)
    }

    @Test("Echo initial state preserves the upstream parent sentinel and neighbor domains")
    func initialStateMatchesUpstreamShape() throws {
        let scenario = try #require(EchoModel.validationScenarios().first)
        let machine = try #require(EchoModel.initialMachines(configuration: scenario.configuration).first)
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
