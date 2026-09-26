import Darwin
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
        let members = Dictionary(values.map { ($0.canonicalEncoding, $0) }, uniquingKeysWith: { first, _ in first })
        return .orderedSet(members.sorted { canonicalBytes($0.key, $1.key) }.map(\.value))
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
        let keyedEntries = entries.map { (entry: $0, encoding: $0.key.canonicalEncoding) }
        let ordered = keyedEntries.sorted { canonicalBytes($0.encoding, $1.encoding) }.map(\.entry)
        var keys = Set<String>()
        for (entry, encoding) in keyedEntries {
            guard keys.insert(encoding).inserted else {
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
        var fields: [CanonicalRecordField] = []
        for entry in ordered {
            guard case .string(let name) = entry.key else { return .orderedFunction(ordered) }
            fields.append(CanonicalRecordField(name: name, value: entry.value))
        }
        return .orderedRecord(fields)
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

    // Formal string identity follows the encoded bytes, not Swift's Unicode equivalence.
    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.canonicalEncoding == rhs.canonicalEncoding
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(canonicalEncoding)
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
    private let cachedHash: Int

    package init(canonicalEncoding: String) {
        self.canonicalEncoding = canonicalEncoding
        cachedHash = canonicalEncoding.hashValue
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.canonicalEncoding == rhs.canonicalEncoding
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(cachedHash)
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
    package let key: CanonicalStateKey

    package init(bindings: [String: CanonicalValue]) {
        self.bindings = bindings
        let fields = bindings.sorted { canonicalBytes($0.key, $1.key) }
            .map { "\(encodedBytes($0.key))=\($0.value.canonicalEncoding)" }
            .joined(separator: ",")
        key = CanonicalStateKey(canonicalEncoding: "state:[\(fields)]")
    }

    package init(_ projection: TLAStateProjection) throws {
        self.init(bindings: try Dictionary(uniqueKeysWithValues: projection.entries.map {
            ($0.token.description, try CanonicalValue($0.value))
        }))
    }
}

package struct CanonicalEdge: Hashable, Sendable, Comparable {
    package let source: CanonicalStateKey
    package let action: String
    package let target: CanonicalStateKey

    package init(source: CanonicalStateKey, action: String, target: CanonicalStateKey) {
        self.source = source
        self.action = action
        self.target = target
    }

    package var canonicalEncoding: String {
        "edge:\(source.canonicalEncoding)--\(encodedBytes(action))-->\(target.canonicalEncoding)"
    }

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.target == rhs.target
            && lhs.action.utf8.count == rhs.action.utf8.count
            && compareUTF8Prefixes(lhs.action, rhs.action) == 0
    }

    package static func < (lhs: Self, rhs: Self) -> Bool {
        let left = lhs.source.canonicalEncoding
        let right = rhs.source.canonicalEncoding
        let order = compareUTF8Prefixes(left, right)
        if order != 0 { return order < 0 }
        // A prefix key can overlap the wire delimiter; compare the complete
        // encoding in that unusual case to preserve the exact byte ordering.
        if left.utf8.count != right.utf8.count {
            return canonicalBytes(lhs.canonicalEncoding, rhs.canonicalEncoding)
        }
        // Hex encoding preserves byte order; its delimiter sorts before every hex digit.
        let actionOrder = compareUTF8Prefixes(lhs.action, rhs.action)
        if actionOrder != 0 { return actionOrder < 0 }
        if lhs.action.utf8.count != rhs.action.utf8.count { return lhs.action.utf8.count < rhs.action.utf8.count }
        return canonicalBytes(lhs.target.canonicalEncoding, rhs.target.canonicalEncoding)
    }

}

private struct IndexedCanonicalEdge: Hashable, Sendable {
    let source: Int
    let action: String
    let target: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.target == rhs.target
            && lhs.action.utf8.count == rhs.action.utf8.count
            && compareUTF8Prefixes(lhs.action, rhs.action) == 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(source)
        hasher.combine(action)
        hasher.combine(target)
    }
}

private struct CanonicalEdgeIndex: Equatable, Sendable {
    let stateKeys: [CanonicalStateKey]
    private let hasPrefixOverlap: Bool
    private let firstIDByHash: [Int: Int]
    private let collisions: [Int: [Int]]
    private var indexedEdges: Set<IndexedCanonicalEdge> = []
    private(set) var actions: Set<String> = []

