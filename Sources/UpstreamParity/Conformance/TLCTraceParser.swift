import CoreFoundation
import Foundation

package enum TLCTraceError: Error, Equatable, Sendable {
    case dotIsNotTraceEvidence
    case invalidUTF8
    case malformedJSON
    case missingStates
    case invalidState(Int)
    case invalidAction(Int)
}

package struct TLCTraceParser: Sendable {
    package init() {}

    package func parseCounterexample(_ data: Data) throws -> GraphTrace {
        guard let source = String(data: data, encoding: .utf8) else { throw TLCTraceError.invalidUTF8 }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard rawActions.count == states.count - 1 || rawActions.count == states.count else {
            throw TLCTraceError.invalidAction(rawActions.count)
        }
        let actions = try rawActions.enumerated().map { index, action in
            try parseAction(action, variables: variables, index: index, states: states)
        }
        for (index, action) in actions.enumerated() where index < states.count - 1 {
            guard action.targetIndex == index + 1 else { throw TLCTraceError.invalidAction(index) }
        }
        let cycleStart = actions.count == states.count ? actions.last?.targetIndex : nil
        return GraphTrace(id: "tlc-counterexample",
            steps: [GraphTraceStep(state: states[0].key, action: nil)] + actions.map(\.step),
            cycleStartIndex: cycleStart)
    }

    private func parseNumberedState(_ raw: Any, variables: [String], index: Int) throws -> CanonicalState {
        guard let pair = raw as? [Any], pair.count == 2,
              let number = pair[0] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(index + 1),
              let bindings = pair[1] as? [String: Any], Set(bindings.keys) == Set(variables)
        else { throw TLCTraceError.invalidState(index) }
        var canonical: [String: CanonicalValue] = [:]
        for variable in variables {
            guard let value = bindings[variable] else { throw TLCTraceError.invalidState(index) }
            canonical[variable] = try parseValue(value, state: index)
        }
        return CanonicalState(bindings: canonical)
    }

    private func parseAction(
        _ raw: Any, variables: [String], index: Int, states: [CanonicalState]
    ) throws -> (targetIndex: Int, step: GraphTraceStep) {
        guard let triple = raw as? [Any], triple.count == 3,
              let metadata = triple[1] as? [String: Any], let name = metadata["name"] as? String, !name.isEmpty
        else { throw TLCTraceError.invalidAction(index) }
        let source = try parseNumberedState(triple[0], variables: variables, index: index)
        guard source == states[index] else { throw TLCTraceError.invalidAction(index) }
        guard let targetPair = triple[2] as? [Any], targetPair.count == 2,
              let number = targetPair[0] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 1, number.doubleValue <= Double(states.count),
              number.doubleValue == Double(number.intValue) else {
            throw TLCTraceError.invalidAction(index)
        }
        let targetIndex = number.intValue - 1
        let target = try parseNumberedState(targetPair, variables: variables, index: targetIndex)
        guard target == states[targetIndex] else { throw TLCTraceError.invalidAction(index) }
        return (targetIndex, GraphTraceStep(state: target.key, action: name))
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
