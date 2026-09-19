import CoreFoundation
import CryptoKit
import Foundation

package enum TLCGraphEventError: Error, Equatable, Sendable {
    case invalidUTF8
    case malformedJSON(line: Int)
    case duplicateKey(line: Int, key: String)
    case invalidRecord(line: Int, reason: String)
    case missingFooter
    case invalidFooter(String)
    case unsupportedCallback(String)
    case unsupportedValue(String)
    case incompleteExecution(String)
}

package struct TLCBinding: Equatable, Sendable {
    package let name: String
    package let tla: String

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name.utf8.elementsEqual(rhs.name.utf8)
            && lhs.tla.utf8.elementsEqual(rhs.tla.utf8)
    }
}

package struct TLCGraphState: Equatable, Sendable {
    package let fingerprint: String
    package let bindings: [TLCBinding]
}

/// A validated transition between TLC state fingerprints.
package struct TLCGraphTransition: Hashable, Sendable {
    package let source: String
    package let target: String
    package let action: String
}

package struct TLCGraphEventStream: Equatable, Sendable {
    package let runID: UUID
    package let caseID: String
    package let states: [String: TLCGraphState]
    package let initialStates: Set<String>
    package let transitions: Set<TLCGraphTransition>
}

package struct TLCGraphReader: Sendable {
    private let finiteGraphCase: FiniteGraphCase
    private let renderedActions: [String: String]

    package init(finiteGraphCase: FiniteGraphCase) {
        self.finiteGraphCase = finiteGraphCase
        self.renderedActions = Dictionary(
            uniqueKeysWithValues: finiteGraphCase.renderedActions.map {
                (
                    tlaInvocationLocationIdentity(
                        action: $0.sourceName,
                        arguments: $0.arguments.map(\.description)
                    ),
                    $0.renderedName
                )
            })
    }

    package func parse(contentsOf url: URL) throws -> TLCGraphEventStream {
        try parse(Data(contentsOf: url, options: .alwaysMapped))
    }

    package func parse(_ data: Data) throws -> TLCGraphEventStream {
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]), data.last == 10 else {
            throw TLCGraphEventError.invalidFooter("stream must be UTF-8 without BOM and LF-terminated")
        }
        var runID: UUID?
        var initialStates: Set<String> = []
        var transitions: Set<TLCGraphTransition> = []
        var representatives: [String: TLCGraphState] = [:]
        var counts: [String: Int] = [:]
        var footer: [String: Any]?
        var bodyHash = CryptoKit.SHA256()
        let newline = Data([10])
        var offset = data.startIndex
        var recordCount = 0

        while let separator = data.range(of: newline, in: offset..<data.endIndex) {
            try autoreleasepool {
                let index = recordCount
                let line = index + 1
                let lineData = data.subdata(in: offset..<separator.lowerBound)
                guard String(data: lineData, encoding: .utf8) != nil else {
                    throw TLCGraphEventError.invalidUTF8
                }
                let object = try decodeJSONObject(lineData, line: line)
                try validateCommon(object, line: line, expectedSequence: index, runID: &runID)
                guard footer == nil else { throw TLCGraphEventError.invalidRecord(line: line, reason: "record after footer") }
                let type = try string(object, "type", line)
                switch type {
                case "header":
                    guard index == 0 else { throw TLCGraphEventError.invalidRecord(line: line, reason: "header is not first") }
                    try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId"], line)
                    guard try string(object, "callback", line) == "writer.header" else {
                        throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid header callback")
                    }
                case "initial":
                    try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "state"], line)
                    guard try string(object, "callback", line) == "writeState.initial" else {
                        throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid initial callback")
                    }
                    let state = try parseState(try dictionary(object, "state", line), line: line)
                    initialStates.insert(try registerRepresentative(state, in: &representatives, line: line))
                case "transition":
                    try exactKeys(object, [
                        "schema", "version", "type", "callback", "seq", "runId", "caseId", "source",
                        "target", "action", "resolvedActions", "stateFlags", "visualization", "predicateLocation", "reachable"
                    ], line)
                    let callback = try string(object, "callback", line)
                    guard callback == "writeState.action" || callback == "writeState.actionPredicate",
                          try string(object, "visualization", line) == "none"
                    else { throw TLCGraphEventError.invalidRecord(line: line, reason: "unsupported transition transport") }
                    let action = try dictionary(object, "action", line)
                    try exactKeys(action, ["name", "location", "named"], line)
                    _ = try string(action, "name", line)
                    _ = try string(action, "location", line)
                    _ = try bool(action, "named", line)
                    let resolvedActions = try array(object, "resolvedActions", line).map { raw -> String in
                        guard let resolved = raw as? [String: Any] else {
                            throw TLCGraphEventError.invalidRecord(line: line, reason: "resolved action")
                        }
                        try exactKeys(resolved, ["name", "location", "named"], line)
                        let name = try string(resolved, "name", line)
                        let location = try string(resolved, "location", line)
                        guard try bool(resolved, "named", line), !name.isEmpty else {
                            throw TLCGraphEventError.invalidRecord(line: line, reason: "unnamed action")
                        }
                        if callback == "writeState.actionPredicate",
                           !location.hasPrefix("<\(name)("), !location.hasPrefix("<\(name) line ") {
                            throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid excluded predicate transition")
                        }
                        return try resolvedAction(name: name, location: location, line: line)
                    }
                    guard !resolvedActions.isEmpty, Set(resolvedActions).count == resolvedActions.count else {
                        throw TLCGraphEventError.invalidRecord(line: line, reason: "empty or duplicate resolved actions")
                    }
                    let flags = try dictionary(object, "stateFlags", line)
                    try exactKeys(flags, ["raw", "seen", "notInModel"], line)
                    let rawFlags = try int(flags, "raw", line)
                    let notInModel = try bool(flags, "notInModel", line)
                    let source = try parseState(try dictionary(object, "source", line), line: line)
                    let target = try parseState(try dictionary(object, "target", line), line: line)
                    let seen = try bool(flags, "seen", line)
                    if callback == "writeState.actionPredicate" {
                        guard try string(object, "reachable", line) == "excluded",
                              rawFlags == 2, !seen, notInModel,
                              let predicateLocation = object["predicateLocation"] as? String,
                              predicateLocation.hasPrefix("line "), predicateLocation.contains(" of module ")
                        else { throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid excluded predicate transition") }
                        _ = try canonicalState(source)
                        if source.bindings != target.bindings {
                            _ = try canonicalState(target)
                        }
                    } else {
                        guard try string(object, "reachable", line) == "reachable",
                              object["predicateLocation"] is NSNull,
                              !notInModel
                        else { throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid reachable transition") }
                        let sourceFingerprint = try validateReference(source, in: representatives, line: line)
                        let targetFingerprint: String
                        if seen {
                            targetFingerprint = try validateReference(target, in: representatives, line: line)
                        } else {
                            targetFingerprint = try registerRepresentative(target, in: &representatives, line: line)
                        }
                        for resolvedAction in resolvedActions {
                            transitions.insert(TLCGraphTransition(
                                source: sourceFingerprint, target: targetFingerprint, action: resolvedAction
                            ))
                        }
                    }
                case "unsupported":
                    try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "reason"], line)
                    guard try string(object, "callback", line) == "writeState.visualization",
                          try string(object, "reason", line) == "callback has no Action identity: STUTTERING"
                    else {
                        throw TLCGraphEventError.unsupportedCallback(try string(object, "callback", line))
                    }
                case "footer":
                    try exactKeys(object, [
                        "schema", "version", "type", "callback", "seq", "runId", "caseId", "status",
                        "counts", "lastBodySeq", "bodySha256"
                    ], line)
                    footer = object
                default:
                    throw TLCGraphEventError.invalidRecord(line: line, reason: "unknown record type")
                }
                if type != "footer" {
                    counts[type, default: 0] += 1
                    bodyHash.update(data: lineData)
                    bodyHash.update(data: newline)
                }
            }
            recordCount += 1
            offset = separator.upperBound
        }

        guard let footer else { throw TLCGraphEventError.missingFooter }
        guard try string(footer, "status", recordCount) == "closed" else { throw TLCGraphEventError.invalidFooter("not closed") }
        guard try int(footer, "lastBodySeq", recordCount) == recordCount - 2 else {
            throw TLCGraphEventError.invalidFooter("last body sequence")
        }
        let digest = bodyHash.finalize().map { String(format: "%02x", $0) }.joined()
        guard try string(footer, "bodySha256", recordCount) == digest else { throw TLCGraphEventError.invalidFooter("body digest") }
        let footerCounts = try dictionary(footer, "counts", recordCount)
        for (type, count) in counts {
            guard try int(footerCounts, type, recordCount) == count else {
                throw TLCGraphEventError.invalidFooter("count for \(type)")
            }
        }
        guard counts["header"] == 1, footerCounts.count == counts.count else { throw TLCGraphEventError.invalidFooter("counts") }
        guard let runID else { throw TLCGraphEventError.invalidRecord(line: 1, reason: "missing run ID") }
        return TLCGraphEventStream(
            runID: runID, caseID: finiteGraphCase.id, states: representatives,
            initialStates: initialStates, transitions: transitions)
    }

    package func makeGraphRun(
        _ stream: TLCGraphEventStream,
        outcome: TLCExecutionOutcome
    ) throws -> GraphRun {
        let canonicalStatesByFingerprint = try stream.states.mapValues(canonicalState)
        func canonicalRepresentative(_ fingerprint: String) throws -> CanonicalState {
            guard let state = canonicalStatesByFingerprint[fingerprint] else {
                throw TLCGraphEventError.invalidRecord(line: 0, reason: "unmapped fingerprint")
            }
            return state
        }
        let initialStates = try stream.initialStates.map(canonicalRepresentative)
        var edges = Set<CanonicalEdge>()
        edges.reserveCapacity(stream.transitions.count)
        for transition in stream.transitions {
            edges.insert(CanonicalEdge(
                source: try canonicalRepresentative(transition.source).key,
                action: transition.action,
                target: try canonicalRepresentative(transition.target).key
            ))
        }
        let graph = try CanonicalGraph(
            initialStates: initialStates,
            states: canonicalStatesByFingerprint.values,
            edges: edges
        )
        return try GraphRun(
            isComplete: outcome == .completed,
            graph: graph,
            observableActions: graph.observedActions,
            outcome: graphOutcome(outcome)
        )
    }

    private func graphOutcome(_ outcome: TLCExecutionOutcome) -> GraphRunOutcome {
        switch outcome {
        case .completed:
            return .noViolation
        case .assumptionViolation:
            return .executionError("TLC assumption violation")
        case .deadlock:
            return .executionError("TLC deadlock violation")
        case .safetyViolation:
            return .invariantViolation("TLC safety property violation")
        case .livenessViolation:
            return .executionError("TLC liveness violation during finite graph exploration")
        case .temporalTautology:
            return .executionError("TLC proved temporal tautology before graph exploration")
        case .assertionViolation:
            return .executionError("TLC assertion violation")
        case .failed(let exitStatus):
            return .executionError("TLC execution failed with exit status \(exitStatus)")
        }
    }

    private func validateCommon(_ object: [String: Any], line: Int, expectedSequence: Int, runID: inout UUID?) throws {
        guard try string(object, "schema", line) == "swifttla.tlc.graph-events", try int(object, "version", line) == 3 else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "schema")
        }
        guard try int(object, "seq", line) == expectedSequence else { throw TLCGraphEventError.invalidRecord(line: line, reason: "sequence gap") }
        guard try string(object, "caseId", line) == finiteGraphCase.id else { throw TLCGraphEventError.invalidRecord(line: line, reason: "case ID") }
        guard let parsed = UUID(uuidString: try string(object, "runId", line)) else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "run ID")
        }
        guard runID == nil || runID == parsed else { throw TLCGraphEventError.invalidRecord(line: line, reason: "run ID changed") }
        runID = parsed
    }

    private func parseState(_ value: [String: Any], line: Int) throws -> TLCGraphState {
        try exactKeys(value, ["fingerprint", "level", "bindings"], line)
        let bindings = try array(value, "bindings", line).enumerated().map { index, item -> TLCBinding in
            guard let object = item as? [String: Any] else { throw TLCGraphEventError.invalidRecord(line: line, reason: "binding") }
            try exactKeys(object, ["ordinal", "name", "tla"], line)
            let text = try string(object, "tla", line)
            guard try int(object, "ordinal", line) == index else { throw TLCGraphEventError.invalidRecord(line: line, reason: "binding ordinal") }
            return TLCBinding(
                name: try string(object, "name", line),
                tla: text
            )
        }
        guard Set(bindings.map(\.name)).count == bindings.count else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "duplicate binding")
        }
        _ = try int(value, "level", line)
        return TLCGraphState(fingerprint: try string(value, "fingerprint", line), bindings: bindings)
    }

    private func registerRepresentative(
        _ state: TLCGraphState, in representatives: inout [String: TLCGraphState], line: Int
    ) throws -> String {
        if let existing = representatives[state.fingerprint] {
            if existing.bindings == state.bindings { return existing.fingerprint }
            guard try canonicalState(existing) == canonicalState(state) else {
                throw TLCGraphEventError.invalidRecord(line: line, reason: "fingerprint binding mismatch")
            }
            return existing.fingerprint
        }
        representatives[state.fingerprint] = state
        return state.fingerprint
    }

    private func validateReference(
        _ state: TLCGraphState, in representatives: [String: TLCGraphState], line: Int
    ) throws -> String {
        guard let representative = representatives[state.fingerprint] else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "seen fingerprint without representative")
        }
        if representative.bindings == state.bindings { return representative.fingerprint }
        let representativeState = try canonicalState(representative)
        let alias = try canonicalState(state)
        if representativeState == alias {
            return representative.fingerprint
        }
        guard finiteGraphCase.symmetryGroup.isEmpty == false else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "fingerprint binding mismatch")
        }
        guard try finiteGraphCase.symmetryGroup.contains(where: { permutation in
            try permutation.apply(alias) == representativeState
        }) else {
            throw TLCGraphEventError.invalidRecord(
                line: line, reason: "fingerprint binding outside declared symmetry orbit")
        }
        return representative.fingerprint
    }

    private func canonicalState(_ state: TLCGraphState) throws -> CanonicalState {
        var bindings: [String: CanonicalValue] = [:]
        for binding in state.bindings {
            guard bindings[binding.name] == nil else {
                throw TLCGraphEventError.invalidRecord(line: 0, reason: "duplicate binding")
            }
            let value = try TLCValueParser.parse(binding.tla)
            bindings[binding.name] = value
        }
        return CanonicalState(bindings: bindings)
    }

    private func resolvedAction(name: String, location: String, line: Int) throws -> String {
        guard !renderedActions.isEmpty else { return name }
        let directIdentity = tlaInvocationLocationIdentity(action: name, arguments: [])
        if let directName = renderedActions[directIdentity] { return directName }
        let identity = try actionLocationIdentity(name: name, location: location, line: line)
        guard let wrapper = renderedActions[identity] else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "undeclared invocation identity")
        }
        return wrapper
    }

    private func actionLocationIdentity(name: String, location: String, line: Int) throws -> String {
        let prefix = "<\(name)("
        guard location.hasPrefix(prefix),
              let suffix = location.range(of: ") line ", options: .backwards),
              suffix.lowerBound >= location.index(location.startIndex, offsetBy: prefix.count) else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid action location")
        }
        let argumentsStart = location.index(location.startIndex, offsetBy: prefix.count)
        let arguments = String(location[argumentsStart..<suffix.lowerBound])
        do {
            return tlaInvocationLocationIdentity(
                action: name, arguments: try TLCValueParser.components(arguments))
        } catch {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid action location")
        }
    }

}

