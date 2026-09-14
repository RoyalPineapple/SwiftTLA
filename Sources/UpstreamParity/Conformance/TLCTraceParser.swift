import CoreFoundation
import Foundation

package enum TLCTraceError: Error, Equatable, Sendable {
    case dotIsNotTraceEvidence
    case invalidUTF8
    case malformedJSON
    case missingStates
    case invalidState(Int)
    case ambiguousState(Int)
    case invalidAction(Int)
}

package struct TLCTraceParser: Sendable {
    package init() {}

    package func parseCounterexample(_ data: Data, states knownStates: some Collection<CanonicalState>) throws -> GraphTrace {
        guard let source = String(data: data, encoding: .utf8) else { throw TLCTraceError.invalidUTF8 }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("digraph"), !trimmed.hasPrefix("strict graph") else {
            throw TLCTraceError.dotIsNotTraceEvidence
        }
        let root: [String: Any]
        do { root = try decodeJSONObject(data, line: 1) }
        catch { throw TLCTraceError.malformedJSON }
        guard let counterexample = root["counterexample"] as? [String: Any],
              let variables = root["vars"] as? [String], !variables.isEmpty, Set(variables).count == variables.count,
              let rawStates = counterexample["state"] as? [Any], !rawStates.isEmpty,
              let rawActions = counterexample["action"] as? [Any]
        else { throw TLCTraceError.missingStates }
        let states = try rawStates.enumerated().map { index, state in
            let bindings = try parseBindings(state, variables: variables, index: index)
            // TLC JSON erases collection and model-value tags. Resolve an existing
            // typed graph state rather than inventing types from its JSON syntax.
            let matches = Array(knownStates.lazy.filter { state in
                state.bindings.count == bindings.count && state.bindings.allSatisfy { name, value in
                    bindings[name].map { matchesJSON($0, value: value) } ?? false
                }
            }.prefix(2))
            guard let match = matches.first else { throw TLCTraceError.invalidState(index) }
            guard matches.count == 1 else { throw TLCTraceError.ambiguousState(index) }
            return match
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

    private func parseBindings(_ raw: Any, variables: [String], index: Int) throws -> [String: Any] {
        guard let pair = raw as? [Any], pair.count == 2,
              let number = pair[0] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(index + 1),
              let bindings = pair[1] as? [String: Any], Set(bindings.keys) == Set(variables)
        else { throw TLCTraceError.invalidState(index) }
        return bindings
    }

    private func parseAction(
        _ raw: Any, variables: [String], index: Int, states: [CanonicalState]
    ) throws -> (targetIndex: Int, step: GraphTraceStep) {
        guard let triple = raw as? [Any], triple.count == 3,
              let metadata = triple[1] as? [String: Any], let name = metadata["name"] as? String, !name.isEmpty
        else { throw TLCTraceError.invalidAction(index) }
        let source = try parseBindings(triple[0], variables: variables, index: index)
        guard states[index].bindings.allSatisfy({ name, value in
            source[name].map { matchesJSON($0, value: value) } ?? false
        }) else { throw TLCTraceError.invalidAction(index) }
        guard let targetPair = triple[2] as? [Any], targetPair.count == 2,
              let number = targetPair[0] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 1, number.doubleValue <= Double(states.count),
              number.doubleValue == Double(number.intValue) else {
            throw TLCTraceError.invalidAction(index)
        }
        let targetIndex = number.intValue - 1
        let target = try parseBindings(targetPair, variables: variables, index: targetIndex)
        guard states[targetIndex].bindings.allSatisfy({ name, value in
            target[name].map { matchesJSON($0, value: value) } ?? false
        }) else { throw TLCTraceError.invalidAction(index) }
        if let location = metadata["location"] as? [String: Any],
           location["module"] as? String == "--TLA+ BUILTINS--" {
            let coordinates = ["beginLine", "beginColumn", "endLine", "endColumn"]
            guard name == "UnnamedAction", Set(location.keys) == Set(coordinates + ["module"]),
                  coordinates.allSatisfy({ key in
                      guard let number = location[key] as? NSNumber else { return false }
                      return CFGetTypeID(number) != CFBooleanGetTypeID()
                          && !CFNumberIsFloatType(number) && number.stringValue == "0"
                  }), states[index].key == states[targetIndex].key else {
                throw TLCTraceError.invalidAction(index)
            }
            return (targetIndex, GraphTraceStep(state: states[targetIndex].key, action: nil))
        }
        return (targetIndex, GraphTraceStep(state: states[targetIndex].key, action: name))
    }

    private func matchesJSON(_ raw: Any, value: CanonicalValue) -> Bool {
        switch value {
        case .integer(let expected):
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !CFNumberIsFloatType(number), let actual = Int(number.stringValue) else { return false }
            return actual == expected
        case .boolean(let expected):
            guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
            return number.boolValue == expected
        case .string(let expected), .constant(let expected):
            guard let actual = raw as? String else { return false }
            return actual.utf8.elementsEqual(expected.utf8)
        case .orderedTuple(let values):
            if values.isEmpty, let object = raw as? [String: Any], object.isEmpty { return true }
            guard let array = raw as? [Any], array.count == values.count else { return false }
            return zip(array, values).allSatisfy { matchesJSON($0, value: $1) }
        case .orderedSet(let values):
            guard let array = raw as? [Any], array.count == values.count else { return false }
            return matchesUnordered(array, values: values, matching: matchesJSON)
        case .orderedRecord(let fields):
            guard let object = raw as? [String: Any], object.count == fields.count else { return false }
            return fields.allSatisfy { field in
                guard let index = object.index(forKey: field.name) else { return false }
                let entry = object[index]
                return entry.key.utf8.elementsEqual(field.name.utf8)
                    && matchesJSON(entry.value, value: field.value)
            }
        case .orderedFunction(let entries):
            guard let object = raw as? [String: Any], object.count == entries.count else { return false }
            return matchesUnordered(Array(object), values: entries) { field, entry in
                let keyMatches = entry.key == .string(field.key) || (try? TLCValueParser.parse(field.key)) == entry.key
                return keyMatches && matchesJSON(field.value, value: entry.value)
            }
        }
    }

    /// Find a bijection: erased JSON values can match more than one typed member.
    /// An augmenting path avoids greedy mismatches without enumerating permutations.
    private func matchesUnordered<Raw, Value>(
        _ raw: [Raw], values: [Value], matching: (Raw, Value) -> Bool
    ) -> Bool {
        let candidates = raw.map { item in values.indices.filter { matching(item, values[$0]) } }
        var owners: [Int: Int] = [:]
        func assign(_ index: Int, visited: inout Set<Int>) -> Bool {
            for candidate in candidates[index] where visited.insert(candidate).inserted {
                if let previous = owners[candidate], !assign(previous, visited: &visited) { continue }
                owners[candidate] = index
                return true
            }
            return false
        }
        return raw.indices.allSatisfy { index in
            var visited = Set<Int>()
            return assign(index, visited: &visited)
        }
    }
}
