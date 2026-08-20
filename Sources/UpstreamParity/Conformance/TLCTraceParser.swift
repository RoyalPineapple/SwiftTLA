import CoreFoundation
import Foundation

public enum TLCTraceError: Error, Equatable, Sendable {
    case dotIsNotTraceEvidence
    case invalidUTF8
    case malformedJSON
    case missingStates
    case invalidState(Int)
    case invalidAction(Int)
}

public struct TLCCounterexampleAction: Equatable, Sendable {
    public let source: CanonicalState
    public let name: String
    public let target: CanonicalState

    public init(source: CanonicalState, name: String, target: CanonicalState) {
        self.source = source
        self.name = name
        self.target = target
    }

    public var edge: CanonicalEdge {
        CanonicalEdge(source: source.key, action: name, target: target.key)
    }
}

public struct TLCCounterexampleEvidence: Equatable, Sendable {
    public let rawJSON: Data
    public let states: [CanonicalState]
    public let transitions: [TLCCounterexampleAction]

    public var actions: [String] { transitions.map(\.name) }

    public init(rawJSON: Data, states: [CanonicalState], transitions: [TLCCounterexampleAction]) {
        self.rawJSON = rawJSON
        self.states = states
        self.transitions = transitions
    }

    public func canonicalTrace(id: String) -> CanonicalTrace {
        CanonicalTrace(
            id: id,
            steps: transitions.map { CanonicalTraceStep(state: $0.source.key, action: $0.name) }
        )
    }
}

public struct TLCTraceParser: Sendable {
    public init() {}

    public func parseCounterexample(_ data: Data) throws -> TLCCounterexampleEvidence {
        guard String(data: data, encoding: .utf8) != nil else { throw TLCTraceError.invalidUTF8 }
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("digraph"), !trimmed.hasPrefix("strict graph") else {
            throw TLCTraceError.dotIsNotTraceEvidence
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let counterexample = root["counterexample"] as? [String: Any],
              let variables = root["vars"] as? [String], !variables.isEmpty,
              let rawStates = counterexample["state"] as? [Any], !rawStates.isEmpty,
              let rawActions = counterexample["action"] as? [Any]
        else { throw TLCTraceError.missingStates }

        let states = try rawStates.enumerated().map { index, state in
            try parseNumberedState(state, variables: variables, index: index)
        }
        let transitions = try rawActions.enumerated().map { index, action in
            try parseAction(action, variables: variables, index: index, states: states)
        }
        guard transitions.count == states.count - 1 || transitions.count == states.count else {
            throw TLCTraceError.invalidAction(transitions.count)
        }
        for index in transitions.indices {
            guard transitions[index].source == states[index].state else {
                throw TLCTraceError.invalidAction(index)
            }
            if index < states.count - 1 {
                guard transitions[index].target == states[index + 1].state else {
                    throw TLCTraceError.invalidAction(index)
                }
            } else {
                guard states.contains(where: { $0.state == transitions[index].target }) else {
                    throw TLCTraceError.invalidAction(index)
                }
            }
        }
        return TLCCounterexampleEvidence(rawJSON: data, states: states.map(\.state), transitions: transitions)
    }

    private struct NumberedState {
        let number: Int
        let state: CanonicalState
    }

    private func parseNumberedState(_ raw: Any, variables: [String], index: Int) throws -> NumberedState {
        guard let pair = raw as? [Any], pair.count == 2,
              let number = pair[0] as? NSNumber, number.intValue == index + 1,
              let bindings = pair[1] as? [String: Any], Set(bindings.keys) == Set(variables)
        else { throw TLCTraceError.invalidState(index) }
        var canonical: [String: CanonicalValue] = [:]
        for variable in variables {
            guard let value = bindings[variable] else { throw TLCTraceError.invalidState(index) }
            canonical[variable] = try parseValue(value, state: index)
        }
        return NumberedState(number: number.intValue, state: CanonicalState(bindings: canonical))
    }

    private func parseAction(
        _ raw: Any, variables: [String], index: Int, states: [NumberedState]
    ) throws -> TLCCounterexampleAction {
        guard let triple = raw as? [Any], triple.count == 3,
              let metadata = triple[1] as? [String: Any], let name = metadata["name"] as? String, !name.isEmpty
        else { throw TLCTraceError.invalidAction(index) }
        let source = try parseNumberedState(triple[0], variables: variables, index: index)
        guard source.number == states[index].number, source.state == states[index].state else {
            throw TLCTraceError.invalidAction(index)
        }
        guard let targetPair = triple[2] as? [Any], targetPair.count == 2,
              let targetNumber = targetPair[0] as? NSNumber,
              let targetIndex = states.firstIndex(where: { $0.number == targetNumber.intValue }) else {
            throw TLCTraceError.invalidAction(index)
        }
        let target = try parseNumberedState(targetPair, variables: variables, index: targetIndex)
        guard target.number == states[targetIndex].number, target.state == states[targetIndex].state else {
            throw TLCTraceError.invalidAction(index)
        }
        return TLCCounterexampleAction(source: source.state, name: name, target: target.state)
    }

    private func parseValue(_ raw: Any, state: Int) throws -> CanonicalValue {
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            guard number.doubleValue == Double(number.intValue) else { throw TLCTraceError.invalidState(state) }
            return .integer(number.intValue)
        }
        if let value = raw as? String { return .string(value) }
        if let values = raw as? [Any] { return .tuple(try values.map { try parseValue($0, state: state) }) }
        if let fields = raw as? [String: Any] {
            var record: [String: CanonicalValue] = [:]
            for (name, value) in fields { record[name] = try parseValue(value, state: state) }
            return .record(record)
        }
        throw TLCTraceError.invalidState(state)
    }
}
