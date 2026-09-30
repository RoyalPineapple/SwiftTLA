import Foundation
import SwiftTLA

package enum ValidationVerdict: String, Codable, Sendable {
    case satisfied
    case violated
    case reached
    case unreachable

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
    case expectationMismatch(String)
    case unavailable(String)
}

/// One generated-machine validation pass, with isolated follow-up runs only
/// when a decisive early result leaves another selected check unresolved.
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let batch = try MachineValidationEvidence.write(
            scenario: scenario, caseID: caseID, maximumStates: maximumStates, stopOnViolation: true,
            stopOnReachability: !safety.intersection(reachability).isEmpty,
            checking: .init(properties: safety, checkDeadlock: scenario.checking.checkDeadlock),
            to: directory.appendingPathComponent("machine.bin"))
        let complete: Bool
        switch batch.completion {
        case .exhausted: complete = true
        case .decisiveViolation, .decisiveReachability: complete = false
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
                if batch.violatedInvariants.contains(property) { verdict = .violated }
                else if complete { verdict = .satisfied }
                else {
                    let isolated = try MachineValidationEvidence.write(
                        scenario: scenario, caseID: caseID, maximumStates: maximumStates, stopOnViolation: true,
                        checking: .init(properties: [property], checkDeadlock: false),
                        to: directory.appendingPathComponent("check-\(name).bin"))
                    verdict = isolated.violatedInvariants.contains(property) ? .violated : .satisfied
                }
            } else if reachability.contains(property) {
                if batch.reachedProperties.contains(property) { verdict = .reached }
                else if complete { verdict = .unreachable }
                else {
                    let isolated = try MachineValidationEvidence.write(
                        scenario: scenario, caseID: caseID, maximumStates: maximumStates, stopOnViolation: true,
                        stopOnReachability: true,
                        checking: .init(properties: [property], checkDeadlock: false),
                        to: directory.appendingPathComponent("check-\(name).bin"))
                    verdict = isolated.reachedProperties.contains(property) ? .reached : .unreachable
                }
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
            guard scenario.expectations[property].map({ verdict.satisfies($0) }) == true else {
                throw NativeValidationRunnerError.expectationMismatch(name)
            }
            properties[name] = verdict
        }
        let deadlock: ValidationVerdict?
        if scenario.checking.checkDeadlock {
            if batch.deadlockFound { deadlock = .violated }
            else if complete { deadlock = .satisfied }
            else if !batch.violatedInvariants.isEmpty {
                deadlock = nil
            }
            else {
                let isolated = try MachineValidationEvidence.write(
                    scenario: scenario, caseID: caseID, maximumStates: maximumStates, stopOnViolation: true,
                    checking: .init(properties: [], checkDeadlock: true),
                    to: directory.appendingPathComponent("check-deadlock.bin"))
                deadlock = isolated.deadlockFound ? .violated : .satisfied
            }
            guard deadlock == nil || scenario.deadlockExpectation.map({ deadlock!.satisfies($0) }) == true else {
                throw NativeValidationRunnerError.expectationMismatch("deadlock")
            }
        } else {
            deadlock = nil
        }
        let report = NativeValidationReport(
            schema: "swifttla.native-validation-report", scenario: scenario.name,
            maximumStates: maximumStates,
            graphComplete: complete, initialStates: batch.initialStates,
            states: batch.states, edges: batch.edges,
            properties: properties, deadlock: deadlock,
            deadlockSelected: scenario.checking.checkDeadlock)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("report.json"), options: .atomic)
        return report
    }

}
