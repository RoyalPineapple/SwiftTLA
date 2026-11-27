import Dispatch
import Foundation
import SwiftTLA

package enum MachineValidationEvidenceError: Error, Equatable {
    case invalidPropertyName
}

private struct RecordedActionFailure: Encodable {
    let source: Int
    struct Binding: Encodable {
        let binding: Int
        let target: Int
        let value: Int
    }

    let action: Int
    let branch: Int?
    let phase: String?
    let site: Int
    let target: Int
    let before: [Binding]
    let payload: BinaryEvaluationFailure

    init(_ occurrence: ValidationActionFailureOccurrence) {
        source = occurrence.source
        action = occurrence.failure.action
        switch occurrence.failure.location {
        case .arm(let ordinal):
            branch = ordinal
            phase = nil
        case .sharedPrefix:
            branch = nil
            phase = "sharedPrefix"
        }
        site = occurrence.failure.site
        target = occurrence.failure.target
        before = occurrence.failure.before.map { Binding(binding: $0.binding, target: $0.target, value: $0.value) }
        payload = BinaryEvaluationFailure(occurrence.failure.reason)
    }
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
    let orderedActionFailureHistory: [RecordedActionFailure]?
}

/// Append-only evidence from the generated Swift machine. TLC is never read by this checker.
package enum MachineValidationEvidence {
    package static func write<Scenario: ModelValidationScenario>(
        scenario: Scenario, initialMachines: [Scenario.Machine], caseID: String,
        maximumStates: Int, stopOnViolation: Bool,
        stopOnReachability: Bool = false,
        checking: ModelChecks<Scenario.Property>? = nil,
        fairness: [MachineFairnessCondition<Scenario.Machine.Snapshot, Scenario.Machine.Action>] = [],
        to output: URL,
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
        guard let machine = initialMachines.first else { throw ExplorationError.noInitialStates }
        var writer = try BinaryGraphEvidenceWriter(to: output, caseID: caseID)
        defer { writer.close() }
        var actionIDs: [Scenario.Machine.Action: UInt32] = [:]
        var previousAction: (action: Scenario.Machine.Action, id: UInt32)?
        var stateEvents = 0
        var edgeEvents = 0
        var sampledStates = 0
        var sampledEdges = 0
        var typedProjectionNanoseconds: UInt64 = 0
        var canonicalEncodingNanoseconds: UInt64 = 0
        var stateWriteNanoseconds: UInt64 = 0
        var edgeWriteNanoseconds: UInt64 = 0
        var stateKeyEncoder = CanonicalBinaryState.Encoder()
        var representativeEncoder = CanonicalBinaryState.Encoder()

        func actionID(_ action: Scenario.Machine.Action) throws -> UInt32 {
            if let previousAction, previousAction.action == action { return previousAction.id }
            if let id = actionIDs[action] {
                previousAction = (action, id)
                return id
            }
            guard let id = UInt32(exactly: actionIDs.count) else {
                throw BinaryGraphEvidenceError.invalid("action count")
            }
            actionIDs[action] = id
            try writer.action(id: id, name: machine.formalCall(for: action).description)
            previousAction = (action, id)
            return id
        }

        func encode(_ snapshot: Scenario.Machine.Snapshot, observation: MachineValidationObservation<Scenario.Machine>,
                    sampled: Bool = false) throws -> Data? {
            guard let level = observation.checkingLevel else { throw ExplorationError.configurationMismatch }
            let start = sampled ? DispatchTime.now().uptimeNanoseconds : 0
            var projectionTime: UInt64 = 0
            defer {
                if sampled {
                    typedProjectionNanoseconds += projectionTime
                    canonicalEncodingNanoseconds += DispatchTime.now().uptimeNanoseconds - start - projectionTime
                }
            }
            if case .tupleFields(let slots) = observation.identity {
                do {
                    try representativeEncoder.encode(tupleView: slots, key: &stateKeyEncoder,
                        visit: { try machine._visitFormalProjection(of: snapshot, into: &$0) },
                        projection: {
                            let full = try machine.formalProjection(of: snapshot)
                            if sampled { projectionTime = DispatchTime.now().uptimeNanoseconds - start }
                            return full
                        })
                    return representativeEncoder.bytes
                } catch {
                    // Match ordinary capture's diagnostic if the VIEW also fails.
                    try stateKeyEncoder.encode(scenario.formalIdentityProjection(of: snapshot, using: machine,
                        atLevel: level), viewed: true)
                    throw error
                }
            }
            let key: TLAStateProjection
            if case .evaluated(let evaluated) = observation.identity { key = evaluated }
            else { key = try scenario.formalIdentityProjection(of: snapshot, using: machine, atLevel: level) }
            if sampled { projectionTime = DispatchTime.now().uptimeNanoseconds - start }
            try stateKeyEncoder.encode(key, viewed: scenario.usesView)
            guard scenario.usesView else { return nil }
            let beforeFull = sampled ? DispatchTime.now().uptimeNanoseconds : 0
            let full = try machine.formalProjection(of: snapshot)
            if sampled { projectionTime += DispatchTime.now().uptimeNanoseconds - beforeFull }
            try representativeEncoder.encode(full)
            return representativeEncoder.bytes
        }

        let result = try scenario.captureValidation(initialMachines: initialMachines,
            maximumStates: maximumStates,
            checking: checking, stopOnViolation: stopOnViolation,
            stopOnReachability: stopOnReachability, fairness: fairness
        ) { observation in
            let event = observation.event
            switch event {
            case .state(let id, let snapshot, let isInitial, let predecessor, _):
                guard id == stateEvents, isInitial == (predecessor == nil) else { throw ExplorationError.configurationMismatch }
                stateEvents += 1
                let sampled = stateEvents % 256 == 1
                let full = try encode(snapshot, observation: observation, sampled: sampled)
                let writeStartedAt = sampled ? DispatchTime.now().uptimeNanoseconds : 0
                try writer.state(id: UInt64(id), key: stateKeyEncoder.bytes, initial: isInitial, representative: full)
                if sampled {
                    sampledStates += 1
                    stateWriteNanoseconds += DispatchTime.now().uptimeNanoseconds - writeStartedAt
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
                let full = try encode(snapshot, observation: observation)
                try writer.invariantFailure(property: name, key: stateKeyEncoder.bytes,
                    predecessor: predecessor.map(UInt64.init), action: action,
                    representative: full)
            case .deadlock(let state):
                try writer.deadlock(state: UInt64(state))
            case .reachability(let property, let snapshot, let predecessor, let action):
                guard let name = propertyNames[property] else {
                    throw MachineValidationEvidenceError.invalidPropertyName
                }
                let action = try action.map(actionID)
                let full = try encode(snapshot, observation: observation)
                try writer.reached(property: name, key: stateKeyEncoder.bytes,
                    predecessor: predecessor.map(UInt64.init), action: action,
                    representative: full)
            case .evaluationFailure(let source, let action, let reason):
                try writer.evaluationFailure(source: UInt64(source), action: actionID(action), reason: reason)
            }
            try observe?(event)
        }
        let completion: UInt8 = switch result.completion {
        case .exhausted: 0
        case .decisiveViolation: 1
        case .decisiveReachability: 2
        case .evaluationFailure: 3
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
                edgeWriteNanoseconds, samples: sampledEdges, total: edgeEvents),
            orderedActionFailureHistory: result.orderedActionFailureHistory?.map(RecordedActionFailure.init))
        try JSONEncoder().encode(profile).write(
            to: output.deletingPathExtension().appendingPathExtension("profile.json"), options: .atomic)
        return result
    }
}
