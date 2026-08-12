import CoreFoundation
import Foundation

public enum TLCTraceErrorV1: Error, Equatable, Sendable {
    case dotIsNotTraceEvidence
    case invalidUTF8
    case malformedJSON
    case missingStates
    case invalidState(Int)
    case invalidAction(Int)
}

public struct TLCCounterexampleActionV1: Equatable, Sendable {
    public let source: CanonicalStateV1
    public let name: String
    public let target: CanonicalStateV1

    public init(source: CanonicalStateV1, name: String, target: CanonicalStateV1) {
        self.source = source
        self.name = name
        self.target = target
    }

    public var edge: CanonicalEdgeV1 {
        CanonicalEdgeV1(source: source.key, action: name, target: target.key)
    }
}

public struct TLCCounterexampleEvidenceV1: Equatable, Sendable {
    public let rawJSON: Data
    public let states: [CanonicalStateV1]
    public let transitions: [TLCCounterexampleActionV1]

    public var actions: [String] { transitions.map(\.name) }

    public init(rawJSON: Data, states: [CanonicalStateV1], transitions: [TLCCounterexampleActionV1]) {
        self.rawJSON = rawJSON
        self.states = states
        self.transitions = transitions
    }

    public func canonicalTrace(id: String) -> CanonicalTraceV1 {
        CanonicalTraceV1(
            id: id,
            steps: transitions.map { CanonicalTraceStepV1(state: $0.source.key, action: $0.name) }
        )
    }
}

public struct TLCTraceParserV1: Sendable {
    public init() {}

    public func parseCounterexample(_ data: Data) throws -> TLCCounterexampleEvidenceV1 {
        guard String(data: data, encoding: .utf8) != nil else { throw TLCTraceErrorV1.invalidUTF8 }
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("digraph"), !trimmed.hasPrefix("strict graph") else {
            throw TLCTraceErrorV1.dotIsNotTraceEvidence
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let counterexample = root["counterexample"] as? [String: Any],
              let variables = root["vars"] as? [String], !variables.isEmpty,
              let rawStates = counterexample["state"] as? [Any], !rawStates.isEmpty,
              let rawActions = counterexample["action"] as? [Any]
        else { throw TLCTraceErrorV1.missingStates }

        let states = try rawStates.enumerated().map { index, state in
            try parseState(state, variables: variables, index: index)
        }
        let transitions = try rawActions.enumerated().map { index, action in
            try parseAction(action, variables: variables, index: index)
        }
        guard transitions.count == states.count - 1 else {
            throw TLCTraceErrorV1.invalidAction(transitions.count)
        }
        for index in transitions.indices {
            guard transitions[index].source == states[index], transitions[index].target == states[index + 1] else {
                throw TLCTraceErrorV1.invalidAction(index)
            }
        }
        return TLCCounterexampleEvidenceV1(rawJSON: data, states: states, transitions: transitions)
    }

    private func parseState(_ raw: Any, variables: [String], index: Int) throws -> CanonicalStateV1 {
        guard let pair = raw as? [Any], pair.count == 2,
              pair[0] is NSNumber,
              let bindings = pair[1] as? [String: Any], Set(bindings.keys) == Set(variables)
        else { throw TLCTraceErrorV1.invalidState(index) }
        var canonical: [String: CanonicalValueV1] = [:]
        for variable in variables {
            guard let value = bindings[variable] else { throw TLCTraceErrorV1.invalidState(index) }
            canonical[variable] = try parseValue(value, state: index)
        }
        return CanonicalStateV1(bindings: canonical)
    }

    private func parseAction(
        _ raw: Any, variables: [String], index: Int
    ) throws -> TLCCounterexampleActionV1 {
        guard let triple = raw as? [Any], triple.count == 3,
              let metadata = triple[1] as? [String: Any], let name = metadata["name"] as? String, !name.isEmpty
        else { throw TLCTraceErrorV1.invalidAction(index) }
        let source = try parseState(triple[0], variables: variables, index: index)
        let target = try parseState(triple[2], variables: variables, index: index + 1)
        return TLCCounterexampleActionV1(source: source, name: name, target: target)
    }

    private func parseValue(_ raw: Any, state: Int) throws -> CanonicalValueV1 {
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            guard number.doubleValue == Double(number.intValue) else { throw TLCTraceErrorV1.invalidState(state) }
            return .integer(number.intValue)
        }
        if let value = raw as? String { return .string(value) }
        if let values = raw as? [Any] { return .tuple(try values.map { try parseValue($0, state: state) }) }
        if let fields = raw as? [String: Any] {
            var record: [String: CanonicalValueV1] = [:]
            for (name, value) in fields { record[name] = try parseValue(value, state: state) }
            return .record(record)
        }
        throw TLCTraceErrorV1.invalidState(state)
    }
}
