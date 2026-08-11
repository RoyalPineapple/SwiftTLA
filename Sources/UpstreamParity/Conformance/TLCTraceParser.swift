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

public struct TLCCounterexampleEvidenceV1: Equatable, Sendable {
    public let rawJSON: Data
    public let states: [CanonicalStateV1]
    public let actions: [String]

    public init(rawJSON: Data, states: [CanonicalStateV1], actions: [String]) {
        self.rawJSON = rawJSON
        self.states = states
        self.actions = actions
    }

    public func canonicalTrace(id: String) -> CanonicalTraceV1 {
        CanonicalTraceV1(
            id: id,
            steps: zip(states, actions).map { CanonicalTraceStepV1(state: $0.key, action: $1) }
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
        let actions = try rawActions.enumerated().map { index, action in
            try parseAction(action, index: index)
        }
        guard actions.count == states.count - 1 else { throw TLCTraceErrorV1.invalidAction(actions.count) }
        return TLCCounterexampleEvidenceV1(rawJSON: data, states: states, actions: actions)
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

    private func parseAction(_ raw: Any, index: Int) throws -> String {
        guard let triple = raw as? [Any], triple.count == 3,
              let metadata = triple[1] as? [String: Any], let name = metadata["name"] as? String, !name.isEmpty
        else { throw TLCTraceErrorV1.invalidAction(index) }
        return name
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
