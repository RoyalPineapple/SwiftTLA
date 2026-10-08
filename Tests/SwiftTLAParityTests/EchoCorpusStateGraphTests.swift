import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct EchoCorpusStateGraphTests {
    @Test("Echo exports the connected-relation assumption with its generated machine")
    func connectedRelationExport() throws {
        let scenario = try #require(EchoModel.validationScenarios().first)
        let exported = try EchoModel.render(configuration: scenario.configuration).plusCalBundle()
        let assumptions = try #require(exported.root.tla.components(separatedBy: "(*--algorithm").first)
        #expect(assumptions.contains("RECURSIVE"))
        #expect(assumptions.contains("\\A from \\in Node : (\\A to \\in Node"))
        #expect(exported.cfg.contains("CONSTANT NoNode = NoNode"))
        #expect(exported.cfg.contains("INVARIANT TypeOK"))
        #expect(exported.cfg.contains("INVARIANT AncestorProperties"))
        #expect(exported.cfg.contains("CHECK_DEADLOCK TRUE"))
    }

    @Test("MCEcho checks every generated claim over a complete graph")
    func configuredChecking() throws {
        let scenario = try #require(EchoModel.validationScenarios().first)
        #expect(scenario.name == "MCEcho")
        #expect(scenario.configuration.Node == Set<EchoModel.NodeID>([.a, .b, .c]))
        #expect(scenario.configuration.R.contains(.init(first: .a, second: .b)))
        #expect(!scenario.configuration.R.contains(.init(first: .a, second: .a)))
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
        let chain: Set<Pair<EchoModel.NodeID, EchoModel.NodeID>> = [
            .init(first: .a, second: .b), .init(first: .b, second: .a),
            .init(first: .b, second: .c), .init(first: .c, second: .b)
        ]
        let alternateRelation = try ReachabilityGraph(
            initialMachines: EchoModel.initialMachines(configuration: .init(
                Node: scenario.configuration.Node, R: chain)),
            maximumStates: 1_000
        )
        #expect(alternateRelation.safetyViolations.isEmpty)
        #expect(try CanonicalGraph(alternateRelation) != configuredGraph)
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

    @Test("Echo node membership controls its process and communication domains")
    func configuredNodeDomain() throws {
        let configuration = try EchoModel.Configuration(
            Node: [.b, .c],
            R: [.init(first: .b, second: .c), .init(first: .c, second: .b)]
        )
        let machine = try #require(EchoModel.initialMachines(configuration: configuration).first)
        let state = try machine.formalProjection(of: machine.snapshot)
        let pc = try #require(TLAStateProjection.Token(validating: "pc"))
        let inbox = try #require(TLAStateProjection.Token(validating: "inbox"))
        let nbrs = try #require(TLAStateProjection.Token(validating: "nbrs"))
        #expect(state.value(for: pc) == .function([.string("b"): .string("n0"), .string("c"): .string("n0")]))
        #expect(state.value(for: inbox) == .function([.string("b"): .set([]), .string("c"): .set([])]))
        #expect(state.value(for: nbrs) == .function([
            .string("b"): .set([.string("c")]), .string("c"): .set([.string("b")])
        ]))
        let graph = try ReachabilityGraph(initialMachines: [machine], maximumStates: 1_000)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("Echo rejects self-loop, asymmetric, and disconnected relations")
    func rejectsInvalidRelations() throws {
        let scenario = try #require(EchoModel.validationScenarios().first)
        let complete = scenario.configuration.R
        let selfLoop = complete.union([Pair<EchoModel.NodeID, EchoModel.NodeID>(first: .a, second: .a)])
        let asymmetric = complete.subtracting([Pair<EchoModel.NodeID, EchoModel.NodeID>(first: .b, second: .a)])
        let disconnected: Set<Pair<EchoModel.NodeID, EchoModel.NodeID>> = [
            .init(first: .a, second: .b), .init(first: .b, second: .a)
        ]
        for relation in [selfLoop, asymmetric, disconnected] {
            let configuration = try EchoModel.Configuration(
                Node: scenario.configuration.Node, R: relation
            )
            #expect(throws: ExplorationError.assumptionViolated) {
                try ReachabilityGraph(
                    initialMachines: EchoModel.initialMachines(configuration: configuration), maximumStates: 100
                )
            }
        }
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
