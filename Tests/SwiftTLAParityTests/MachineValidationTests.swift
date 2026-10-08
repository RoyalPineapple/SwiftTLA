import Testing
import SwiftTLA
@testable import UpstreamParity
import Foundation

struct MachineValidationTests {
    @Test("a model-owned postcondition reports the result after complete native exploration")
    func reportsPostconditionOutcome() throws {
        for (name, expected) in [("levelView", ValidationVerdict.satisfied),
                                 ("rejectedView", .violated)] {
            let scenario = try #require(ReachabilityExportModel.validationScenarios().first { $0.name == name })
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let report = try NativeValidationRunner.run(scenario: scenario, caseID: name,
                maximumStates: 4, to: directory)
            #expect(report.graphComplete)
            #expect(report.postcondition == expected)
            #expect(report.postcondition?.satisfies(try #require(scenario.postconditionExpectation)) == true)
        }
    }

    @Test("a typed view identifies explored states while evidence retains complete representatives")
    func exploresByViewWithoutProjectingStateEvents() throws {
        var states: [Int: Int] = [:]
        var edges: Set<String> = []
        let result = try MachineValidator.run(
            initialMachines: ReachabilityExportModel.initialMachines(), maximumStates: 3,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false,
            identity: { $0.state.value % 2 }
        ) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.value
            case .edge(let source, _, let target): edges.insert("\(source)->\(target)")
            default: break
            }
        }
        if case .exhausted = result.completion {} else { Issue.record("Expected completed view exploration") }
        #expect(result.states == 2)
        #expect(result.edges == 2)
        #expect(states == [0: 0, 1: 1])
        #expect(edges == ["0->1", "1->0"])
    }

    @Test("a view collision cannot admit a constrained-out successor or hide its invariant failure")
    func checksExcludedSuccessorsBeforeViewLookup() throws {
        let configuration = try ConstraintBoundaryCounter.Configuration(safetyLimit: 2)
        var edges: Set<String> = []
        var failures: [Int] = []
        let result = try MachineValidator.run(
            initialMachines: ConstraintBoundaryCounter.initialMachines(configuration: configuration),
            maximumStates: 3, checking: .init(properties: [.Bounded], checkDeadlock: false),
            stopOnViolation: false, identity: { $0.state.count % 2 }
        ) { event in
            switch event {
            case .edge(let source, _, let target): edges.insert("\(source)->\(target)")
            case .invariantFailure(_, let snapshot, _, _): failures.append(snapshot.state.count)
            default: break
            }
        }
        if case .exhausted = result.completion {} else { Issue.record("Expected completed view exploration") }
        #expect(result.states == 2)
        #expect(result.edges == 1)
        #expect(edges == ["0->1"])
        #expect(result.violatedInvariants == [.Bounded])
        #expect(failures == [2])
    }

    @Test("a view merges admitted initial states but still checks an excluded initial state")
    func checksInitialConstraintBeforeViewLookup() throws {
        var initialValues: [Int] = []
        var failures: [Int] = []
        let result = try MachineValidator.run(
            initialMachines: ConstraintInitialCounter.initialMachines(), maximumStates: 3,
            checking: .init(properties: [.Bounded], checkDeadlock: false),
            stopOnViolation: false, identity: { _ in 0 }
        ) { event in
            switch event {
            case .state(_, let snapshot, let initial, _, _) where initial:
                initialValues.append(snapshot.state.count)
            case .invariantFailure(_, let snapshot, _, _):
                failures.append(snapshot.state.count)
            default: break
            }
        }
        if case .exhausted = result.completion {} else { Issue.record("Expected completed view exploration") }
        #expect(result.initialStates == 1)
        #expect(result.states == 1)
        #expect(initialValues == [0])
        #expect(result.violatedInvariants == [.Bounded])
        #expect(failures == [2])
    }

    @Test("distinct generated states remain distinct when their snapshot hashes collide")
    func retainsFullStateIdentityAcrossHashCollisions() throws {
        let initial = try ReachabilityExportModel.initialMachines().map(CollidingReachabilityMachine.init(base:))
        var values: Set<Int> = []
        _ = try MachineValidator.run(
            initialMachines: initial, maximumStates: 3,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false
        ) { event in
            if case .state(_, let snapshot, _, _, _) = event {
                values.insert(snapshot.base.state.value)
            }
        }
        #expect(values == [0, 1, 2])
    }

    @Test("generated machine validation emits each reachable state and transition")
    func emitsCompleteFiniteBehavior() throws {
        var states: [Int: Int] = [:]
        var initials: Set<Int> = []
        var edges: Set<String> = []
        let initial = try ReachabilityExportModel.initialMachines()
        let result = try MachineValidator.run(
            initialMachines: initial + initial, maximumStates: 3,
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

    @Test("a generated-machine graph retains labeled edges and terminal states")
    func exposesCompleteLabeledGraph() throws {
        let graph = try MachineValidationGraph(
            initialMachines: ReachabilityExportModel.initialMachines(), maximumStates: 3)
        let transitions = graph.transitions
        #expect(Set(graph.initialStates.map(\.state.value)) == [0])
        #expect(Set(transitions.keys.map(\.state.value)) == [0, 1, 2])
        for value in 0..<2 {
            let edges = try #require(transitions.first { $0.key.state.value == value }?.value)
            #expect(edges.count == 1)
            #expect(edges[0].action == .advance)
            #expect(edges[0].target.state.value == value + 1)
        }
        #expect(transitions.first { $0.key.state.value == 2 }?.value.isEmpty == true)
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

    @Test("a decisive generated scenario reports its witness without exhausting an unbounded graph")
    func retainsDecisiveDieHardestResult() throws {
        let scenario = try #require(DieHardestModel.validationScenarios().first)
        #expect(scenario.checkingMode == .decisiveCounterexample)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = try NativeValidationRunner.run(
            scenario: scenario, caseID: "die-hardest-0", maximumStates: 100_000, to: directory)
        #expect(!report.graphComplete)
        #expect(report.properties["NotSolved"] == .violated)
        #expect(report.deadlock?.rawValue == "unavailable")
    }

    @Test("native evidence records a complete generated machine without TLC")
    func writesIndependentEvidence() throws {
        let scenario = RenderlessScenario(base: try ConfiguredCounter.validationScenarios()[0])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("native.bin")
        let summary = try MachineValidationEvidence.write(
            scenario: scenario, initialMachines: scenario.initialMachines(),
            caseID: "counter-0", maximumStates: 100,
            stopOnViolation: false, to: output)
        let evidence = try Data(contentsOf: output)
        let profileURL = output.deletingPathExtension().appendingPathExtension("profile.json")
        let profile = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: profileURL)) as? [String: Any])
        if case .exhausted = summary.completion {} else { Issue.record("Expected complete traversal") }
        #expect(summary.states >= 3)
        #expect(summary.edges >= 2)
        #expect(evidence.starts(with: Data("STLAGRF2".utf8)))
        #expect(evidence.count > 100)
        #expect(profile["schema"] as? String == "swifttla.native-validation-profile.v3")
        #expect(profile["seenHashSeconds"] as? Double != nil)
        #expect(profile["seenProbeSeconds"] as? Double != nil)
        #expect(profile["estimatedTypedProjectionSeconds"] as? Double != nil)
        #expect(profile["estimatedCanonicalEncodingSeconds"] as? Double != nil)
        #expect(profile["stateEvents"] as? Int == summary.states)
        #expect(profile["edgeEvents"] as? Int == summary.edges)
    }

    @Test("binary view evidence uses the same checking level as native state identity")
    func recordsCheckerLevelInViewEvidence() throws {
        let scenario = try #require(ReachabilityExportModel.validationScenarios().first)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("native.bin")
        var snapshots: [ReachabilityExportModel.Snapshot] = []
        let summary = try MachineValidationEvidence.write(
            scenario: scenario, initialMachines: scenario.initialMachines(),
            caseID: "level-view", maximumStates: 4, stopOnViolation: false, to: output
        ) { event in
            if case .state(_, let snapshot, _, _, _) = event { snapshots.append(snapshot) }
        }
        #expect(summary.states == 3)
        #expect(summary.edges == 2)
        #expect(summary.maximumLevel == 3)
        #expect(try scenario.postconditionSatisfied(after: summary) == true)
        let rendered = try scenario.render().tlaBundle
        #expect(rendered.cfg.contains("POSTCONDITION TraceAccepted"))
        #expect(rendered.tla.contains("TraceAccepted =="))
        #expect(rendered.tla.contains("TLCGet(\"stats\").diameter"))

        var reader = try BinaryGraphEvidenceReader(output)
        defer { reader.close() }
        #expect(try reader.bytes(8) == Data("STLAGRF2".utf8))
        #expect(try reader.byte() == 2)
        #expect(try reader.string() == "level-view")
        #expect(try reader.string().isEmpty)
        var keys: [Data] = []
        while keys.count < summary.states {
            switch try reader.byte() {
            case 1:
                _ = try reader.uint32()
                _ = try reader.string()
                _ = try reader.string()
            case 2:
                #expect(try reader.uint64() == UInt64(keys.count))
                _ = try reader.byte()
                keys.append(try reader.bytes(Int(reader.uint32())))
            case 3:
                _ = try reader.uint64()
                _ = try reader.uint32()
                _ = try reader.uint64()
            case 9:
                _ = try reader.uint64()
                _ = try reader.bytes(Int(reader.uint32()))
            default:
                Issue.record("Unexpected record before the complete view state set")
                return
            }
        }
        let machine = try #require(scenario.initialMachines().first)
        guard snapshots.count == keys.count else {
            Issue.record("Every retained view state needs one generated-machine snapshot")
            return
        }
        for (offset, snapshot) in snapshots.enumerated() {
            let projection = try scenario.formalIdentityProjection(of: snapshot, using: machine,
                atLevel: offset + 1)
            #expect(try keys[offset] == CanonicalBinaryState.encode(projection, viewed: true))
        }
    }

    @Test("generated assertions and reachability retain all selected scenario outcomes")
    func validatesConfiguredCounter() throws {
        let scenario = try ConfiguredCounter.validationScenarios()[0]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = try NativeValidationRunner.run(scenario: scenario, caseID: "counter-0",
            maximumStates: 100, to: directory)
        var evidence = try BinaryGraphEvidenceReader(directory.appendingPathComponent("machine.bin.gz"))
        #expect(try evidence.bytes(8) == Data("STLAGRF2".utf8))
        #expect(try evidence.byte() == 2)
        #expect(try evidence.string() == "counter-0")
        evidence.close()
        #expect(report.properties["__pcal_assert_0"] == .satisfied)
        #expect(report.properties["AtLimit"] == .reached)
        #expect(report.deadlock == .satisfied)
        #expect(report.graphComplete)
    }

    @Test("a state limit cannot satisfy an expected invariant violation")
    func rejectsLimitedExpectedFailure() throws {
        let scenario = try #require(TraceReplayCounter.validationScenarios().first)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: ExplorationError.stateLimitExceeded(1)) {
            try NativeValidationRunner.run(scenario: scenario, caseID: "limited-counter",
                maximumStates: 1, to: directory)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("report.json").path))
    }

    @Test("an invariant violation retains the complete graph and every selected verdict")
    func retainsCompleteEvidenceAfterInvariantViolation() throws {
        let scenario = try ConstantStateClaims.validationScenarios()[0]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let changedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: changedDirectory)
        }
        let report = try NativeValidationRunner.run(scenario: scenario, caseID: "constant-state-claims-0",
            maximumStates: 10, to: directory)
        #expect(report.graphComplete)
        #expect(report.initialStates == 1)
        #expect(report.states == 1)
        #expect(report.edges == 1)
        #expect(report.properties["falseInvariant"] == .violated)
        #expect(report.properties["trueInvariant"] == .satisfied)
        #expect(report.properties["initialWitness"] == .reached)
        #expect(report.properties["absentWitness"] == .unreachable)
        #expect(report.deadlockSelected)
        #expect(report.deadlock == .satisfied)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("report.json").path))

        var expectations = scenario.expectations
        expectations[.falseInvariant] = .satisfied
        let changed = ConstantStateClaims.ValidationScenario(
            name: scenario.name, displayName: scenario.displayName, configuration: scenario.configuration,
            checking: scenario.checking, checkingMode: scenario.checkingMode, behavior: scenario.behavior,
            selectedSymmetry: scenario.selectedSymmetry,
            selectedFairnessProfile: scenario.selectedFairnessProfile,
            selectedFairnessProfileName: scenario.selectedFairnessProfileName,
            selectedView: scenario.selectedView,
            selectedPostcondition: scenario.selectedPostcondition,
            postconditionName: scenario.postconditionName,
            postconditionExpectation: scenario.postconditionExpectation,
            expectations: expectations, deadlockExpectation: scenario.deadlockExpectation)
        let changedReport = try NativeValidationRunner.run(
            scenario: changed, caseID: "constant-state-claims-0", maximumStates: 10,
            to: changedDirectory)
        #expect(changedReport.properties == report.properties)
        #expect(changedReport.graphComplete == report.graphComplete)
        #expect(FileManager.default.fileExists(atPath: changedDirectory.appendingPathComponent("report.json").path))
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
            scenario: temporal, caseID: "selected-checks-0", maximumStates: 10, to: temporalDirectory)
        let refinementReport = try NativeValidationRunner.run(
            scenario: refinement, caseID: "refinement-counter-1", maximumStates: 10,
            to: refinementDirectory)
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
    var displayName: String { base.displayName }
    var checking: ModelChecks<Property> { base.checking }
    var behavior: ModelBehavior { base.behavior }
    var expectations: [Property: ValidationExpectation] { base.expectations }
    var deadlockExpectation: ValidationExpectation? { base.deadlockExpectation }
    var formalPropertyNames: [Property: String] { base.formalPropertyNames }
    func initialMachines() throws -> [Machine] { try base.initialMachines() }
    func render() throws -> RenderedSpecification { throw RenderlessError.called }
}

private enum RenderlessError: Error { case called }
