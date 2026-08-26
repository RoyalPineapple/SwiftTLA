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
        .orderedSet(values.sorted { canonicalBytes($0.canonicalEncoding, $1.canonicalEncoding) })
    }

    package static func tuple(_ values: [CanonicalValue]) -> CanonicalValue {
        .orderedTuple(values)
    }

    package static func record(_ fields: [String: CanonicalValue]) -> CanonicalValue {
        .orderedRecord(fields.map { CanonicalRecordField(name: $0.key, value: $0.value) }
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

package struct CanonicalStateKey: Hashable, Sendable, Comparable, CustomStringConvertible {
    package let canonicalEncoding: String

    package init(canonicalEncoding: String) {
        self.canonicalEncoding = canonicalEncoding
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
    case inconsistentStateBindings(expected: Set<String>, actual: Set<String>)
    case initialStateMissing(CanonicalStateKey)
    case edgeStateMissing(CanonicalStateKey)
}

package struct CanonicalGraph: Equatable, Sendable {
    package let initialStateKeys: Set<CanonicalStateKey>
    package let states: [CanonicalStateKey: CanonicalState]
    package let edgeOccurrences: [CanonicalEdge: Int]

    package init(
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

    package var variableNames: Set<String> {
        states.values.first.map { Set($0.bindings.keys) } ?? []
    }

}

package enum CanonicalOutcome: Hashable, Sendable {
    case exhaustiveSuccess
    case invariantViolation(String)
    case deadlock(CanonicalStateKey)
    case incomplete(reason: String)
    case executionError(String)

    package var isExhaustiveSuccess: Bool {
        if case .exhaustiveSuccess = self { return true }
        return false
    }
}

package struct CanonicalDiagnostic: Hashable, Sendable {
    package let code: String
    package let message: String

    package init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

package struct CanonicalTraceStep: Hashable, Sendable {
    package let state: CanonicalStateKey
    package let action: String

    package init(state: CanonicalStateKey, action: String) {
        self.state = state
        self.action = action
    }
}

package struct CanonicalTrace: Hashable, Sendable {
    package let id: String
    package let steps: [CanonicalTraceStep]

    package init(id: String, steps: [CanonicalTraceStep]) {
        self.id = id
        self.steps = steps
    }
}

package enum CompletedGraphRunError: Error, Equatable, Sendable {
    case duplicateTraceID(String)
    case graphActionUndeclared(String)
    case deadlockStateMissing(CanonicalStateKey)
    case traceStateMissing(CanonicalStateKey)
}

package struct CompletedGraphRun: Equatable, Sendable {
    package let graph: CanonicalGraph
    package let observableActions: Set<String>
    package let outcome: CanonicalOutcome
    package let errors: [CanonicalDiagnostic]
    package let traces: [CanonicalTrace]

    package init(
        graph: CanonicalGraph,
        observableActions: Set<String>,
        outcome: CanonicalOutcome,
        errors: [CanonicalDiagnostic] = [],
        traces: [CanonicalTrace] = []
    ) throws {
        let traceIDs = traces.map(\.id)
        guard Set(traceIDs).count == traceIDs.count else {
            throw CompletedGraphRunError.duplicateTraceID(traceIDs.sorted().first ?? "")
        }
        for edge in graph.edgeOccurrences.keys where !observableActions.contains(edge.action) {
            throw CompletedGraphRunError.graphActionUndeclared(edge.action)
        }
        if case .deadlock(let state) = outcome, graph.states[state] == nil {
            throw CompletedGraphRunError.deadlockStateMissing(state)
        }
        for trace in traces {
            for step in trace.steps where graph.states[step.state] == nil {
                throw CompletedGraphRunError.traceStateMissing(step.state)
            }
        }

        self.graph = graph
        self.observableActions = observableActions
        self.outcome = outcome
        self.errors = errors
        self.traces = traces
    }

    package var isPassEligible: Bool {
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
