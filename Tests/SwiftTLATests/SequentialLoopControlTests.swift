import Foundation
import Testing
import UpstreamParity
@testable import SwiftTLA

struct SequentialLoopControlTests {
    @Test("HourClock preserves all twelve initial states and labeled transitions without control state")
    func preservesHourClockGraph() throws {
        let scenario = try #require(try HourClockModel.validationScenarios().first)
        let graph = try scenario.explore(maximumStates: 12)
        #expect(graph.initialStates.count == 12)
        #expect(graph.transitions.count == 12)
        #expect(graph.transitions.values.flatMap { $0 }.count == 12)
        #expect(graph.deadlockedStates.isEmpty)
        for (source, successors) in graph.transitions {
            let successor = try #require(successors.first)
            #expect(successor.target.state.hr == (source.state.hr == 12 ? 1 : source.state.hr + 1))
            #expect(successor.action == .HCnxt)
        }
        let run = try NativeScenarioRun(scenario, maximumStates: 12)
        try run.validateExpectations()
        let rendered = try scenario.render()
        #expect(rendered.tlaBundle.tla.contains("VARIABLES hr\n"))
        #expect(!rendered.tlaBundle.tla.contains("Terminating =="))
        #expect(try rendered.plusCalBundle().root.cfg == rendered.tlaBundle.root.cfg)
    }

    @Test("a blocked endless loop remains a deadlock without synthetic termination")
    func preservesDeadlock() throws {
        let graph = try ReachabilityGraph(initialMachines: GuardedEndlessLoop.initialMachines(), maximumStates: 4)
        #expect(graph.transitions.count == 2)
        #expect(graph.deadlockedStates.map { $0.state.value } == [1])
        #expect(try GuardedEndlessLoop.render().tlaBundle.tla.contains("VARIABLES value\n"))
    }

    @Test("a conditional loop retains control state and normal completion")
    func preservesCompletion() throws {
        let graph = try ReachabilityGraph(initialMachines: FinishingLoop.initialMachines(), maximumStates: 4)
        #expect(graph.transitions.count == 3)
        #expect(graph.deadlockedStates.isEmpty)
        let (_, evidence) = try FinishingLoop.spec.compileRetainingSequentialControl()
        let control = try #require(evidence)
        let scheduled = try #require(control.scheduled.canonicalTraces(sourceWrites: false))
        let lowered = try #require(control.lowered.canonicalTraces(sourceWrites: false))
        #expect(scheduled == lowered)
        let initial = try #require(graph.initialStates.first)
        let body = try #require(graph.transitions[initial]?.first)
        #expect(body.action == .advance)
        #expect(body.target.state.value == 1)
        let exit = try #require(graph.transitions[body.target]?.first)
        #expect(exit.action == .advance)
        #expect(exit.target.state.value == body.target.state.value)
        let terminal = try #require(graph.transitions[exit.target]?.first)
        #expect(terminal.action == .Terminating)
        #expect(terminal.target == exit.target)

        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("SequentialLoopControlFixtures.swift")
        let authored = try Data(contentsOf: fixture)
        let rendered = try FinishingLoop.render()
        let proof = try #require(try SequentialControlOutputEvidence.proof(authoredSource: authored,
            modelName: String(describing: FinishingLoop.self), spec: FinishingLoop.spec, rendered: rendered))
        let module = rendered.tlaBundle.root
        let cfg = try #require(module.cfg)
#if compiler(>=6.2)
        Attachment.record(Array(authored), named: fixture.lastPathComponent)
        Attachment.record(Array(module.tla.utf8), named: "\(module.name).tla")
        Attachment.record(Array(cfg.utf8), named: "\(module.name).cfg")
        Attachment.record(Array(proof.control), named: "\(proof.controlModule).tla")
        Attachment.record(Array(proof.configured), named: "\(proof.configuredModule).tla")
#else
        _ = (cfg, proof)
#endif
    }
}