enum TLCValueParser {
    static func parse(_ text: String) throws -> CanonicalValue {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TLCGraphEventError.unsupportedValue(text) }
        if value == "TRUE" { return .boolean(true) }
        if value == "FALSE" { return .boolean(false) }
        if let integer = Int(value) { return .integer(integer) }
        if value.first == "\"", value.last == "\"" {
            if let string = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) {
                return .string(string)
            }
            throw TLCGraphEventError.unsupportedValue(text)
        }
        if value.hasPrefix("<<"), value.hasSuffix(">>") {
            return .tuple(try components(String(value.dropFirst(2).dropLast(2))).map(parse))
        }
        if value.hasPrefix("{"), value.hasSuffix("}") {
            return .set(try components(String(value.dropFirst().dropLast())).map(parse))
        }
        if value.hasPrefix("["), value.hasSuffix("]") {
            let fields = try components(String(value.dropFirst().dropLast())).map { field -> (String, CanonicalValue) in
                guard let separator = field.range(of: "|->") else {
                    throw TLCGraphEventError.unsupportedValue(text)
                }
                let name = String(field[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rhs = String(field[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { throw TLCGraphEventError.unsupportedValue(text) }
                return (name, try parse(rhs))
            }
            guard Set(fields.map(\.0)).count == fields.count else { throw TLCGraphEventError.unsupportedValue(text) }
            return .record(Dictionary(uniqueKeysWithValues: fields))
        }
        if value.hasPrefix("("), value.hasSuffix(")"), value.contains(":>") {
            let entries = try splitTopLevel(String(value.dropFirst().dropLast()), separator: "@@").map { entry -> CanonicalFunctionEntry in
                let pair = try splitTopLevel(entry, separator: ":>")
                guard pair.count == 2 else { throw TLCGraphEventError.unsupportedValue(text) }
                return CanonicalFunctionEntry(key: try parse(pair[0]), value: try parse(pair[1]))
            }
            guard Set(entries.map(\.key)).count == entries.count else { throw TLCGraphEventError.unsupportedValue(text) }
            return try .function(entries)
        }
        guard value.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
            throw TLCGraphEventError.unsupportedValue(text)
        }
        return .constant(value)
    }

    static func components(_ text: String) throws -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : try splitTopLevel(trimmed, separator: ",")
    }

    private static func splitTopLevel(_ text: String, separator: String) throws -> [String] {
        var parts: [String] = []
        var start = text.startIndex
        var index = text.startIndex
        var depth = 0
        var quoted = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if quoted {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { quoted = false }
            } else if character == "\"" {
                quoted = true
            } else if text[index...].hasPrefix("<<") {
                depth += 1
                index = text.index(index, offsetBy: 2)
                continue
            } else if text[index...].hasPrefix(">>") {
                depth -= 1
                guard depth >= 0 else { throw TLCGraphEventError.unsupportedValue(text) }
                index = text.index(index, offsetBy: 2)
                continue
            } else if "{[(".contains(character) {
                depth += 1
            } else if "}])".contains(character) {
                depth -= 1
                guard depth >= 0 else { throw TLCGraphEventError.unsupportedValue(text) }
            } else if depth == 0, text[index...].hasPrefix(separator) {
                parts.append(String(text[start..<index]).trimmingCharacters(in: .whitespaces))
                index = text.index(index, offsetBy: separator.count)
                start = index
                continue
            }
            index = text.index(after: index)
        }
        guard !quoted, depth == 0 else { throw TLCGraphEventError.unsupportedValue(text) }
        let last = String(text[start...]).trimmingCharacters(in: .whitespaces)
        guard !last.isEmpty else { throw TLCGraphEventError.unsupportedValue(text) }
        parts.append(last)
        return parts
    }
}

