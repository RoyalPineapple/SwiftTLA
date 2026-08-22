import Foundation
import SwiftTLA

public enum CanonicalSchemaError: Error, Equatable, Sendable {
    case unknownSchema(String)
}

public enum CanonicalValueError: Error, Equatable, Sendable, CustomStringConvertible {
    case duplicateFunctionKey(CanonicalValue)

    public var description: String {
        switch self {
        case .duplicateFunctionKey(let key):
            return "Canonical function contains duplicate key \(key.canonicalEncoding)."
        }
    }
}

public enum CanonicalSchema: String, Hashable, Sendable {
    case exactFiniteTLCGraph

    public init(validating rawValue: String) throws {
        guard let schema = Self(rawValue: rawValue) else {
            throw CanonicalSchemaError.unknownSchema(rawValue)
        }
        self = schema
    }
}

public enum CanonicalValue: Hashable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case string(String)
    case constant(String)
    case orderedSet([CanonicalValue])
    case orderedTuple([CanonicalValue])
    case orderedRecord([CanonicalRecordField])
    case orderedFunction([CanonicalFunctionEntry])

    public static func set(_ values: [CanonicalValue]) -> CanonicalValue {
        .orderedSet(values.sorted { canonicalBytes($0.canonicalEncoding, $1.canonicalEncoding) })
    }

    public static func tuple(_ values: [CanonicalValue]) -> CanonicalValue {
        .orderedTuple(values)
    }

    public static func record(_ fields: [String: CanonicalValue]) -> CanonicalValue {
        .orderedRecord(fields.map { CanonicalRecordField(name: $0.key, value: $0.value) }
            .sorted { canonicalBytes($0.name, $1.name) })
    }

    public static func function(_ entries: [CanonicalFunctionEntry]) throws -> CanonicalValue {
        let ordered = entries.sorted { canonicalBytes($0.key.canonicalEncoding, $1.key.canonicalEncoding) }
        var keys = Set<CanonicalValue>()
        for entry in ordered {
            guard keys.insert(entry.key).inserted else {
                throw CanonicalValueError.duplicateFunctionKey(entry.key)
            }
        }
        return .orderedFunction(ordered)
    }

    public init(_ value: TLAValue) throws {
        switch value {
        case .int(let value): self = .integer(value)
        case .bool(let value): self = .boolean(value)
        case .string(let value): self = .string(value)
        case .constant(let value): self = .constant(value)
        case .set(let values): self = .set(try values.map(Self.init))
        case .tuple(let values): self = .tuple(try values.map(Self.init))
        case .record(let fields): self = .record(try fields.mapValues(Self.init))
        case .function(let entries):
            self = try .function(entries.map { try CanonicalFunctionEntry(key: Self($0.key), value: Self($0.value)) })
        }
    }

    public var canonicalEncoding: String {
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

public struct CanonicalRecordField: Hashable, Sendable {
    public let name: String
    public let value: CanonicalValue

    public init(name: String, value: CanonicalValue) {
        self.name = name
        self.value = value
    }
}

public struct CanonicalFunctionEntry: Hashable, Sendable {
    public let key: CanonicalValue
    public let value: CanonicalValue

    public init(key: CanonicalValue, value: CanonicalValue) {
        self.key = key
        self.value = value
    }
}

public struct CanonicalStateKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let canonicalEncoding: String

    public init(canonicalEncoding: String) {
        self.canonicalEncoding = canonicalEncoding
    }

    public var description: String { canonicalEncoding }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        canonicalBytes(lhs.canonicalEncoding, rhs.canonicalEncoding)
    }
}

public struct CanonicalState: Hashable, Sendable {
    public let bindings: [String: CanonicalValue]

    public init(bindings: [String: CanonicalValue]) {
        self.bindings = bindings
    }

    public var key: CanonicalStateKey {
        let fields = bindings.sorted { canonicalBytes($0.key, $1.key) }
            .map { "\(encodedBytes($0.key))=\($0.value.canonicalEncoding)" }
            .joined(separator: ",")
        return CanonicalStateKey(canonicalEncoding: "state:[\(fields)]")
    }
}

public struct CanonicalEdge: Hashable, Sendable, Comparable {
  public let source: CanonicalStateKey
  public let action: String
  public let target: CanonicalStateKey
  public let canonicalEncoding: String

  public init(source: CanonicalStateKey, action: String, target: CanonicalStateKey) {
    self.source = source
    self.action = action
    self.target = target
    canonicalEncoding = "edge:\(source.canonicalEncoding)--\(encodedBytes(action))-->\(target.canonicalEncoding)"
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        canonicalBytes(lhs.canonicalEncoding, rhs.canonicalEncoding)
    }

}

public struct CanonicalStateObservation: Hashable, Sendable {
    public let enabledActions: Set<String>
    public let isTerminal: Bool

