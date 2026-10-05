import Dispatch
import Foundation
import SwiftTLA

package enum MachineValidationEvidenceError: Error, Equatable {
    case invalidPropertyName
}

private struct MachineValidationProfile: Encodable {
    let schema: String
    let caseID: String
    let elapsedSeconds: Double
    let explorationSeconds: Double
    let successorSeconds: Double
    let invariantSeconds: Double
    let reachabilitySeconds: Double
    let constraintSeconds: Double
    let seenLookupSeconds: Double
    let seenHashSeconds: Double
    let seenProbeSeconds: Double
    let seenInsertSeconds: Double
    let configurationSeconds: Double
    let eventSeconds: Double
    let successorCalls: Int
    let stateEvents: Int
    let edgeEvents: Int
    let sampledStates: Int
    let sampledEdges: Int
    let estimatedTypedProjectionSeconds: Double
    let estimatedCanonicalEncodingSeconds: Double
    let estimatedStateWriteSeconds: Double
    let estimatedEdgeWriteSeconds: Double
}

/// Append-only evidence from the generated Swift machine. TLC is never read by this checker.
package enum MachineValidationEvidence {
    package static func write<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, maximumStates: Int, stopOnViolation: Bool,
        stopOnReachability: Bool = false,
        checking: ModelChecks<Scenario.Property>? = nil, to output: URL,
        observe: ((MachineValidationEvent<Scenario.Machine>) throws -> Void)? = nil
    ) throws -> MachineValidationSummary<Scenario.Property> {
        let startedAt = DispatchTime.now().uptimeNanoseconds
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
        var stateEvents = 0
        var edgeEvents = 0
        var sampledStates = 0
        var sampledEdges = 0
        var typedProjectionNanoseconds: UInt64 = 0
        var canonicalEncodingNanoseconds: UInt64 = 0
        var stateWriteNanoseconds: UInt64 = 0
        var edgeWriteNanoseconds: UInt64 = 0
        var stateKeyBuffer = Data()

        func actionID(_ action: Scenario.Machine.Action) throws -> UInt32 {
            if let id = actionIDs[action] { return id }
            guard let id = UInt32(exactly: actionIDs.count) else {
                throw BinaryGraphEvidenceError.invalid("action count")
            }
            actionIDs[action] = id
            try writer.action(id: id, name: machine.formalCall(for: action).description)
            return id
        }

        func encodeStateKey(_ snapshot: Scenario.Machine.Snapshot) throws {
            try CanonicalBinaryState.encode(machine.formalProjection(of: snapshot), into: &stateKeyBuffer)
        }

        let result = try MachineValidator.run(
            initialMachines: initial, maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability
        ) { event in
            switch event {
            case .state(let id, let snapshot, let isInitial, _, _):
                stateEvents += 1
                if stateEvents % 256 == 1 {
                    sampledStates += 1
                    let projectionStartedAt = DispatchTime.now().uptimeNanoseconds
                    let projection = try machine.formalProjection(of: snapshot)
                    let encodingStartedAt = DispatchTime.now().uptimeNanoseconds
                    try CanonicalBinaryState.encode(projection, into: &stateKeyBuffer)
                    let writeStartedAt = DispatchTime.now().uptimeNanoseconds
                    try writer.state(id: UInt64(id), key: stateKeyBuffer, initial: isInitial)
                    let finishedAt = DispatchTime.now().uptimeNanoseconds
                    typedProjectionNanoseconds += encodingStartedAt - projectionStartedAt
                    canonicalEncodingNanoseconds += writeStartedAt - encodingStartedAt
                    stateWriteNanoseconds += finishedAt - writeStartedAt
                } else {
                    try encodeStateKey(snapshot)
                    try writer.state(id: UInt64(id), key: stateKeyBuffer, initial: isInitial)
                }
            case .edge(let source, let action, let target):
                let action = try actionID(action)
                edgeEvents += 1
                if edgeEvents % 1024 == 1 {
                    sampledEdges += 1
                    let writeStartedAt = DispatchTime.now().uptimeNanoseconds
                    try writer.edge(source: UInt64(source), action: action, target: UInt64(target))
                    edgeWriteNanoseconds += DispatchTime.now().uptimeNanoseconds - writeStartedAt
                } else {
                    try writer.edge(source: UInt64(source), action: action, target: UInt64(target))
                }
            case .invariantFailure(let property, let snapshot, let predecessor, let action):
                guard let name = propertyNames[property] else {
                    throw MachineValidationEvidenceError.invalidPropertyName
                }
                let action = try action.map(actionID)
                try encodeStateKey(snapshot)
                try writer.invariantFailure(property: name, key: stateKeyBuffer,
                    predecessor: predecessor.map(UInt64.init), action: action)
            case .deadlock(let state):
                try writer.deadlock(state: UInt64(state))
            case .reachability(let property, let snapshot, let predecessor, let action):
                guard let name = propertyNames[property] else {
                    throw MachineValidationEvidenceError.invalidPropertyName
                }
                let action = try action.map(actionID)
                try encodeStateKey(snapshot)
                try writer.reached(property: name, key: stateKeyBuffer,
                    predecessor: predecessor.map(UInt64.init), action: action)
            }
            try observe?(event)
        }
        let completion: UInt8 = switch result.completion {
        case .exhausted: 0
        case .decisiveViolation: 1
        case .decisiveReachability: 2
        }
        try writer.finish(completion: completion)
        func seconds(_ nanoseconds: UInt64) -> Double { Double(nanoseconds) / 1_000_000_000 }
        func estimatedSeconds(_ nanoseconds: UInt64, samples: Int, total: Int) -> Double {
            guard samples > 0 else { return 0 }
            return seconds(nanoseconds) * Double(total) / Double(samples)
        }
        let profile = MachineValidationProfile(
            schema: "swifttla.native-validation-profile.v3", caseID: caseID,
            elapsedSeconds: seconds(DispatchTime.now().uptimeNanoseconds - startedAt),
            explorationSeconds: seconds(result.timing.elapsedNanoseconds),
            successorSeconds: seconds(result.timing.successorNanoseconds),
            invariantSeconds: seconds(result.timing.invariantNanoseconds),
            reachabilitySeconds: seconds(result.timing.reachabilityNanoseconds),
            constraintSeconds: seconds(result.timing.constraintNanoseconds),
            seenLookupSeconds: seconds(result.timing.seenLookupNanoseconds),
            seenHashSeconds: seconds(result.timing.seenHashNanoseconds),
            seenProbeSeconds: seconds(result.timing.seenProbeNanoseconds),
            seenInsertSeconds: seconds(result.timing.seenInsertNanoseconds),
            configurationSeconds: seconds(result.timing.configurationNanoseconds),
            eventSeconds: seconds(result.timing.eventNanoseconds),
            successorCalls: result.timing.successorCalls,
            stateEvents: stateEvents, edgeEvents: edgeEvents,
            sampledStates: sampledStates, sampledEdges: sampledEdges,
            estimatedTypedProjectionSeconds: estimatedSeconds(
                typedProjectionNanoseconds, samples: sampledStates, total: stateEvents),
            estimatedCanonicalEncodingSeconds: estimatedSeconds(
                canonicalEncodingNanoseconds, samples: sampledStates, total: stateEvents),
            estimatedStateWriteSeconds: estimatedSeconds(
                stateWriteNanoseconds, samples: sampledStates, total: stateEvents),
            estimatedEdgeWriteSeconds: estimatedSeconds(
                edgeWriteNanoseconds, samples: sampledEdges, total: edgeEvents))
        try JSONEncoder().encode(profile).write(
            to: output.deletingPathExtension().appendingPathExtension("profile.json"), options: .atomic)
        return result
    }
}
