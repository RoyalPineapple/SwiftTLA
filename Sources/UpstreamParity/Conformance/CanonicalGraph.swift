import Foundation
import SwiftTLA

public enum CanonicalSchemaErrorV1: Error, Equatable, Sendable {
    case unknownSchema(String)
}

public enum CanonicalSchemaV1: String, Hashable, Sendable {
    case exactFiniteTLCGraphV1

    public init(validating rawValue: String) throws {
        guard let schema = Self(rawValue: rawValue) else {
            throw CanonicalSchemaErrorV1.unknownSchema(rawValue)
        }
        self = schema
    }
}

public enum CanonicalValueV1: Hashable, Sendable {
    case integer(Int)
    case boolean(Bool)
    case string(String)
    case constant(String)
    case orderedSet([CanonicalValueV1])
    case orderedTuple([CanonicalValueV1])
    case orderedRecord([CanonicalRecordFieldV1])
    case orderedFunction([CanonicalFunctionEntryV1])

    public static func set(_ values: [CanonicalValueV1]) -> CanonicalValueV1 {
        .orderedSet(values.sorted { canonicalBytes($0.canonicalEncoding, $1.canonicalEncoding) })
    }

    public static func tuple(_ values: [CanonicalValueV1]) -> CanonicalValueV1 {
        .orderedTuple(values)
    }

    public static func record(_ fields: [String: CanonicalValueV1]) -> CanonicalValueV1 {
        .orderedRecord(fields.map { CanonicalRecordFieldV1(name: $0.key, value: $0.value) }
            .sorted { canonicalBytes($0.name, $1.name) })
    }

    public static func function(_ entries: [CanonicalFunctionEntryV1]) -> CanonicalValueV1 {
        let ordered = entries.sorted { canonicalBytes($0.key.canonicalEncoding, $1.key.canonicalEncoding) }
        precondition(
            Set(ordered.map(\.key)).count == ordered.count,
            "A canonical finite function cannot contain duplicate keys."
        )
        return .orderedFunction(ordered)
    }

    public init(_ value: TLAValue) {
        switch value {
        case .int(let value): self = .integer(value)
        case .bool(let value): self = .boolean(value)
        case .string(let value): self = .string(value)
        case .constant(let value): self = .constant(value)
        case .set(let values): self = .set(values.map(Self.init))
        case .tuple(let values): self = .tuple(values.map(Self.init))
        case .record(let fields): self = .record(fields.mapValues(Self.init))
        case .function(let entries):
            self = .function(entries.map { CanonicalFunctionEntryV1(key: Self($0.key), value: Self($0.value)) })
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

public struct CanonicalRecordFieldV1: Hashable, Sendable {
    public let name: String
    public let value: CanonicalValueV1

    public init(name: String, value: CanonicalValueV1) {
        self.name = name
        self.value = value
    }
}

public struct CanonicalFunctionEntryV1: Hashable, Sendable {
    public let key: CanonicalValueV1
    public let value: CanonicalValueV1

    public init(key: CanonicalValueV1, value: CanonicalValueV1) {
        self.key = key
        self.value = value
    }
}

public struct CanonicalStateKeyV1: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let canonicalEncoding: String

    public init(canonicalEncoding: String) {
        self.canonicalEncoding = canonicalEncoding
    }

    public var description: String { canonicalEncoding }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        canonicalBytes(lhs.canonicalEncoding, rhs.canonicalEncoding)
    }
}

public struct CanonicalStateV1: Hashable, Sendable {
    public let bindings: [String: CanonicalValueV1]

    public init(bindings: [String: CanonicalValueV1]) {
        self.bindings = bindings
    }

    public var key: CanonicalStateKeyV1 {
        let fields = bindings.sorted { canonicalBytes($0.key, $1.key) }
            .map { "\(encodedBytes($0.key))=\($0.value.canonicalEncoding)" }
            .joined(separator: ",")
        return CanonicalStateKeyV1(canonicalEncoding: "state:[\(fields)]")
    }
}

public struct CanonicalEdgeV1: Hashable, Sendable, Comparable {
  public let source: CanonicalStateKeyV1
  public let action: String
  public let target: CanonicalStateKeyV1
  public let canonicalEncoding: String

  public init(source: CanonicalStateKeyV1, action: String, target: CanonicalStateKeyV1) {
    self.source = source
    self.action = action
    self.target = target
    canonicalEncoding = "edge:\(source.canonicalEncoding)--\(encodedBytes(action))-->\(target.canonicalEncoding)"
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        canonicalBytes(lhs.canonicalEncoding, rhs.canonicalEncoding)
    }

}

public struct CanonicalStateObservationV1: Hashable, Sendable {
    public let enabledActions: Set<String>
    public let isTerminal: Bool