    public init(enabledActions: Set<String>, isTerminal: Bool) {
        self.enabledActions = enabledActions
        self.isTerminal = isTerminal
    }
}

public enum CanonicalGraphError: Error, Equatable, Sendable {
    case inconsistentStateBindings(expected: Set<String>, actual: Set<String>)
    case initialStateMissing(CanonicalStateKey)
    case edgeStateMissing(CanonicalStateKey)
}

public struct CanonicalGraph: Equatable, Sendable {
    public let initialStateKeys: Set<CanonicalStateKey>
    public let states: [CanonicalStateKey: CanonicalState]
    public let edgeOccurrences: [CanonicalEdge: Int]

    public init(
        initialStates: [CanonicalState],
        states: [CanonicalState],
        edges: some Sequence<CanonicalEdge>
    ) throws {
        let stateTable = Dictionary(uniqueKeysWithValues: states.map { ($0.key, $0) })
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

        var occurrences: [CanonicalEdge: Int] = [:]
        for edge in edges {
            guard stateTable[edge.source] != nil else {
                throw CanonicalGraphError.edgeStateMissing(edge.source)
            }
            guard stateTable[edge.target] != nil else {
                throw CanonicalGraphError.edgeStateMissing(edge.target)
            }
            occurrences[edge, default: 0] += 1
        }

        self.initialStateKeys = initialKeys
        self.states = stateTable
        self.edgeOccurrences = occurrences
    }

    public var variableNames: Set<String> {
        states.values.first.map { Set($0.bindings.keys) } ?? []
    }

    public var observations: [CanonicalStateKey: CanonicalStateObservation] {
        let enabledByState = edgeOccurrences.keys.reduce(into: [CanonicalStateKey: Set<String>]()) { result, edge in
            result[edge.source, default: []].insert(edge.action)
        }
        return Dictionary(uniqueKeysWithValues: states.keys.map { key in
            let enabledActions = enabledByState[key, default: []]
            return (key, CanonicalStateObservation(
                enabledActions: enabledActions,
                isTerminal: enabledActions.isEmpty
            ))
        })
    }
}

public enum CanonicalOutcome: Hashable, Sendable {
    case exhaustiveSuccess
    case invariantViolation(String)
    case deadlock(CanonicalStateKey)
    case incomplete(reason: String)
    case executionError(String)

    public var isExhaustiveSuccess: Bool {
        if case .exhaustiveSuccess = self { return true }
        return false
    }
}

public struct CanonicalDiagnostic: Hashable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct CanonicalTraceStep: Hashable, Sendable {
    public let state: CanonicalStateKey
    public let action: String

    public init(state: CanonicalStateKey, action: String) {
        self.state = state
        self.action = action
    }
}

public struct CanonicalTrace: Hashable, Sendable {
    public let id: String
    public let steps: [CanonicalTraceStep]

    public init(id: String, steps: [CanonicalTraceStep]) {
        self.id = id
        self.steps = steps
    }
}

public enum CanonicalRunError: Error, Equatable, Sendable {
    case duplicateTraceID(String)
    case graphActionUndeclared(String)
    case deadlockStateMissing(CanonicalStateKey)
    case traceStateMissing(CanonicalStateKey)
}

public struct CanonicalRun: Equatable, Sendable {
    public let schema: CanonicalSchema
    public let graph: CanonicalGraph
    public let observableActions: Set<String>
    public let outcome: CanonicalOutcome
    public let errors: [CanonicalDiagnostic]
    public let traces: [CanonicalTrace]

    public init(
        schema: CanonicalSchema = .exactFiniteTLCGraph,
        graph: CanonicalGraph,
        observableActions: Set<String>,
        outcome: CanonicalOutcome,
        errors: [CanonicalDiagnostic] = [],
        traces: [CanonicalTrace] = []
    ) throws {
        let traceIDs = traces.map(\.id)
        guard Set(traceIDs).count == traceIDs.count else {
            throw CanonicalRunError.duplicateTraceID(traceIDs.sorted().first ?? "")
        }
        for edge in graph.edgeOccurrences.keys where !observableActions.contains(edge.action) {
            throw CanonicalRunError.graphActionUndeclared(edge.action)
        }
        if case .deadlock(let state) = outcome, graph.states[state] == nil {
            throw CanonicalRunError.deadlockStateMissing(state)
        }
        for trace in traces {
            for step in trace.steps where graph.states[step.state] == nil {
                throw CanonicalRunError.traceStateMissing(step.state)
            }
        }

        self.schema = schema
        self.graph = graph
        self.observableActions = observableActions
        self.outcome = outcome
        self.errors = errors
        self.traces = traces
    }

    public var isPassEligible: Bool {
        outcome.isExhaustiveSuccess && errors.isEmpty
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
