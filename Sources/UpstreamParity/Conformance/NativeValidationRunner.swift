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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let batch = try MachineValidationEvidence.write(
            scenario: scenario, caseID: caseID, maximumStates: maximumStates, stopOnViolation: decisive,
            stopOnReachability: decisive,
            checking: .init(properties: safety, checkDeadlock: scenario.checking.checkDeadlock),
            to: directory.appendingPathComponent("machine.bin"))
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
        if !scenario.checking.properties.intersection(temporal.union(refinement)).isEmpty {
            var complete = try MachineValidationGraph(initialMachines: initial,
                maximumStates: maximumStates, behavior: scenario.behavior)
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

}
