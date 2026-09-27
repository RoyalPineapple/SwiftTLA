import Foundation
import SwiftTLA

package enum MachineValidationEvidenceError: Error, Equatable {
    case invalidPropertyName
}

/// Append-only evidence from the generated Swift machine. TLC is never read by this checker.
package enum MachineValidationEvidence {
    package static func write<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, maximumStates: Int, stopOnViolation: Bool,
        stopOnReachability: Bool = false,
        checking: ModelChecks<Scenario.Property>? = nil, to output: URL
    ) throws -> MachineValidationSummary<Scenario.Property> {
        let propertyNames = scenario.formalPropertyNames
        guard Set(propertyNames.keys) == Set(Scenario.Property.allCases),
              Set(propertyNames.values).count == propertyNames.count,
              propertyNames == Scenario.Machine.formalPropertyNames else {
            throw MachineValidationEvidenceError.invalidPropertyName
        }
        let checking = checking ?? scenario.checking
        guard checking.properties.isSubset(of: scenario.checking.properties),
              !checking.checkDeadlock || scenario.checking.checkDeadlock else {
            throw MachineValidationEvidenceError.invalidPropertyName
        }
        let initial = try scenario.initialMachines()
        guard let machine = initial.first else { throw ExplorationError.noInitialStates }
        var writer = try BinaryGraphEvidenceWriter(to: output, caseID: caseID)
        defer { writer.close() }
        var actionIDs: [Scenario.Machine.Action: UInt32] = [:]

        func actionID(_ action: Scenario.Machine.Action) throws -> UInt32 {
            if let id = actionIDs[action] { return id }
            guard let id = UInt32(exactly: actionIDs.count) else {
                throw BinaryGraphEvidenceError.invalid("action count")
            }
            actionIDs[action] = id
            try writer.action(id: id, name: machine.formalCall(for: action).description)
            return id
        }

        func stateKey(_ snapshot: Scenario.Machine.Snapshot) throws -> String {
            try CanonicalState(machine.formalProjection(of: snapshot)).key.canonicalEncoding
        }

        let result = try MachineValidator.run(
            initialMachines: initial, maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability
        ) { event in
            switch event {
            case .state(let id, let snapshot, let isInitial, _, _):
                try writer.state(id: UInt64(id), key: stateKey(snapshot), initial: isInitial)
            case .edge(let source, let action, let target):
                let action = try actionID(action)
                try writer.edge(source: UInt64(source), action: action, target: UInt64(target))
            case .invariantFailure(let property, let snapshot, let predecessor, let action):
                guard let name = propertyNames[property] else {
                    throw MachineValidationEvidenceError.invalidPropertyName
                }
                let action = try action.map(actionID)
                try writer.invariantFailure(property: name, key: stateKey(snapshot),
                    predecessor: predecessor.map(UInt64.init), action: action)
            case .deadlock(let state):
                try writer.deadlock(state: UInt64(state))
            case .reachability(let property, let snapshot, let predecessor, let action):
                guard let name = propertyNames[property] else {
                    throw MachineValidationEvidenceError.invalidPropertyName
                }
                let action = try action.map(actionID)
                try writer.reached(property: name, key: stateKey(snapshot),
                    predecessor: predecessor.map(UInt64.init), action: action)
            }
        }
        let completion: UInt8 = switch result.completion {
        case .exhausted: 0
        case .decisiveViolation: 1
        case .decisiveReachability: 2
        }
        try writer.finish(completion: completion)
        return result
    }
}
