import Testing
import SwiftTLA
@testable import UpstreamParity
import Foundation

struct MachineValidationTests {
    @Test("generated machine validation emits each reachable state and transition")
    func emitsCompleteFiniteBehavior() throws {
        var states: [Int: Int] = [:]
        var initials: Set<Int> = []
        var edges: Set<String> = []
        let result = try MachineValidator.run(
            initialMachines: ReachabilityExportModel.initialMachines(), maximumStates: 3,
            checking: .init(properties: [.Positive, .BeyondLimit], checkDeadlock: false),
            stopOnViolation: false
        ) { event in
            switch event {
            case .state(let id, let snapshot, let initial, _, _):
                states[id] = snapshot.state.value
                if initial { initials.insert(id) }
            case .edge(let source, _, let target):
                edges.insert("\(source)->\(target)")
            default: break
            }
        }
        if case .exhausted = result.completion {} else { Issue.record("Validation stopped early") }
        #expect(result.initialStates == 1)
        #expect(result.states == 3)
        #expect(result.edges == 2)
        #expect(initials.count == 1)
        #expect(states.values.sorted() == [0, 1, 2])
        #expect(edges == ["0->1", "1->2"])
        #expect(result.reachedProperties == [.Positive])
    }

    @Test("a decisive invariant failure retains the generated successor outside the completed graph")
    func stopsAtGeneratedViolation() throws {
        var failure: (value: Int, predecessor: Int?)?
        let result = try MachineValidator.run(
            initialMachines: FailingExportModel.initialMachines(), maximumStates: 3,
            checking: .init(properties: [.BelowTwo, .BelowThree], checkDeadlock: false),
            stopOnViolation: true
        ) { event in
            if case .invariantFailure(let property, let snapshot, let predecessor, _) = event,
               property == .BelowTwo {
                failure = (snapshot.state.value, predecessor)
            }
        }
        if case .decisiveViolation = result.completion {} else { Issue.record("Expected an early violation") }
        #expect(result.violatedInvariants == [.BelowTwo])
        #expect(failure?.value == 2)
        #expect(failure?.predecessor != nil)
        #expect(result.states == 2)
        #expect(result.edges == 0)
    }

    @Test("a selected reachability witness stops without claiming a complete graph")
    func stopsAtReachabilityWitness() throws {
        var witnessed: Int?
        let result = try MachineValidator.run(
            initialMachines: ReachabilityExportModel.initialMachines(), maximumStates: 3,
            checking: .init(properties: [.Positive], checkDeadlock: false),
            stopOnViolation: true, stopOnReachability: true
        ) { event in
            if case .reachability(_, let snapshot, _, _) = event {
                witnessed = snapshot.state.value
            }
        }
        if case .decisiveReachability = result.completion {} else {
            Issue.record("A reachability witness is not exhaustive completion")
        }
        #expect(witnessed == 1)
        #expect(result.reachedProperties == [.Positive])
        #expect(result.states < 3)
    }

    @Test("native evidence records a complete generated machine without TLC")
    func writesIndependentEvidence() throws {
        let scenario = RenderlessScenario(base: try ConfiguredCounter.validationScenarios()[0])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("native.jsonl")
        let summary = try MachineValidationEvidence.write(
            scenario: scenario, maximumStates: 100, stopOnViolation: false, to: output)
        let evidence = try String(contentsOf: output)
        if case .exhausted = summary.completion {} else { Issue.record("Expected complete traversal") }
        #expect(summary.states >= 3)
        #expect(summary.edges >= 2)
        #expect(evidence.contains("\"type\":\"header\""))
        #expect(evidence.contains("\"type\":\"state\""))
        #expect(evidence.contains("\"type\":\"edge\""))
        #expect(evidence.contains("\"type\":\"complete\""))
    }

    @Test("generated assertions and reachability retain all selected scenario outcomes")
    func validatesConfiguredCounter() throws {
        let scenario = try ConfiguredCounter.validationScenarios()[0]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = try NativeValidationRunner.run(scenario: scenario, maximumStates: 100, to: directory)
        #expect(report.properties["__pcal_assert_0"] == .satisfied)
        #expect(report.properties["AtLimit"] == .reached)
        #expect(report.deadlock == .satisfied)
        #expect(!report.graphComplete)
    }

    @Test("early violations are isolated before every selected check receives a verdict")
    func resolvesChecksAfterEarlyViolation() throws {
        let scenario = try ConstantStateClaims.validationScenarios()[0]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = try NativeValidationRunner.run(scenario: scenario, maximumStates: 10, to: directory)
        #expect(!report.graphComplete)
        #expect(report.properties["falseInvariant"] == .violated)
        #expect(report.properties["trueInvariant"] == .satisfied)
        #expect(report.properties["initialWitness"] == .reached)
        #expect(report.properties["absentWitness"] == .unreachable)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("check-absentWitness.jsonl").path))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("report.json").path))
    }

    @Test("selected temporal and refinement checks use the generated-machine graph")
    func checksGraphProperties() throws {
        let temporal = try SelectedChecksModel.validationScenarios()[0]
        let refinement = try RefinementScenarioCounter.validationScenarios()[1]
        let temporalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let refinementDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: temporalDirectory)
            try? FileManager.default.removeItem(at: refinementDirectory)
        }
        let temporalReport = try NativeValidationRunner.run(
            scenario: temporal, maximumStates: 10, to: temporalDirectory)
        let refinementReport = try NativeValidationRunner.run(
            scenario: refinement, maximumStates: 10, to: refinementDirectory)
        #expect(temporalReport.properties["StaysZero"] == .violated)
        #expect(refinementReport.properties["UnitSteps"] == .violated)
    }

    @Test("unsupported selected checks fail instead of receiving an unchecked pass")
    func rejectsUnsupportedChecks() throws {
        let scenario = try SelectedChecksModel.validationScenarios()[0]
        #expect(throws: ExplorationError.unsupportedValidationProperty("StaysZero")) {
            try MachineValidator.run(
                initialMachines: scenario.initialMachines(), maximumStates: 10,
                checking: scenario.checking, stopOnViolation: true
            ) { _ in }
        }
    }
}

private struct RenderlessScenario<Base: ModelValidationScenario>: ModelValidationScenario {
    typealias Machine = Base.Machine
    typealias Property = Base.Property
    let base: Base
    var name: String { base.name }
    var checking: ModelChecks<Property> { base.checking }
    var behavior: ModelBehavior { base.behavior }
    var expectations: [Property: ValidationExpectation] { base.expectations }
    var deadlockExpectation: ValidationExpectation? { base.deadlockExpectation }
    var formalPropertyNames: [Property: String] { base.formalPropertyNames }
    func initialMachines() throws -> [Machine] { try base.initialMachines() }
    func render() throws -> RenderedSpecification { throw RenderlessError.called }
}

private enum RenderlessError: Error { case called }
