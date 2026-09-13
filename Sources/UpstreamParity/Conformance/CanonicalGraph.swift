import Foundation
import SwiftTLA

package enum CanonicalValueError: Error, Equatable, Sendable, CustomStringConvertible {
    case duplicateFunctionKey(CanonicalValue)

    package var description: String {
        switch self {
        case .duplicateFunctionKey(let key):
            return "Canonical function contains duplicate key \(key.canonicalEncoding)."
        }
    }
}

package enum CanonicalValue: Hashable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case string(String)
    case constant(String)
    case orderedSet([CanonicalValue])
    case orderedTuple([CanonicalValue])
    case orderedRecord([CanonicalRecordField])
    case orderedFunction([CanonicalFunctionEntry])

    package static func set(_ values: [CanonicalValue]) -> CanonicalValue {
        .orderedSet(Set(values).sorted { canonicalBytes($0.canonicalEncoding, $1.canonicalEncoding) })
    }

    package static func tuple(_ values: [CanonicalValue]) -> CanonicalValue {
        .orderedTuple(values)
    }

    package static func record(_ fields: [String: CanonicalValue]) -> CanonicalValue {
        guard fields.isEmpty == false else { return .tuple([]) }
        return .orderedRecord(fields.map { CanonicalRecordField(name: $0.key, value: $0.value) }
            .sorted { canonicalBytes($0.name, $1.name) })
    }

    package static func function(_ entries: [CanonicalFunctionEntry]) throws -> CanonicalValue {
        let ordered = entries.sorted { canonicalBytes($0.key.canonicalEncoding, $1.key.canonicalEncoding) }
        var keys = Set<CanonicalValue>()
        for entry in ordered {
            guard keys.insert(entry.key).inserted else {
                throw CanonicalValueError.duplicateFunctionKey(entry.key)
            }
        }
        if entries.isEmpty {
            return .tuple([])
        }
        let indexedValues = entries.compactMap { entry -> (index: Int, value: CanonicalValue)? in
            guard case .integer(let index) = entry.key else { return nil }
            return (index, entry.value)
        }.sorted { $0.index < $1.index }
        if indexedValues.count == entries.count,
           indexedValues.enumerated().allSatisfy({ offset, entry in entry.index == offset + 1 }) {
            return .tuple(indexedValues.map(\.value))
        }
        var fields: [String: CanonicalValue] = [:]
        for entry in ordered {
            guard case .string(let name) = entry.key else { return .orderedFunction(ordered) }
            fields[name] = entry.value
        }
        return .record(fields)
    }

    package init(_ value: TLAValue) throws {
        switch value {
        case .int(let value): self = .integer(value)
        case .bool(let value): self = .boolean(value)
        case .string(let value): self = .string(value)
        case .constant(let value): self = .constant(value)
        case .set(let values): self = .set(try values.map(Self.init))
        case .tuple(let values): self = .tuple(try values.map(Self.init))
        case .record(let fields):
            self = .record(try Dictionary(uniqueKeysWithValues: fields.fields.map { field in
                (field.name, try Self(field.value))
            }))
        case .function(let entries):
            self = try .function(entries.map { try CanonicalFunctionEntry(key: Self($0.key), value: Self($0.value)) })
        }
    }

    package var canonicalEncoding: String {
        switch self {
        case .integer(let value): return "integer:\(value)"
        case .boolean(let value): return "boolean:\(value ? "true" : "false")"
        case .string(let value): return "string:\(encodedBytes(value))"
        case .constant(let value): return "constant:\(encodedBytes(value))"
        case .orderedSet(let values):
            return "set:[\(values.map(\.canonicalEncoding).joined(separator: ","))]"
        case .orderedTuple(let values):
            return "tuple:[\(values.map(\.canonicalEncoding).joined(separator: ","))]"
        case .orderedRecord(let fields):
            return "record:[\(fields.map { "\(encodedBytes($0.name))=\($0.value.canonicalEncoding)" }.joined(separator: ","))]"
        case .orderedFunction(let entries):
            return "function:[\(entries.map { "\($0.key.canonicalEncoding)=>\($0.value.canonicalEncoding)" }.joined(separator: ","))]"
        }
    }
}