    public init(enabledActions: Set<String>, isTerminal: Bool) {
        self.enabledActions = enabledActions
        self.isTerminal = isTerminal
    }
}

public enum CanonicalGraphErrorV1: Error, Equatable, Sendable {
    case inconsistentStateBindings(expected: Set<String>, actual: Set<String>)
    case initialStateMissing(CanonicalStateKeyV1)
    case edgeStateMissing(CanonicalStateKeyV1)
}

public struct CanonicalGraphV1: Equatable, Sendable {
    public let initialStateKeys: Set<CanonicalStateKeyV1>
    public let states: [CanonicalStateKeyV1: CanonicalStateV1]
    public let edgeOccurrences: [CanonicalEdgeV1: Int]

    public init(
        initialStates: [CanonicalStateV1],
        states: [CanonicalStateV1],
        edges: some Sequence<CanonicalEdgeV1>
    ) throws {
        let stateTable = Dictionary(uniqueKeysWithValues: states.map { ($0.key, $0) })
        let expectedBindings = stateTable.values.first.map { Set($0.bindings.keys) } ?? []
        for state in stateTable.values where Set(state.bindings.keys) != expectedBindings {
            throw CanonicalGraphErrorV1.inconsistentStateBindings(
                expected: expectedBindings,
                actual: Set(state.bindings.keys)
            )
        }

        let initialKeys = Set(initialStates.map(\.key))
        for key in initialKeys where stateTable[key] == nil {
            throw CanonicalGraphErrorV1.initialStateMissing(key)
        }

        var occurrences: [CanonicalEdgeV1: Int] = [:]
        for edge in edges {
            guard stateTable[edge.source] != nil else {
                throw CanonicalGraphErrorV1.edgeStateMissing(edge.source)
            }
            guard stateTable[edge.target] != nil else {
                throw CanonicalGraphErrorV1.edgeStateMissing(edge.target)
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

    public var observations: [CanonicalStateKeyV1: CanonicalStateObservationV1] {
        let enabledByState = edgeOccurrences.keys.reduce(into: [CanonicalStateKeyV1: Set<String>]()) { result, edge in
            result[edge.source, default: []].insert(edge.action)
        }
        return Dictionary(uniqueKeysWithValues: states.keys.map { key in
            let enabledActions = enabledByState[key, default: []]
            return (key, CanonicalStateObservationV1(
                enabledActions: enabledActions,
                isTerminal: enabledActions.isEmpty
            ))
        })
    }
}

public enum CanonicalOutcomeV1: Hashable, Sendable {
    case exhaustiveSuccess
    case invariantViolation(String)
    case deadlock(CanonicalStateKeyV1)
    case incomplete(reason: String)
    case executionError(String)

    public var isExhaustiveSuccess: Bool {
        if case .exhaustiveSuccess = self { return true }
        return false
    }
}

public struct CanonicalDiagnosticV1: Hashable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct CanonicalTraceStepV1: Hashable, Sendable {
    public let state: CanonicalStateKeyV1
    public let action: String

    public init(state: CanonicalStateKeyV1, action: String) {
        self.state = state
        self.action = action
    }
}

public struct CanonicalTraceV1: Hashable, Sendable {
    public let id: String
    public let steps: [CanonicalTraceStepV1]

    public init(id: String, steps: [CanonicalTraceStepV1]) {
        self.id = id
        self.steps = steps
    }
}

public enum CanonicalRunErrorV1: Error, Equatable, Sendable {
    case duplicateTraceID(String)
    case graphActionUndeclared(String)
    case deadlockStateMissing(CanonicalStateKeyV1)
    case traceStateMissing(CanonicalStateKeyV1)
}

public struct CanonicalRunV1: Equatable, Sendable {
    public let schema: CanonicalSchemaV1
    public let graph: CanonicalGraphV1
    public let observableActions: Set<String>
    public let outcome: CanonicalOutcomeV1
    public let errors: [CanonicalDiagnosticV1]
    public let traces: [CanonicalTraceV1]

    public init(
        schema: CanonicalSchemaV1 = .exactFiniteTLCGraphV1,
        graph: CanonicalGraphV1,
        observableActions: Set<String>,
        outcome: CanonicalOutcomeV1,
        errors: [CanonicalDiagnosticV1] = [],
        traces: [CanonicalTraceV1] = []
    ) throws {
        let traceIDs = traces.map(\.id)
        guard Set(traceIDs).count == traceIDs.count else {
            throw CanonicalRunErrorV1.duplicateTraceID(traceIDs.sorted().first ?? "")
        }
        for edge in graph.edgeOccurrences.keys where !observableActions.contains(edge.action) {
            throw CanonicalRunErrorV1.graphActionUndeclared(edge.action)
        }
        if case .deadlock(let state) = outcome, graph.states[state] == nil {
            throw CanonicalRunErrorV1.deadlockStateMissing(state)
        }
        for trace in traces {
            for step in trace.steps where graph.states[step.state] == nil {
                throw CanonicalRunErrorV1.traceStateMissing(step.state)
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