    init(stateKeys: [CanonicalStateKey], reservingCapacity count: Int = 0) {
        self.stateKeys = stateKeys
        hasPrefixOverlap = zip(stateKeys, stateKeys.dropFirst()).contains {
            $1.canonicalEncoding.hasPrefix($0.canonicalEncoding)
        }
        var firstIDByHash: [Int: Int] = [:]
        firstIDByHash.reserveCapacity(stateKeys.count)
        var collisions: [Int: [Int]] = [:]
        for (id, key) in stateKeys.enumerated() {
            let hash = key.hashValue
            if firstIDByHash[hash] == nil {
                firstIDByHash[hash] = id
            } else {
                collisions[hash, default: []].append(id)
            }
        }
        self.firstIDByHash = firstIDByHash
        self.collisions = collisions
        indexedEdges.reserveCapacity(count)
    }

    var count: Int { indexedEdges.count }

    func id(for key: CanonicalStateKey) -> Int? {
        let hash = key.hashValue
        guard let first = firstIDByHash[hash] else { return nil }
        if stateKeys[first] == key { return first }
        return collisions[hash]?.first { stateKeys[$0] == key }
    }

    mutating func insert(_ edge: CanonicalEdge) throws {
        guard let source = id(for: edge.source) else { throw CanonicalGraphError.edgeStateMissing(edge.source) }
        guard let target = id(for: edge.target) else { throw CanonicalGraphError.edgeStateMissing(edge.target) }
        insert(source: source, action: edge.action, target: target)
    }

    mutating func insert(source: Int, action: String, target: Int) {
        indexedEdges.insert(.init(source: source, action: action, target: target))
        actions.insert(action)
    }

    func contains(_ edge: CanonicalEdge) -> Bool {
        guard let source = id(for: edge.source), let target = id(for: edge.target) else { return false }
        return indexedEdges.contains(.init(source: source, action: edge.action, target: target))
    }

    func hasSource(_ id: Int) -> Bool { indexedEdges.contains { $0.source == id } }

    func expanded() -> Set<CanonicalEdge> {
        Set(indexedEdges.map(edge))
    }

    func forEachOrdered(_ body: (CanonicalEdge) throws -> Void) rethrows {
        var ordered = Array(indexedEdges)
        ordered.sort { lhs, rhs in
            if lhs.source != rhs.source {
                let left = stateKeys[lhs.source].canonicalEncoding
                let right = stateKeys[rhs.source].canonicalEncoding
                if hasPrefixOverlap && (left.hasPrefix(right) || right.hasPrefix(left)) {
                    return edge(lhs) < edge(rhs)
                }
                return lhs.source < rhs.source
            }
            let actionOrder = compareUTF8Prefixes(lhs.action, rhs.action)
            if actionOrder != 0 { return actionOrder < 0 }
            if lhs.action.utf8.count != rhs.action.utf8.count {
                return lhs.action.utf8.count < rhs.action.utf8.count
            }
            return lhs.target < rhs.target
        }
        for item in ordered { try body(edge(item)) }
    }