package struct CanonicalRecordField: Hashable, Sendable {
    package let name: String
    package let value: CanonicalValue

    package init(name: String, value: CanonicalValue) {
        self.name = name
        self.value = value
    }
}

package struct CanonicalFunctionEntry: Hashable, Sendable {
    package let key: CanonicalValue
    package let value: CanonicalValue

    package init(key: CanonicalValue, value: CanonicalValue) {
        self.key = key
        self.value = value
    }
}

package struct CanonicalStateKey: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    package let canonicalEncoding: String

    package init(canonicalEncoding: String) {
        self.canonicalEncoding = canonicalEncoding
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Empty canonical state key")
        }
        self.init(canonicalEncoding: value)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalEncoding)
    }

    package var description: String { canonicalEncoding }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        canonicalBytes(lhs.canonicalEncoding, rhs.canonicalEncoding)
    }
}

package struct CanonicalState: Hashable, Sendable {
    package let bindings: [String: CanonicalValue]

    package init(bindings: [String: CanonicalValue]) {
        self.bindings = bindings
    }

    package init(_ projection: TLAStateProjection) throws {
        bindings = try Dictionary(uniqueKeysWithValues: projection.entries.map {
            ($0.token.description, try CanonicalValue($0.value))
        })
    }

    package var key: CanonicalStateKey {
        let fields = bindings.sorted { canonicalBytes($0.key, $1.key) }
            .map { "\(encodedBytes($0.key))=\($0.value.canonicalEncoding)" }
            .joined(separator: ",")
        return CanonicalStateKey(canonicalEncoding: "state:[\(fields)]")
    }
}

package struct CanonicalEdge: Hashable, Sendable, Comparable {
  package let source: CanonicalStateKey
  package let action: String
  package let target: CanonicalStateKey
  package let canonicalEncoding: String

  package init(source: CanonicalStateKey, action: String, target: CanonicalStateKey) {
    self.source = source
    self.action = action
    self.target = target
    canonicalEncoding = "edge:\(source.canonicalEncoding)--\(encodedBytes(action))-->\(target.canonicalEncoding)"
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        canonicalBytes(lhs.canonicalEncoding, rhs.canonicalEncoding)
    }

}

package enum CanonicalGraphError: Error, Equatable, Sendable {
    case missingNativeSnapshot
    case duplicateState(CanonicalStateKey)
    case inconsistentStateBindings(expected: Set<String>, actual: Set<String>)
    case initialStateMissing(CanonicalStateKey)
    case edgeStateMissing(CanonicalStateKey)
}

package func canonicalStateTable(
    _ states: some Sequence<CanonicalState>
) throws -> [CanonicalStateKey: CanonicalState] {
    var table: [CanonicalStateKey: CanonicalState] = [:]
    for state in states {
        guard table.updateValue(state, forKey: state.key) == nil else {
            throw CanonicalGraphError.duplicateState(state.key)
        }
    }
    return table
}