func decodeJSONObject(_ data: Data, line: Int) throws -> [String: Any] {
    var scanner = JSONDuplicateKeyScanner(data: data)
    do {
        try scanner.validate()
    } catch TLCGraphEventError.duplicateKey(_, let key) {
        throw TLCGraphEventError.duplicateKey(line: line, key: key)
    } catch {
        throw TLCGraphEventError.malformedJSON(line: line)
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TLCGraphEventError.malformedJSON(line: line) }
    return object
}

private func exactKeys(_ object: [String: Any], _ expected: Set<String>, _ line: Int) throws {
    guard Set(object.keys) == expected else { throw TLCGraphEventError.invalidRecord(line: line, reason: "record fields") }
}

private func string(_ object: [String: Any], _ key: String, _ line: Int) throws -> String {
    guard let value = object[key] as? String else { throw TLCGraphEventError.invalidRecord(line: line, reason: key) }
    return value
}

private func int(_ object: [String: Any], _ key: String, _ line: Int) throws -> Int {
    guard let value = object[key] as? NSNumber,
          CFGetTypeID(value) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(value),
          let integer = Int(value.stringValue)
    else { throw TLCGraphEventError.invalidRecord(line: line, reason: key) }
    return integer
}

private func bool(_ object: [String: Any], _ key: String, _ line: Int) throws -> Bool {
    guard let value = object[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
        throw TLCGraphEventError.invalidRecord(line: line, reason: key)
    }
    return value.boolValue
}

