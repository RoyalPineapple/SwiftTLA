import Foundation
import SwiftTLA

package enum ValidationVerdict: String, Codable, Sendable {
    case satisfied
    case violated
    case reached
    case unreachable
    case unavailable

    package func satisfies(_ expected: ValidationExpectation) -> Bool {
        switch (expected, self) {
        case (.satisfied, .satisfied), (.satisfied, .reached),
             (.violated, .violated), (.violated, .unreachable): true
        default: false
        }
    }
}

package struct NativeValidationReport: Codable, Sendable {
    package let schema: String
    package let scenario: String
    package let maximumStates: Int
    package let graphComplete: Bool
    package let initialStates: Int
    package let states: Int
    package let edges: Int
    package let properties: [String: ValidationVerdict]
    package let deadlock: ValidationVerdict?
    package let deadlockSelected: Bool
}

package enum NativeValidationRunnerError: Error, Equatable {
    case invalidCoverage(String)
    case unavailable(String)
}

/// One generated-machine pass records either a complete graph or a decisive witness.
package enum NativeValidationRunner {
    package static func run<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, maximumStates: Int, to directory: URL
    ) throws -> NativeValidationReport {
        let names = scenario.formalPropertyNames
        guard names == Scenario.Machine.formalPropertyNames,
              Set(names.keys) == Set(Scenario.Property.allCases),
              Set(names.values).count == names.count,
              names.values.allSatisfy({
                  $0.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
              }),
              scenario.checking.properties == Set(scenario.expectations.keys),
              (scenario.deadlockExpectation != nil) == scenario.checking.checkDeadlock else {
            throw NativeValidationRunnerError.invalidCoverage(scenario.name)
        }
        if case .simulation(let traces, let maximumDepth) = scenario.checkingMode {
            return try runSimulation(scenario: scenario, caseID: caseID,
                maximumStates: maximumStates, traces: traces, maximumDepth: maximumDepth,
                to: directory)
        }
        let initial = try scenario.initialMachines()
        guard let first = initial.first else { throw ExplorationError.noInitialStates }
        let invariant = Set(Scenario.Machine.invariantProperties)
        let reachability = Set(Scenario.Machine.reachabilityProperties)
        let temporal = Set(try first.temporalProperties(checking: scenario.checking.properties).keys)
        let refinement = Set(Scenario.Machine.refinementProperties)
        let supported = invariant.union(reachability).union(temporal).union(refinement)
        if let property = scenario.checking.properties.subtracting(supported).first {
            throw ExplorationError.unsupportedValidationProperty(names[property]!)
        }
        let safety = scenario.checking.properties.intersection(invariant.union(reachability))
        let decisive = scenario.checkingMode == .decisiveCounterexample
        guard !decisive || (safety.count == 1 && scenario.checking.properties == safety) else {
            throw NativeValidationRunnerError.unavailable("decisive mode requires one selected safety check")
        }
        let needsGraph = !scenario.checking.properties.intersection(temporal.union(refinement)).isEmpty
        var snapshots: [Scenario.Machine.Snapshot] = []
        var initialStates: Set<Scenario.Machine.Snapshot> = []
        var transitions: [Scenario.Machine.Snapshot: [(action: Scenario.Machine.Action, target: Scenario.Machine.Snapshot)]] = [:]
        let observe: ((MachineValidationEvent<Scenario.Machine>) throws -> Void)? = needsGraph ? { event in
            switch event {
            case .state(let id, let snapshot, let initial, _, _):
                guard id == snapshots.count else { throw ExplorationError.configurationMismatch }
                snapshots.append(snapshot)
                guard transitions.updateValue([], forKey: snapshot) == nil else {
                    throw ExplorationError.configurationMismatch
                }
                if initial { initialStates.insert(snapshot) }
            case .edge(let source, let action, let target):
                guard snapshots.indices.contains(source), snapshots.indices.contains(target) else {
                    throw ExplorationError.configurationMismatch
                }
                transitions[snapshots[source], default: []].append((action, snapshots[target]))
            default: break
            }
        } : nil
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let batch = try MachineValidationEvidence.write(
            scenario: scenario, caseID: caseID, maximumStates: maximumStates, stopOnViolation: decisive,
            stopOnReachability: decisive,
            checking: .init(properties: safety, checkDeadlock: scenario.checking.checkDeadlock),
            to: directory.appendingPathComponent("machine.bin.gz"), observe: observe)
        switch (scenario.checkingMode, batch.completion) {
        case (.exhaustive, .exhausted),
             (.decisiveCounterexample, .decisiveViolation),
             (.decisiveCounterexample, .decisiveReachability): break
        default: throw NativeValidationRunnerError.unavailable("declared checking outcome")
        }
        if decisive, batch.violatedInvariants.isEmpty && batch.reachedProperties.isEmpty {
            throw NativeValidationRunnerError.unavailable("selected decisive safety witness")
        }
        var temporalResults: [Scenario.Property: TemporalAnalysis<Scenario.Machine.Snapshot, Scenario.Machine.Action?>] = [:]
        var refinementFailures: [Scenario.Property: RefinementFailure<Scenario.Machine.Snapshot, Scenario.Machine.Action>] = [:]
        if needsGraph {
            let fairness = scenario.behavior == .specification
                ? try scenario.fairnessConditions(on: first) : []
            var complete = MachineValidationGraph(machine: first, initialStates: initialStates,
                transitions: transitions, behavior: scenario.behavior, fairness: fairness)
            temporalResults = try complete.temporalResults(checking: scenario.checking.properties)
            refinementFailures = try first.validationRefinementFailures(
                in: &complete, checking: scenario.checking.properties)
        }
        var properties: [String: ValidationVerdict] = [:]
        for property in scenario.checking.properties.sorted(by: { names[$0]! < names[$1]! }) {
            let name = names[property]!
            let verdict: ValidationVerdict
            if invariant.contains(property) {
                verdict = batch.violatedInvariants.contains(property) ? .violated : .satisfied
            } else if reachability.contains(property) {
                verdict = batch.reachedProperties.contains(property) ? .reached : .unreachable
            } else if let analysis = temporalResults[property] {
                switch analysis.status {
                case .satisfied: verdict = .satisfied
                case .violated: verdict = .violated
                case .unavailable: throw NativeValidationRunnerError.unavailable(name)
                }
            } else if refinement.contains(property) {
                verdict = refinementFailures[property] == nil ? .satisfied : .violated
            } else {
                throw ExplorationError.unsupportedValidationProperty(name)
            }
            properties[name] = verdict
        }
        let deadlock: ValidationVerdict?
        if scenario.checking.checkDeadlock {
            deadlock = batch.deadlockFound ? .violated : decisive ? .unavailable : .satisfied
        } else {
            deadlock = nil
        }
        let report = NativeValidationReport(
            schema: "swifttla.native-validation-report", scenario: scenario.name,
            maximumStates: maximumStates,
            graphComplete: !decisive, initialStates: batch.initialStates,
            states: batch.states, edges: batch.edges,
            properties: properties, deadlock: deadlock,
            deadlockSelected: scenario.checking.checkDeadlock)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        return report
    }

    private struct SampledWitness: Codable {
        let schema: String
        let caseID: String
        let kind: String
        let property: String
        let seed: UInt64
        let traces: Int
        let maximumDepth: Int
        let steps: [Step]

        struct Step: Codable {
            let action: Action?
            let state: [String: TLAValue]
        }

        struct Action: Codable {
            let name: String
            let arguments: [TLAValue]
        }
    }

    private struct SampleGenerator: RandomNumberGenerator {
        var state: UInt64 = 1

        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var value = state
            value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
            value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
            return value ^ (value >> 31)
        }
    }

    private static func runSimulation<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, maximumStates: Int,
        traces: Int, maximumDepth: Int, to directory: URL
    ) throws -> NativeValidationReport {
        var generator = SampleGenerator()
        let initial = try scenario.initialMachines()
        guard let first = initial.first else { throw ExplorationError.noInitialStates }
        let sampled = try scenario.simulate(initialMachines: initial, using: &generator)
        let names = scenario.formalPropertyNames
        var properties = Dictionary(uniqueKeysWithValues: scenario.checking.properties.map {
            (names[$0]!, ValidationVerdict.unavailable)
        })
        var deadlock: ValidationVerdict? = scenario.checking.checkDeadlock ? .unavailable : nil
        let kind: String?
        let property: String?
        let trace: [(action: Scenario.Machine.Action?, state: Scenario.Machine.Snapshot)]
        switch sampled {
        case .counterexample(let witness):
            for violation in witness.violations {
                switch violation {
                case .invariant(let selected): properties[names[selected]!] = .violated
                case .deadlock: deadlock = .violated
                }
            }
            kind = witness.violations.contains(.deadlock) ? "deadlock" : "violation"
            property = witness.violations.compactMap { violation -> String? in
                if case .invariant(let selected) = violation { return names[selected] }
                return nil
            }.sorted().first ?? (deadlock == .violated ? "deadlock" : nil)
            trace = witness.trace
        case .temporalCounterexample(let selected, _, let sampledTrace):
            properties[names[selected]!] = .violated
            kind = "temporal-violation"
            property = names[selected]
            trace = sampledTrace
        case .inconclusive(let sampledTrace, _):
            kind = nil
            property = nil
            trace = sampledTrace
        }
        let steps = try trace.map { step -> SampledWitness.Step in
            let action = try step.action.map { selected -> SampledWitness.Action in
                let call = try first.formalCall(for: selected)
                return .init(name: call.name, arguments: call.arguments)
            }
            let projection = try first.formalProjection(of: step.state)
            return .init(action: action,
                state: Dictionary(uniqueKeysWithValues: projection.entries.map {
                    ($0.token.description, $0.value)
                }))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let witness = SampledWitness(schema: "swifttla.native-sampled-trace", caseID: caseID,
            kind: kind ?? "inconclusive", property: property ?? "", seed: 1,
            traces: traces, maximumDepth: maximumDepth, steps: steps)
        try encoder.encode(witness).write(to: directory.appendingPathComponent("sampled-trace.json"), options: .atomic)
        let report = NativeValidationReport(
            schema: "swifttla.native-validation-report", scenario: scenario.name,
            maximumStates: maximumStates, graphComplete: false,
            initialStates: 1, states: steps.count, edges: max(0, steps.count - 1),
            properties: properties, deadlock: deadlock,
            deadlockSelected: scenario.checking.checkDeadlock)
        try encoder.encode(report).write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        return report
    }

    package static func verifySampledWitness<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, report: NativeValidationReport,
        in directory: URL
    ) throws {
        guard case .simulation(let traces, let maximumDepth) = scenario.checkingMode,
              !report.graphComplete, report.scenario == scenario.name,
              report.properties.values.contains(.violated) else {
            throw NativeValidationRunnerError.invalidCoverage("sampled native report")
        }
        let witness = try JSONDecoder().decode(SampledWitness.self,
            from: Data(contentsOf: directory.appendingPathComponent("sampled-trace.json")))
        guard witness.schema == "swifttla.native-sampled-trace", witness.caseID == caseID,
              witness.kind == "violation", witness.seed == 1,
              witness.traces == traces, witness.maximumDepth == maximumDepth,
              !witness.steps.isEmpty, witness.steps.count - 1 <= maximumDepth,
              witness.steps.first?.action?.name == nil,
              report.initialStates == 1, report.states == witness.steps.count,
              report.edges == witness.steps.count - 1 else {
            throw NativeValidationRunnerError.invalidCoverage("sampled native trace")
        }
        let initial = try scenario.initialMachines()
        guard let first = initial.first else { throw ExplorationError.noInitialStates }
        var context = CheckingContext(registers: try first.initialCheckingRegisters())
        try context.advanceLevel()
        func projected(_ machine: Scenario.Machine) throws -> [String: TLAValue] {
            let projection = try first.formalProjection(of: machine.snapshot)
            return Dictionary(uniqueKeysWithValues: projection.entries.map {
                ($0.token.description, $0.value)
            })
        }
        let starting = try initial.filter { try projected($0) == witness.steps[0].state }
        guard starting.count == 1, let start = starting.first,
              try start.assumptionsHold(), try start.satisfiesStateConstraint() else {
            throw NativeValidationRunnerError.invalidCoverage("sampled initial state")
        }
        var machine = start
        for step in witness.steps.dropFirst() {
            guard let action = step.action else {
                throw NativeValidationRunnerError.invalidCoverage("sampled action")
            }
            let matches = try machine.successors(checking: &context).filter { candidate in
                let call = try first.formalCall(for: candidate.action)
                guard call.name == action.name, call.arguments == action.arguments,
                      try projected(candidate.machine) == step.state else { return false }
                return try candidate.machine.satisfiesStateConstraint()
            }
            let distinct = Dictionary(grouping: matches, by: { $0.machine.snapshot })
            guard distinct.count == 1, let next = distinct.values.first?.first?.machine,
                  next.hasSameConfiguration(as: first) else {
                throw NativeValidationRunnerError.invalidCoverage("sampled transition")
            }
            machine = next
            try context.advanceLevel()
        }
        let names = scenario.formalPropertyNames
        guard let property = scenario.checking.properties.first(where: { names[$0] == witness.property }),
              report.properties[witness.property] == .violated,
              try machine.violatedInvariants(checking: [property], atLevel: witness.steps.count)
                  .contains(property) else {
            throw NativeValidationRunnerError.invalidCoverage("sampled invariant witness")
        }
    }

}
