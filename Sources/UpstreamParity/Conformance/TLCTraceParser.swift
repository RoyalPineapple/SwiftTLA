import CoreFoundation
import Foundation
import SwiftTLA

package enum TLCTraceError: Error, Equatable, Sendable {
    case dotIsNotTraceEvidence
    case invalidUTF8
    case malformedJSON
    case missingStates
    case invalidState(Int)
    case ambiguousState(Int)
    case invalidAction(Int)
    case ambiguousAction(Int)
}

package struct TLCTraceParser: Sendable {
    package init() {}

    package func parseCounterexample(_ data: Data, states knownStates: some Collection<CanonicalState>,
        renderedActions: [RenderedAction] = []) throws -> GraphTrace {
        try parseCounterexample(data, renderedActions: renderedActions) { bindings, index in
            let matches = Array(knownStates.lazy.filter { matchesBindings(bindings, state: $0) }.prefix(2))
            guard let match = matches.first else { throw TLCTraceError.invalidState(index) }
            guard matches.count == 1 else { throw TLCTraceError.ambiguousState(index) }
            return match
        }
    }

    /// Replays the BFS prefix so exploration-wide effects include off-witness branches.
    package func replayCounterexample<Machine: StateMachine>(
        _ data: Data, initialMachines: [Machine], renderedActions: [RenderedAction],
        maximumStates: Int, checkingDeadlock: Bool
    ) throws -> (trace: GraphTrace, final: Machine, finalIsDeadlocked: Bool?) {
        guard maximumStates > 0 else { throw ExplorationError.invalidStateLimit(maximumStates) }
        guard let initial = initialMachines.first else { throw ExplorationError.noInitialStates }
        var context = CheckingContext(registers: try initial.initialCheckingRegisters())
        var pending: [Machine] = []
        var layer: [Machine] = []
        var discovered: Set<Machine.Snapshot> = []
        var expanded: [Machine.Snapshot: [(action: Machine.Action, machine: Machine)]] = [:]
        var successorsToDiscover: [Machine] = []
        func discover(_ machine: Machine) throws {
            guard machine.hasSameConfiguration(as: initial) else { throw ExplorationError.configurationMismatch }
            guard try machine.satisfiesStateConstraint(), !discovered.contains(machine.snapshot) else { return }
            guard discovered.count < maximumStates else { throw ExplorationError.stateLimitExceeded(maximumStates) }
            discovered.insert(machine.snapshot)
            pending.append(machine)
        }
        for machine in initialMachines {
            guard try machine.assumptionsHold() else { throw ExplorationError.assumptionViolated }
            try discover(machine)
        }
        func successors(of machine: Machine) throws -> [(action: Machine.Action, machine: Machine)] {
            while expanded[machine.snapshot] == nil {
                try Task.checkCancellation()
                for successor in successorsToDiscover { try discover(successor) }
                successorsToDiscover.removeAll(keepingCapacity: true)
                if layer.isEmpty {
                    guard !pending.isEmpty else { throw ExplorationError.traceTargetNotReachable }
                    try context.advanceBreadthFirstLevel()
                    swap(&layer, &pending)
                    layer.reverse()
                }
                let source = layer.removeLast()
                let successors = try source.successors(checking: &context)
                expanded[source.snapshot] = successors
                successorsToDiscover = successors.map(\.machine)
            }
            return expanded[machine.snapshot]!
        }
        var machines: [Machine] = []
        var allowedActions: [Set<String>] = []
        let actionNames = Dictionary(uniqueKeysWithValues: renderedActions.map {
            ($0.sourceInvocationName, $0.renderedName)
        })
        let trace = try parseCounterexample(data, renderedActions: renderedActions) { bindings, index in
            let candidates: [(action: Machine.Action?, machine: Machine)]
            if let previous = machines.last {
                guard try previous.satisfiesStateConstraint() else { throw TLCTraceError.invalidState(index - 1) }
                candidates = try successors(of: previous).map { ($0.action, $0.machine) }
            } else {
                candidates = initialMachines.map { (nil, $0) }
            }
            var matches: [Machine.Snapshot: (Machine, CanonicalState)] = [:]
            var actions: Set<String> = []
            for candidate in candidates {
                if let first = initialMachines.first {
                    guard candidate.machine.hasSameConfiguration(as: first) else { throw ExplorationError.configurationMismatch }
                }
                let state = try CanonicalState(candidate.machine.formalProjection(of: candidate.machine.snapshot))
                guard matchesBindings(bindings, state: state) else { continue }
                matches[candidate.machine.snapshot] = (candidate.machine, state)
                if let action = candidate.action {
                    let name = try candidate.machine.formalCall(for: action).description
                    actions.insert(actionNames[name] ?? name)
                }
            }
            guard let match = matches.values.first else { throw TLCTraceError.invalidState(index) }
            guard matches.count == 1 else { throw TLCTraceError.ambiguousState(index) }
            guard try match.0.assumptionsHold() else { throw ExplorationError.assumptionViolated }
            machines.append(match.0)
            allowedActions.append(actions)
            return match.1
        }
        guard trace.cycleStartIndex == nil, trace.steps.count == machines.count,
              let final = machines.last else { throw GraphRunError.invalidLasso }
        for index in trace.steps.indices.dropFirst() {
            guard let action = trace.steps[index].action, allowedActions[index].contains(action) else {
                throw TLCTraceError.invalidAction(index - 1)
            }
        }
        let finalIsDeadlocked = checkingDeadlock ? try successors(of: final).isEmpty : nil
        return (trace, final, finalIsDeadlocked)
    }

    private func matchesBindings(_ bindings: [String: Any], state: CanonicalState) -> Bool {
        state.bindings.count == bindings.count && state.bindings.allSatisfy { name, value in
            bindings[name].map { matchesJSON($0, value: value) } ?? false
        }
    }

    private func parseCounterexample(_ data: Data, renderedActions: [RenderedAction],
        resolve: ([String: Any], Int) throws -> CanonicalState) throws -> GraphTrace {
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
            return try resolve(bindings, index)
        }
        guard rawActions.count == states.count - 1 || rawActions.count == states.count else {
            throw TLCTraceError.invalidAction(rawActions.count)
        }
        let actions = try rawActions.enumerated().map { index, action in
            try parseAction(action, variables: variables, index: index, states: states, renderedActions: renderedActions)
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
        _ raw: Any, variables: [String], index: Int, states: [CanonicalState], renderedActions: [RenderedAction]
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
        let parameters: [String]
        let context: [String: Any]
        if metadata["parameters"] == nil && metadata["context"] == nil {
            parameters = []
            context = [:]
        } else {
            guard let names = metadata["parameters"] as? [String], Set(names).count == names.count,
                  names.allSatisfy({ !$0.isEmpty }), let values = metadata["context"] as? [String: Any],
                  names.allSatisfy({ values[$0] != nil }) else { throw TLCTraceError.invalidAction(index) }
            parameters = names
            context = values
        }
        let action: String
        if renderedActions.isEmpty {
            guard parameters.isEmpty else { throw TLCTraceError.invalidAction(index) }
            action = name
        } else {
            let arguments = parameters.map { context[$0]! }
            let matches = try renderedActions.filter { candidate in
                guard candidate.sourceName.utf8.elementsEqual(name.utf8),
                      candidate.arguments.count == arguments.count else { return false }
                return try zip(arguments, candidate.arguments).allSatisfy { raw, value in
                    matchesJSON(raw, value: try CanonicalValue(value))
                }
            }
            guard let match = matches.first else { throw TLCTraceError.invalidAction(index) }
            guard matches.count == 1 else { throw TLCTraceError.ambiguousAction(index) }
            action = match.renderedName
        }
        return (targetIndex, GraphTraceStep(state: states[targetIndex].key, action: action))
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