package struct CanonicalGraph: Equatable, Sendable {
    package let initialStateKeys: Set<CanonicalStateKey>
    package let states: [CanonicalStateKey: CanonicalState]
    /// The labeled transition relation; repeated evaluation witnesses add no behavior.
    package let edges: Set<CanonicalEdge>

    package init(
        initialStates: [CanonicalState],
        states: [CanonicalState],
        edges: some Sequence<CanonicalEdge>
    ) throws {
        let stateTable = try canonicalStateTable(states)
        let expectedBindings = stateTable.values.first.map { Set($0.bindings.keys) } ?? []
        for state in stateTable.values where Set(state.bindings.keys) != expectedBindings {
            throw CanonicalGraphError.inconsistentStateBindings(
                expected: expectedBindings,
                actual: Set(state.bindings.keys)
            )
        }

        let initialKeys = Set(initialStates.map(\.key))
        for key in initialKeys where stateTable[key] == nil {
            throw CanonicalGraphError.initialStateMissing(key)
        }

        let transitions = Set(edges)
        for edge in transitions {
            guard stateTable[edge.source] != nil else {
                throw CanonicalGraphError.edgeStateMissing(edge.source)
            }
            guard stateTable[edge.target] != nil else {
                throw CanonicalGraphError.edgeStateMissing(edge.target)
            }
        }

        self.initialStateKeys = initialKeys
        self.states = stateTable
        self.edges = transitions
    }

    /// Export native topology only; this does not issue a property-checking verdict.
    package init<Machine: StateMachine>(_ native: ReachabilityGraph<Machine>) throws {
        let states = try Dictionary(uniqueKeysWithValues: native.transitions.keys.map {
            ($0, try CanonicalState(native.formalProjection(of: $0)))
        })
        try self.init(native, states: states)
    }

    package init<Machine: StateMachine>(
        _ native: ReachabilityGraph<Machine>, states: [Machine.Snapshot: CanonicalState],
        renderedActionNames: [String: String] = [:]
    ) throws {
        guard Set(states.keys) == Set(native.transitions.keys) else {
            throw CanonicalGraphError.missingNativeSnapshot
        }
        func state(_ snapshot: Machine.Snapshot) throws -> CanonicalState {
            guard let result = states[snapshot] else { throw CanonicalGraphError.missingNativeSnapshot }
            return result
        }
        var actionNames: [Machine.Action: String] = [:]
        func actionName(_ action: Machine.Action) throws -> String {
            if let name = actionNames[action] { return name }
            let invocation = try native.formalCall(for: action).description
            let name = renderedActionNames[invocation] ?? invocation
            actionNames[action] = name
            return name
        }
        let edges = try native.transitions.flatMap { source, successors in
            try successors.map { successor in
                CanonicalEdge(source: try state(source).key, action: try actionName(successor.action),
                              target: try state(successor.target).key)
            }
        }
        try self.init(initialStates: native.initialStates.map(state), states: Array(states.values), edges: edges)
    }

    package var variableNames: Set<String> {
        states.values.first.map { Set($0.bindings.keys) } ?? []
    }

}

package enum GraphRunOutcome: Hashable, Sendable {
    case noViolation
    case invariantViolation(String)
    case temporalViolation(property: String, reason: TemporalDiagnosticReason)
    case refinementViolation(String)
    case deadlock(CanonicalStateKey)
    case incomplete(reason: String)
    case executionError(String)

    package var isConclusive: Bool {
        switch self {
        case .noViolation, .invariantViolation, .refinementViolation, .deadlock: true
        case .temporalViolation(_, let reason): reason == .violatingFairLasso
        case .incomplete, .executionError: false
        }
    }

}

package struct GraphTraceStep: Hashable, Codable, Sendable {
    package let state: CanonicalStateKey
    /// Nil denotes the initial state or an implicit stuttering step.
    package let action: String?

    package init(state: CanonicalStateKey, action: String?) {
        self.state = state
        self.action = action
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case state, action }

    package init(from decoder: Decoder) throws {
        let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
        self.init(state: try container.decode(CanonicalStateKey.self, forKey: .state),
            action: try container.decodeIfPresent(String.self, forKey: .action))
    }

}

