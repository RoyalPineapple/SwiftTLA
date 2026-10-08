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
    package let postconditionName: String?
    package let postcondition: ValidationVerdict?
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
              scenario.postconditionName == (try scenario.render()).postconditionName,
              (scenario.postconditionExpectation != nil) == (scenario.postconditionName != nil),
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
        guard !decisive || scenario.postconditionName == nil else {
            throw NativeValidationRunnerError.unavailable("postcondition requires exhaustive exploration")
        }
        guard !decisive || (safety.count == 1 && scenario.checking.properties == safety) else {
            throw NativeValidationRunnerError.unavailable("decisive mode requires one selected safety check")
        }
        let needsGraph = !scenario.checking.properties.intersection(temporal.union(refinement)).isEmpty
        var capture = MachineValidationGraphCapture<Scenario.Machine>()
        let observe: ((MachineValidationEvent<Scenario.Machine>) throws -> Void)? = needsGraph ? { event in
            try capture.observe(event)
        } : nil
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let batch = try MachineValidationEvidence.write(
            scenario: scenario, initialMachines: initial, caseID: caseID,
            maximumStates: maximumStates, stopOnViolation: decisive,
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
            var complete = try MachineValidationGraph(machine: first, capture: capture,
                behavior: scenario.behavior, fairness: fairness)
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
        let postcondition: ValidationVerdict?
        if scenario.postconditionName != nil {
            guard let satisfied = try scenario.postconditionSatisfied(after: batch) else {
                throw NativeValidationRunnerError.unavailable("postcondition requires complete exploration")
            }
            postcondition = satisfied ? .satisfied : .violated
        } else {
            postcondition = nil
        }
        let report = NativeValidationReport(
            schema: "swifttla.native-validation-report", scenario: scenario.name,
            maximumStates: maximumStates,
            graphComplete: !decisive, initialStates: batch.initialStates,
            states: batch.states, edges: batch.edges,
            properties: properties, deadlock: deadlock,
            deadlockSelected: scenario.checking.checkDeadlock,
            postconditionName: scenario.postconditionName, postcondition: postcondition)
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
        guard scenario.postconditionName == nil else {
            throw NativeValidationRunnerError.unavailable("postcondition requires exhaustive exploration")
        }
        var generator = SampleGenerator()
        let initial = try scenario.initialMachines()
        guard let first = initial.first else { throw ExplorationError.noInitialStates }
        let names = scenario.formalPropertyNames
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let tracesURL = directory.appendingPathComponent("sampled-traces.jsonl")
        try Data().write(to: tracesURL, options: .atomic)
        let tracesFile = try FileHandle(forWritingTo: tracesURL)
        defer { try? tracesFile.close() }
        var sampledTraceCount = 0
        var sampledStateCount = 0
        var sampledEdgeCount = 0
        func retain(_ sampled: NativeSimulationResult<Scenario.Machine>) throws {
            let kind: String
            let property: String
            let trace: [(action: Scenario.Machine.Action?, state: Scenario.Machine.Snapshot)]
            switch sampled {
            case .counterexample(let witness):
                kind = witness.violations.contains(.deadlock) ? "deadlock" : "violation"
                property = witness.violations.compactMap { violation -> String? in
                    if case .invariant(let selected) = violation { return names[selected] }
                    return nil
                }.sorted().first ?? (kind == "deadlock" ? "deadlock" : "")
                trace = witness.trace
            case .temporalCounterexample(let selected, _, let sampledTrace):
                kind = "temporal-violation"
                property = names[selected]!
                trace = sampledTrace
            case .inconclusive(let sampledTrace, _):
                kind = "inconclusive"
                property = ""
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
            let witness = SampledWitness(schema: "swifttla.native-sampled-trace", caseID: caseID,
                kind: kind, property: property, seed: 1,
                traces: traces, maximumDepth: maximumDepth, steps: steps)
            try tracesFile.write(contentsOf: encoder.encode(witness))
            try tracesFile.write(contentsOf: Data([0x0A]))
            sampledTraceCount += 1
            sampledStateCount += steps.count
            sampledEdgeCount += max(0, steps.count - 1)
        }
        let sampled = try scenario.simulate(initialMachines: initial, using: &generator, onTrace: retain)
        try tracesFile.synchronize()
        var properties = Dictionary(uniqueKeysWithValues: scenario.checking.properties.map {
            (names[$0]!, ValidationVerdict.unavailable)
        })
        var deadlock: ValidationVerdict? = scenario.checking.checkDeadlock ? .unavailable : nil
        switch sampled {
        case .counterexample(let witness):
            for violation in witness.violations {
                switch violation {
                case .invariant(let selected): properties[names[selected]!] = .violated
                case .deadlock: deadlock = .violated
                }
            }
        case .temporalCounterexample(let selected, _, _):
            properties[names[selected]!] = .violated
        case .inconclusive: break
        }
        let report = NativeValidationReport(
            schema: "swifttla.native-validation-report", scenario: scenario.name,
            maximumStates: maximumStates, graphComplete: false,
            initialStates: sampledTraceCount, states: sampledStateCount, edges: sampledEdgeCount,
            properties: properties, deadlock: deadlock,
            deadlockSelected: scenario.checking.checkDeadlock,
            postconditionName: nil, postcondition: nil)
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
        let evidence = try Data(contentsOf: directory.appendingPathComponent("sampled-traces.jsonl"))
        guard evidence.last == 0x0A else {
            throw NativeValidationRunnerError.invalidCoverage("incomplete sampled trace stream")
        }
        let witnesses = try evidence.split(separator: 0x0A).map {
            try JSONDecoder().decode(SampledWitness.self, from: Data($0))
        }
        guard let witness = witnesses.last, witnesses.count <= traces,
              witnesses.dropLast().allSatisfy({ $0.kind == "inconclusive" && $0.property.isEmpty }),
              witnesses.allSatisfy({ candidate in
                  candidate.schema == "swifttla.native-sampled-trace"
                      && candidate.caseID == caseID && candidate.seed == 1
                      && candidate.traces == traces && candidate.maximumDepth == maximumDepth
                      && !candidate.steps.isEmpty
                      && candidate.steps.count - 1 <= maximumDepth
                      && candidate.steps.first?.action?.name == nil
              }),
              report.initialStates == witnesses.count,
              report.states == witnesses.reduce(0, { $0 + $1.steps.count }),
              report.edges == witnesses.reduce(0, { $0 + $1.steps.count - 1 }) else {
            throw NativeValidationRunnerError.invalidCoverage("sampled native trace stream")
        }
        guard witness.schema == "swifttla.native-sampled-trace", witness.caseID == caseID,
              witness.kind == "violation", witness.seed == 1,
              witness.traces == traces, witness.maximumDepth == maximumDepth,
              !witness.steps.isEmpty, witness.steps.count - 1 <= maximumDepth,
              witness.steps.first?.action?.name == nil else {
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
