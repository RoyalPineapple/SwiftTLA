import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLACompilerSupport
import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

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
        let syntax = Parser.parse(source: String(decoding: authored, as: UTF8.self))
        let modelName = String(describing: FinishingLoop.self)
        let model = try #require(syntax.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .first { $0.name.text == modelName })
        var emitter = NativeSwiftEmitter(model: try TLASpecVerifier.parseAndVerify(model))
        let members = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        let library = fixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftTLA")
        let operations = try Data(contentsOf: library.appendingPathComponent("NativeMachineOperations.swift"))
        let checking = try Data(contentsOf: library.appendingPathComponent("CheckingContext.swift"))
        let proof = try #require(try SequentialControlOutputEvidence.proof(authoredSource: authored,
            modelName: modelName, spec: FinishingLoop.spec, rendered: rendered,
            native: (Data(members.utf8), operations, checking)))
        let rejected = members.replacingOccurrences(of: "try SwiftTLA._nativeIntAdd(", with: "try SwiftTLA._nativeIntSubtract(")
        #expect(rejected != members)
        #expect(throws: InitialFailureEvidenceError.unsupportedGeneratedOutput) {
            try SequentialControlOutputEvidence.proof(authoredSource: authored, modelName: modelName,
                spec: FinishingLoop.spec, rendered: rendered, native: (Data(rejected.utf8), operations, checking))
        }
        let module = rendered.tlaBundle.root
        let cfg = try #require(module.cfg)
#if compiler(>=6.2)
        Attachment.record(Array(authored), named: fixture.lastPathComponent)
        Attachment.record(Array(members.utf8), named: "FinishingLoopNativeMembers.swift")
        Attachment.record(Array(module.tla.utf8), named: "\(module.name).tla")
        Attachment.record(Array(cfg.utf8), named: "\(module.name).cfg")
        Attachment.record(Array(proof.control), named: "\(proof.controlModule).tla")
        Attachment.record(Array(proof.configured), named: "\(proof.configuredModule).tla")
#else
        _ = (cfg, proof)
#endif
    }

    @Test("Sequential control proof binds overwritten write targets in source order")
    func rejectsSwappedOverwrittenWriteTargets() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("SequentialLoopControlFixtures.swift")
        let source = try String(contentsOf: fixture, encoding: .utf8)
        let loop = "While(Step.advance, value < 1) {\n                    Assign(value, to: value + 1)"
        try #require(source.components(separatedBy: loop).count == 2)

        func variant(first: String, second: String) -> String {
            source.replacingOccurrences(of: loop, with: """
            let other = scope.sharedVar(_name: "other", initial: 0)
            While(Step.advance, value < 1) {
                Assign(\(first), to: 1)
                Assign(\(second), to: 1)
                Assign(value, to: 2)
                Assign(other, to: 2)
            """)
        }

        func compile(_ source: String) throws -> (TLASpec, RenderedSpecification, SequentialControlEvidence.Machine) {
            let declaration = try #require(Parser.parse(source: source).statements.compactMap {
                $0.item.as(StructDeclSyntax.self)
            }.first { $0.name.text == "FinishingLoop" })
            let model = try ModelSpecificationSyntax.find(in: declaration.memberBlock.members, defaultName: declaration.name.text)
            let enums = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
            let spec = SpecParser.parseSpecClosure(named: model.name, model.closure, sourceTypes: .init(enums: enums))
            let (compilation, evidence) = try spec.compileRetainingSequentialControl()
            let control = try #require(evidence)
            let effectiveTrace = try #require(control.authored.canonicalTraces(sourceWrites: true))
            return (spec, try compilation.render(), effectiveTrace)
        }

        let original = variant(first: "value", second: "other")
        let swapped = variant(first: "other", second: "value")
        try #require(original != source && swapped != original)
        let (spec, rendered, effectiveTrace) = try compile(original)
        let (_, _, swappedEffectiveTrace) = try compile(swapped)
        try #require(effectiveTrace == swappedEffectiveTrace)

        let matched = try SequentialControlOutputEvidence.proof(authoredSource: Data(original.utf8),
            modelName: "FinishingLoop", spec: spec, rendered: rendered)
        try #require(matched != nil)
        #expect(try SequentialControlOutputEvidence.proof(authoredSource: Data(swapped.utf8),
            modelName: "FinishingLoop", spec: spec, rendered: rendered) == nil)
    }
}