package struct GraphTrace: Hashable, Codable, Sendable {
    package let id: String
    package let steps: [GraphTraceStep]
    /// The step where the repeating cycle begins, or nil for a finite trace.
    package let cycleStartIndex: Int?

    package init<State: Hashable & Sendable, Action: Equatable & Sendable>(
        id: String,
        witness: FairLassoWitness<State, Action?>,
        stateKey: (State) throws -> CanonicalStateKey,
        actionName: (Action) throws -> String
    ) throws {
        guard witness.prefix.count == witness.prefixActions.count + 1,
              witness.cycle.count == witness.cycleActions.count + 1,
              witness.cycle.count >= 2, witness.prefix.last == witness.cycle.first,
              witness.cycle.first == witness.cycle.last else { throw GraphRunError.invalidLasso }
        let prefix = zip(witness.prefix, [nil] + witness.prefixActions)
        let cycle = zip(witness.cycle.dropFirst(), witness.cycleActions)
        let steps = try (Array(prefix) + Array(cycle)).map { state, action in
            GraphTraceStep(state: try stateKey(state), action: try action.map(actionName))
        }
        self.init(id: id, steps: steps, cycleStartIndex: witness.prefix.count - 1)
    }

    package init(id: String, steps: [GraphTraceStep], cycleStartIndex: Int? = nil) {
        self.id = id
        self.steps = steps
        self.cycleStartIndex = cycleStartIndex
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case id, steps, cycleStartIndex }

    package init(from decoder: Decoder) throws {
        let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
        self.init(id: try container.decode(String.self, forKey: .id),
            steps: try container.decode([GraphTraceStep].self, forKey: .steps),
            cycleStartIndex: try container.decodeIfPresent(Int.self, forKey: .cycleStartIndex))
        try validateStructure()
    }

    private func validateStructure() throws {
        guard let first = steps.first else { throw GraphRunError.emptyTrace }
        guard first.action == nil else { throw GraphRunError.traceInitialActionPresent }
        if let start = cycleStartIndex {
            guard start >= 0, start < steps.count - 1 else { throw GraphRunError.invalidCycleStart(start) }
            guard steps[start].state == steps.last?.state else { throw GraphRunError.openCycle }
        }
        for (source, target) in zip(steps, steps.dropFirst()) where target.action == nil {
            guard source.state == target.state else { throw GraphRunError.stateChangingStutter }
        }
    }

    package func validate(in graph: CanonicalGraph) throws {
        try validateStructure()
        let first = steps[0]
        for step in steps where graph.states[step.state] == nil {
            throw GraphRunError.traceStateMissing(step.state)
        }
        guard graph.initialStateKeys.contains(first.state) else {
            throw GraphRunError.traceInitialStateMissing(first.state)
        }
        for (source, target) in zip(steps, steps.dropFirst()) {
            guard let action = target.action else { continue }
            let edge = CanonicalEdge(source: source.state, action: action, target: target.state)
            guard graph.edges.contains(edge) else { throw GraphRunError.traceEdgeMissing(edge) }
        }
    }

}

package enum GraphRunError: Error, Equatable, Sendable {
    case graphActionUndeclared(String)
    case deadlockStateMissing(CanonicalStateKey)
    case traceStateMissing(CanonicalStateKey)
    case emptyTrace
    case invalidLasso
    case traceInitialActionPresent
    case invalidCycleStart(Int)
    case openCycle
    case stateChangingStutter
    case traceInitialStateMissing(CanonicalStateKey)
    case traceEdgeMissing(CanonicalEdge)
}

package struct GraphRun: Equatable, Sendable {
    /// Whether the producer finished enumerating the configured state space.
    package let isComplete: Bool
    package let graph: CanonicalGraph
    package let observableActions: Set<String>
    package let outcome: GraphRunOutcome
    package let trace: GraphTrace?

    package init(
        isComplete: Bool,
        graph: CanonicalGraph,
        observableActions: Set<String>,
        outcome: GraphRunOutcome,
        trace: GraphTrace? = nil
    ) throws {
        for edge in graph.edges where !observableActions.contains(edge.action) {
            throw GraphRunError.graphActionUndeclared(edge.action)
        }
        if case .deadlock(let state) = outcome, graph.states[state] == nil {
            throw GraphRunError.deadlockStateMissing(state)
        }
        try trace?.validate(in: graph)

        self.isComplete = isComplete
        self.graph = graph
        self.observableActions = observableActions
        self.outcome = outcome
        self.trace = trace
    }

    package var isComparable: Bool {
        isComplete && outcome.isConclusive
    }
}

func canonicalBytes(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
}

func encodedBytes(_ value: String) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(value.utf8.count * 2)
    for byte in value.utf8 {
        bytes.append(digits[Int(byte >> 4)])
        bytes.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: bytes, as: UTF8.self)
}