    private func edge(_ indexed: IndexedCanonicalEdge) -> CanonicalEdge {
        CanonicalEdge(source: stateKeys[indexed.source], action: indexed.action,
                      target: stateKeys[indexed.target])
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count else { return false }
        if lhs.stateKeys == rhs.stateKeys { return lhs.indexedEdges == rhs.indexedEdges }
        return lhs.indexedEdges.allSatisfy { rhs.contains(lhs.edge($0)) }
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
    table.reserveCapacity(states.underestimatedCount)
    for state in states {
        guard table.updateValue(state, forKey: state.key) == nil else {
            throw CanonicalGraphError.duplicateState(state.key)
        }
    }
    return table
}

package struct NativeCanonicalKeyIndex<Snapshot: Hashable & Sendable>: Sendable {
    private var keysByHash: [Int: CanonicalStateKey] = [:]
    private var collisions: [Int: Set<CanonicalStateKey>] = [:]
    private var idsByHash: [Int: Int] = [:]
    private var collisionIDs: [Int: [(key: CanonicalStateKey, id: Int)]] = [:]
    private var stateKeys: [CanonicalStateKey] = []

    package init(reservingCapacity count: Int = 0) {
        keysByHash.reserveCapacity(count)
    }

    package var sortedKeys: [CanonicalStateKey] { stateKeys }

    package mutating func insert(_ snapshot: Snapshot, key: CanonicalStateKey) {
        let hash = snapshot.hashValue
        if let existing = keysByHash[hash] {
            collisions[hash, default: [existing]].insert(key)
        } else {
            keysByHash[hash] = key
        }
    }

    package mutating func finalize(sortedKeys: [CanonicalStateKey]) throws {
        var idsByKey: [CanonicalStateKey: Int] = [:]
        idsByKey.reserveCapacity(sortedKeys.count)
        for (id, key) in sortedKeys.enumerated() { idsByKey[key] = id }
        var idsByHash: [Int: Int] = [:]
        idsByHash.reserveCapacity(keysByHash.count)
        for (hash, key) in keysByHash {
            guard let id = idsByKey[key] else { throw CanonicalGraphError.missingNativeSnapshot }
            idsByHash[hash] = id
        }
        var collisionIDs: [Int: [(key: CanonicalStateKey, id: Int)]] = [:]
        for (hash, candidates) in collisions {
            collisionIDs[hash] = try candidates.map { key in
                guard let id = idsByKey[key] else { throw CanonicalGraphError.missingNativeSnapshot }
                return (key, id)
            }
        }
        self.idsByHash = idsByHash
        self.collisionIDs = collisionIDs
        stateKeys = sortedKeys
        keysByHash.removeAll()
        collisions.removeAll()
    }

    package func idForKnownSnapshot(
        _ snapshot: Snapshot,
        projecting: () throws -> CanonicalStateKey
    ) throws -> Int {
        let hash = snapshot.hashValue
        guard let id = idsByHash[hash] else { throw CanonicalGraphError.missingNativeSnapshot }
        guard let candidates = collisionIDs[hash] else { return id }
        let projected = try projecting()
        guard let match = candidates.first(where: { $0.key == projected }) else {
            throw CanonicalGraphError.missingNativeSnapshot
        }
        return match.id
    }

    package func key(
        for snapshot: Snapshot,
        projecting: () throws -> CanonicalStateKey
    ) throws -> CanonicalStateKey {
        let projected = try projecting()
        let id = try idForKnownSnapshot(snapshot, projecting: { projected })
        guard stateKeys[id] == projected else { throw CanonicalGraphError.missingNativeSnapshot }
        return stateKeys[id]
    }
}

package struct NativeCanonicalStates<Snapshot: Hashable & Sendable>: Sendable {
    private let keys: NativeCanonicalKeyIndex<Snapshot>
    package let states: [CanonicalStateKey: CanonicalState]

    package init<Machine: StateMachine>(_ native: ReachabilityGraph<Machine>) throws
        where Machine.Snapshot == Snapshot {
        var keys = NativeCanonicalKeyIndex<Snapshot>(reservingCapacity: native.transitions.count)
        var states: [CanonicalStateKey: CanonicalState] = [:]
        states.reserveCapacity(native.transitions.count)
        for snapshot in native.transitions.keys {
            let state = try CanonicalState(native.formalProjection(of: snapshot))
            guard states.updateValue(state, forKey: state.key) == nil else {
                throw CanonicalGraphError.duplicateState(state.key)
            }
            keys.insert(snapshot, key: state.key)
        }
        let unorderedKeys = Array(states.keys)
        var offsets = Array(unorderedKeys.indices)
        offsets.sort { unorderedKeys[$0] < unorderedKeys[$1] }
        try keys.finalize(sortedKeys: offsets.map { unorderedKeys[$0] })
        self.keys = keys
        self.states = states
    }

    package func key<Machine: StateMachine>(
        for snapshot: Snapshot, in native: ReachabilityGraph<Machine>
    ) throws -> CanonicalStateKey where Machine.Snapshot == Snapshot {
        return try keys.key(for: snapshot) {
            try CanonicalState(native.formalProjection(of: snapshot)).key
        }
    }

    package func idForKnownSnapshot<Machine: StateMachine>(
        _ snapshot: Snapshot, in native: ReachabilityGraph<Machine>
    ) throws -> Int where Machine.Snapshot == Snapshot {
        try keys.idForKnownSnapshot(snapshot) {
            try CanonicalState(native.formalProjection(of: snapshot)).key
        }
    }

    package var sortedKeys: [CanonicalStateKey] { keys.sortedKeys }
}

package struct CanonicalGraph: Equatable, Sendable {
    package let initialStateKeys: Set<CanonicalStateKey>
    package let states: [CanonicalStateKey: CanonicalState]
    /// The labeled transition relation; repeated evaluation witnesses add no behavior.
    private let edgeIndex: CanonicalEdgeIndex
    package var edges: Set<CanonicalEdge> { edgeIndex.expanded() }
    package var edgeCount: Int { edgeIndex.count }
    package var sortedStateKeys: [CanonicalStateKey] { edgeIndex.stateKeys }
    package let observedActions: Set<String>

    package init(
        initialStates: [CanonicalState],
        states: some Sequence<CanonicalState>,
        edges: some Sequence<CanonicalEdge>
    ) throws {
        let stateTable = try canonicalStateTable(states)
        var edgeIndex = CanonicalEdgeIndex(stateKeys: stateTable.keys.sorted(),
                                           reservingCapacity: edges.underestimatedCount)
        for edge in edges { try edgeIndex.insert(edge) }
        try self.init(initialStateKeys: Set(initialStates.map(\.key)), stateTable: stateTable,
                      edgeIndex: edgeIndex)
    }

    private init(
        initialStateKeys: Set<CanonicalStateKey>,
        stateTable: [CanonicalStateKey: CanonicalState],
        edgeIndex: CanonicalEdgeIndex
    ) throws {
        let expectedBindings = stateTable.values.first.map { Set($0.bindings.keys) } ?? []
        for state in stateTable.values where state.bindings.count != expectedBindings.count
            || !state.bindings.keys.allSatisfy(expectedBindings.contains) {
            throw CanonicalGraphError.inconsistentStateBindings(
                expected: expectedBindings,
                actual: Set(state.bindings.keys)
            )
        }

        for key in initialStateKeys where stateTable.index(forKey: key) == nil {
            throw CanonicalGraphError.initialStateMissing(key)
        }

        self.initialStateKeys = initialStateKeys
        self.states = stateTable
        self.edgeIndex = edgeIndex
        self.observedActions = edgeIndex.actions
    }

    /// Export native topology only; this does not issue a property-checking verdict.
    package init<Machine: StateMachine>(_ native: ReachabilityGraph<Machine>) throws {
        try self.init(native, projectedStates: NativeCanonicalStates(native))
    }

    package init<Machine: StateMachine>(
        _ native: ReachabilityGraph<Machine>, projectedStates: NativeCanonicalStates<Machine.Snapshot>,
        renderedActionNames: [String: String] = [:]
    ) throws {
        guard projectedStates.states.count == native.transitions.count else {
            throw CanonicalGraphError.missingNativeSnapshot
        }
        var actionNames: [Machine.Action: String] = [:]
        func actionName(_ action: Machine.Action) throws -> String {
            if let name = actionNames[action] { return name }
            let invocation = try native.formalCall(for: action).description
            let name = renderedActionNames[invocation] ?? invocation
            actionNames[action] = name
            return name
        }
        var edgeIndex = CanonicalEdgeIndex(stateKeys: projectedStates.sortedKeys,
            reservingCapacity: native.transitions.values.reduce(0) { $0 + $1.count })
        for (source, successors) in native.transitions {
            let sourceID = try projectedStates.idForKnownSnapshot(source, in: native)
            for successor in successors {
                edgeIndex.insert(source: sourceID, action: try actionName(successor.action),
                                 target: try projectedStates.idForKnownSnapshot(successor.target, in: native))
            }
        }
        try self.init(initialStateKeys: Set(try native.initialStates.map { try projectedStates.key(for: $0, in: native) }),
                      stateTable: projectedStates.states, edgeIndex: edgeIndex)
    }

    package func containsEdge(_ edge: CanonicalEdge) -> Bool { edgeIndex.contains(edge) }

    package func forEachOrderedEdge(_ body: (CanonicalEdge) throws -> Void) rethrows {
        try edgeIndex.forEachOrdered(body)
    }

    package func hasOutgoingEdges(from state: CanonicalStateKey) -> Bool {
        guard let id = edgeIndex.id(for: state) else { return false }
        return edgeIndex.hasSource(id)
    }

    package func hasSameEdges(as other: Self) -> Bool { edgeIndex == other.edgeIndex }

    package var variableNames: Set<String> {
        states.values.first.map { Set($0.bindings.keys) } ?? []
    }

}

package enum GraphRunOutcome: Hashable, Sendable {
    case noViolation
    case invariantViolation(String)
    case refinementViolation(String)
    case deadlock(CanonicalStateKey)
    case incomplete(reason: String)
    case executionError(String)

    package var isConclusive: Bool {
        switch self {
        case .noViolation, .invariantViolation, .refinementViolation, .deadlock: true
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
        let container = try decoder.container(validatingKeys: CodingKeys.self)
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
        let container = try decoder.container(validatingKeys: CodingKeys.self)
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
            guard graph.containsEdge(edge) else { throw GraphRunError.traceEdgeMissing(edge) }
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
        for action in graph.observedActions where !observableActions.contains(action) {
            throw GraphRunError.graphActionUndeclared(action)
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
    let order = compareUTF8Prefixes(lhs, rhs)
    return order == 0 ? lhs.utf8.count < rhs.utf8.count : order < 0
}

/// Compare the shared byte extent without decoding Unicode or iterating byte by byte in Swift.
private func compareUTF8Prefixes(_ lhs: String, _ rhs: String) -> Int32 {
    var left = lhs
    var right = rhs
    return left.withUTF8 { leftBytes in
        right.withUTF8 { rightBytes in
            let count = min(leftBytes.count, rightBytes.count)
            guard count > 0 else { return 0 }
            return memcmp(leftBytes.baseAddress!, rightBytes.baseAddress!, count)
        }
    }
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