private func dictionary(_ object: [String: Any], _ key: String, _ line: Int) throws -> [String: Any] {
    guard let value = object[key] as? [String: Any] else { throw TLCGraphEventError.invalidRecord(line: line, reason: key) }
    return value
}

private func array(_ object: [String: Any], _ key: String, _ line: Int) throws -> [Any] {
    guard let value = object[key] as? [Any] else { throw TLCGraphEventError.invalidRecord(line: line, reason: key) }
    return value
}

private struct JSONDuplicateKeyScanner {
    let bytes: [UInt8]
    var index = 0

    init(data: Data) { bytes = Array(data) }

    mutating func validate() throws { try value(); skip(); guard index == bytes.count else { throw TLCGraphEventError.malformedJSON(line: 0) } }
    private mutating func value() throws {
        skip(); guard index < bytes.count else { throw TLCGraphEventError.malformedJSON(line: 0) }
        switch bytes[index] {
        case 123: try object()
        case 91: try list()
        case 34: _ = try consumeString()
        default: while index < bytes.count, ![44, 93, 125, 32, 9, 10, 13].contains(bytes[index]) { index += 1 }
        }
    }
    private mutating func object() throws {
        index += 1; skip(); var keys = Set<String>(); if consume(125) { return }
        while true {
            let key = try text(); guard keys.insert(key).inserted else { throw TLCGraphEventError.duplicateKey(line: 0, key: key) }
            skip(); guard consume(58) else { throw TLCGraphEventError.malformedJSON(line: 0) }; try value(); skip()
            if consume(125) { return }; guard consume(44) else { throw TLCGraphEventError.malformedJSON(line: 0) }; skip()
        }
    }
    private mutating func list() throws {
        index += 1; skip(); if consume(93) { return }
        while true {
            try value()
            skip()
            if consume(93) { return }
            guard consume(44) else { throw TLCGraphEventError.malformedJSON(line: 0) }
            skip()
        }
    }
    private mutating func text() throws -> String {
        let range = try consumeString()
        let body = bytes[(range.lowerBound + 1)..<(range.upperBound - 1)]
        if body.allSatisfy({ $0 >= 0x20 && $0 < 0x80 && $0 != 0x5c }) {
            return String(decoding: body, as: UTF8.self)
        }
        guard let value = try JSONSerialization.jsonObject(
            with: Data(bytes[range]), options: .fragmentsAllowed) as? String else {
            throw TLCGraphEventError.malformedJSON(line: 0)
        }
        return value
    }

    /// Only object keys need decoding here. Foundation validates and decodes the complete record.
    private mutating func consumeString() throws -> Range<Int> {
        let start = index
        guard consume(34) else { throw TLCGraphEventError.malformedJSON(line: 0) }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { return start..<index }
            if byte == 92 { index += 1 }
        }
        throw TLCGraphEventError.malformedJSON(line: 0)
    }
    private mutating func consume(_ byte: UInt8) -> Bool { guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true }
    private mutating func skip() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
}
