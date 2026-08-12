import CoreFoundation
import Foundation

public enum TLCGraphEventErrorV1: Error, Equatable, Sendable {
    case invalidUTF8
    case malformedJSON(line: Int)
    case duplicateKey(line: Int, key: String)
    case invalidRecord(line: Int, reason: String)
    case provenanceMismatch(String)
    case missingFooter
    case invalidFooter(String)
    case unsupportedCallback(String)
    case unsupportedValue(String)
    case incompleteExecution(String)
}

public struct TLCBindingV1: Equatable, Sendable {
    public let ordinal: Int
    public let name: String
    public let tla: String
    public let tlaSHA256: String
}

public struct TLCGraphStateV1: Equatable, Sendable {
    public let fingerprint: String
    public let level: Int
    public let bindings: [TLCBindingV1]
}

public struct TLCGraphTransitionV1: Equatable, Sendable {
    public let source: TLCGraphStateV1
    public let target: TLCGraphStateV1
    public let action: String
    public let seen: Bool
}

public struct TLCGraphEventStreamV1: Equatable, Sendable {
    public let runID: UUID
    public let caseID: String
    public let fingerprintRepresentatives: [String: TLCGraphStateV1]
    public let initialStates: [TLCGraphStateV1]
    public let transitions: [TLCGraphTransitionV1]
}

public struct TLCGraphEventParserV1: Sendable {
    private let expectedPin: TLCReferencePinV1
    private let expectedCaseID: String
    private let expectedCase: CoreConformanceCaseV1

    public init(expectedCase: CoreConformanceCaseV1) {
        self.expectedPin = expectedCase.pin
        self.expectedCaseID = expectedCase.id
        self.expectedCase = expectedCase
    }

    public func parse(_ data: Data) throws -> TLCGraphEventStreamV1 {
        guard String(data: data, encoding: .utf8) != nil else { throw TLCGraphEventErrorV1.invalidUTF8 }
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]), data.last == 10 else {
            throw TLCGraphEventErrorV1.invalidFooter("stream must be UTF-8 without BOM and LF-terminated")
        }
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        guard lines.last?.isEmpty == true else { throw TLCGraphEventErrorV1.invalidFooter("missing final LF") }
        let records = lines.dropLast()
        guard !records.isEmpty else { throw TLCGraphEventErrorV1.missingFooter }

        var runID: UUID?
        var initialStates: [TLCGraphStateV1] = []
        var transitions: [TLCGraphTransitionV1] = []
        var representatives: [String: TLCGraphStateV1] = [:]
        var counts: [String: Int] = [:]
        var footer: [String: Any]?
        var body = Data()

        for (index, bytes) in records.enumerated() {
            let line = index + 1
            let lineData = Data(bytes)
            let object = try decodeObject(lineData, line: line)
            try validateCommon(object, line: line, expectedSequence: index, runID: &runID)
            guard footer == nil else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "record after footer") }
            let type = try string(object, "type", line)
            switch type {
            case "header":
                guard index == 0 else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "header is not first") }
                try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "provenance"], line)
                guard try string(object, "callback", line) == "writer.header" else {
                    throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "invalid header callback")
                }
                try validateProvenance(try dictionary(object, "provenance", line))
            case "initial":
                try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "state"], line)
                guard try string(object, "callback", line) == "writeState.initial" else {
                    throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "invalid initial callback")
                }
                let state = try parseState(try dictionary(object, "state", line), line: line)
                try registerRepresentative(state, in: &representatives, line: line)
                initialStates.append(state)
            case "transition":
                try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "source", "target", "action", "stateFlags", "visualization", "predicateLocation", "reachable"], line)
                guard try string(object, "callback", line) == "writeState.action",
                      try string(object, "reachable", line) == "reachable",
                      try string(object, "visualization", line) == "none"
                else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "unsupported transition transport") }
                let action = try dictionary(object, "action", line)
                try exactKeys(action, ["name", "location", "named"], line)
                let actionName = try string(action, "name", line)
                _ = try string(action, "location", line)
                guard try bool(action, "named", line), !actionName.isEmpty else {
                    throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "unnamed action")
                }
                let flags = try dictionary(object, "stateFlags", line)
                try exactKeys(flags, ["raw", "seen", "notInModel"], line)
                _ = try int(flags, "raw", line)
                _ = try bool(flags, "notInModel", line)
                let source = try parseState(try dictionary(object, "source", line), line: line)
                let target = try parseState(try dictionary(object, "target", line), line: line)
                let seen = try bool(flags, "seen", line)
                if seen {
                    guard representatives[target.fingerprint] != nil else {
                        throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "seen fingerprint without representative")
                    }
                } else {
                    try registerRepresentative(target, in: &representatives, line: line)
                }
                transitions.append(TLCGraphTransitionV1(
                    source: source,
                    target: target,
                    action: actionName,
                    seen: seen
                ))
            case "unsupported":
                try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "reason"], line)
                guard try string(object, "callback", line) == "writeState.visualization",
                      try string(object, "reason", line) == "callback has no Action identity: STUTTERING"
                else {
                    throw TLCGraphEventErrorV1.unsupportedCallback(try string(object, "callback", line))
                }
            case "footer":
                try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "status", "counts", "lastBodySeq", "bodySha256"], line)
                footer = object
            default:
                throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "unknown record type")
            }
            if type != "footer" {
                counts[type, default: 0] += 1
                body.append(lineData)
                body.append(10)
            }
        }

        guard let footer else { throw TLCGraphEventErrorV1.missingFooter }
        guard try string(footer, "status", records.count) == "closed" else { throw TLCGraphEventErrorV1.invalidFooter("not closed") }
        guard try int(footer, "lastBodySeq", records.count) == records.count - 2 else { throw TLCGraphEventErrorV1.invalidFooter("last body sequence") }
        guard try string(footer, "bodySha256", records.count) == SHA256V1.hex(body) else { throw TLCGraphEventErrorV1.invalidFooter("body digest") }
        let footerCounts = try dictionary(footer, "counts", records.count)
        for (type, count) in counts {
            guard try int(footerCounts, type, records.count) == count else {
                throw TLCGraphEventErrorV1.invalidFooter("count for \(type)")
            }
        }
        guard counts["header"] == 1, footerCounts.count == counts.count else { throw TLCGraphEventErrorV1.invalidFooter("counts") }
        guard let runID else { throw TLCGraphEventErrorV1.invalidRecord(line: 1, reason: "missing run ID") }
        func normalized(_ state: TLCGraphStateV1) throws -> TLCGraphStateV1 {
            guard let representative = representatives[state.fingerprint] else {
                throw TLCGraphEventErrorV1.invalidRecord(line: 0, reason: "unmapped fingerprint")
            }
            return representative
        }
        return TLCGraphEventStreamV1(
            runID: runID, caseID: expectedCaseID,
            fingerprintRepresentatives: representatives,
            initialStates: try initialStates.map(normalized),
            transitions: try transitions.map {
                TLCGraphTransitionV1(source: try normalized($0.source), target: try normalized($0.target), action: $0.action, seen: $0.seen)
            })
    }

    public func parseCanonicalRun(_ data: Data, result: TLCProcessResultV1) throws -> CanonicalRunV1 {
        let stream = try parse(data)
        let initialStates = try stream.initialStates.map(canonicalState)
        let transitionStates = try stream.transitions.flatMap { transition in
            [try canonicalState(transition.source), try canonicalState(transition.target)]
        }
        var uniqueStates: [CanonicalStateKeyV1: CanonicalStateV1] = [:]
        for state in initialStates + transitionStates {
            uniqueStates[state.key] = state
        }
        let edges = try stream.transitions.map { transition in
            CanonicalEdgeV1(
                source: try canonicalState(transition.source).key,
                action: transition.action,
                target: try canonicalState(transition.target).key
            )
        }
        let graph = try CanonicalGraphV1(
            initialStates: initialStates,
            states: Array(uniqueStates.values),
            edges: edges
        )
        return try CanonicalRunV1(
            graph: graph,
            observableActions: Set(stream.transitions.map(\.action)),
            outcome: canonicalOutcome(result)
        )
    }

    private func canonicalOutcome(_ result: TLCProcessResultV1) -> CanonicalOutcomeV1 {
        if result.reportedExhaustiveCompletion { return .exhaustiveSuccess }
        if result.isViolation {
            let message = (result.stdout + "\n" + result.stderr)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: isInvariantViolationDiagnostic) ?? "TLC reported a violation"
            return message == "TLC reported a violation"
                ? .executionError("TLC reported a violation without an invariant diagnostic")
                : .invariantViolation(message)
        }
        return .executionError("TLC did not report exhaustive completion (exit \(result.status))")
    }

    private func isInvariantViolationDiagnostic(_ line: String) -> Bool {
        line.hasPrefix("Error: Invariant ") && line.hasSuffix(" is violated.")
    }

    private func validateCommon(_ object: [String: Any], line: Int, expectedSequence: Int, runID: inout UUID?) throws {
        guard try string(object, "schema", line) == "swifttla.tlc.graph-events", try int(object, "version", line) == 1 else {
            throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "schema")
        }
        guard try int(object, "seq", line) == expectedSequence else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "sequence gap") }
        guard try string(object, "caseId", line) == expectedCaseID else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "case ID") }
        guard let parsed = UUID(uuidString: try string(object, "runId", line)) else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "run ID") }
        guard runID == nil || runID == parsed else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "run ID changed") }
        runID = parsed
    }

    private func validateProvenance(_ value: [String: Any]) throws {
        try exactKeys(value, [
            "tlcTag", "tlcCommit", "tlcJarSha256", "javaDistribution", "javaVersion", "javaArchiveSha256",
            "bridgeClass", "bridgeSourceSha256", "bridgeBinarySha256", "moduleSha256", "cfgSha256",
            "arguments", "argumentsSha256", "workers", "fingerprintPolynomial", "deadlock", "os", "architecture", "environment"
        ], 1)
        let expected: [String: String] = [
            "tlcTag": expectedPin.tag, "tlcCommit": expectedPin.commit, "tlcJarSha256": expectedPin.jarSHA256,
            "javaDistribution": expectedPin.javaDistribution, "javaVersion": expectedPin.javaVersion,
            "javaArchiveSha256": expectedPin.javaArchiveSHA256, "bridgeClass": expectedPin.bridgeClass,
            "bridgeSourceSha256": expectedPin.bridgeSourceSHA256, "bridgeBinarySha256": expectedPin.bridgeBinarySHA256
        ]
        for (key, expectedValue) in expected {
            guard try string(value, key, 1) == expectedValue else {
                throw TLCGraphEventErrorV1.provenanceMismatch(key)
            }
        }
        guard try string(value, "moduleSha256", 1) == expectedCase.moduleSHA256,
              try string(value, "cfgSha256", 1) == expectedCase.cfgSHA256,
              try strings(value, "arguments", 1) == expectedCase.arguments,
              try string(value, "argumentsSha256", 1) == expectedCase.argumentsSHA256,
              try int(value, "workers", 1) == expectedCase.workers,
              try int(value, "fingerprintPolynomial", 1) == expectedCase.fingerprintPolynomial,
              try bool(value, "deadlock", 1) == expectedCase.deadlock,
              try string(value, "os", 1) == expectedCase.operatingSystem,
              try string(value, "architecture", 1) == expectedCase.architecture,
              try stringDictionary(value, "environment", 1) == expectedCase.environment
        else { throw TLCGraphEventErrorV1.provenanceMismatch("case provenance") }
    }

    private func parseState(_ value: [String: Any], line: Int) throws -> TLCGraphStateV1 {
        try exactKeys(value, ["fingerprint", "level", "bindings"], line)
        let bindings = try array(value, "bindings", line).enumerated().map { index, item -> TLCBindingV1 in
            guard let object = item as? [String: Any] else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "binding") }
            try exactKeys(object, ["ordinal", "name", "tla", "tlaSha256"], line)
            let text = try string(object, "tla", line)
            guard try string(object, "tlaSha256", line) == SHA256V1.hex(Data(text.utf8)) else {
                throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "binding digest")
            }
            guard try int(object, "ordinal", line) == index else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "binding ordinal") }
            return TLCBindingV1(ordinal: index, name: try string(object, "name", line), tla: text, tlaSHA256: try string(object, "tlaSha256", line))
        }
        guard Set(bindings.map(\.name)).count == bindings.count else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "duplicate binding") }
        return TLCGraphStateV1(fingerprint: try string(value, "fingerprint", line), level: try int(value, "level", line), bindings: bindings)
    }

    private func registerRepresentative(
        _ state: TLCGraphStateV1, in representatives: inout [String: TLCGraphStateV1], line: Int
    ) throws {
        if let existing = representatives[state.fingerprint], existing != state {
            throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "ambiguous fingerprint representative")
        }
        representatives[state.fingerprint] = state
    }

    private func canonicalState(_ state: TLCGraphStateV1) throws -> CanonicalStateV1 {
        var bindings: [String: CanonicalValueV1] = [:]
        for binding in state.bindings {
            guard bindings[binding.name] == nil else {
                throw TLCGraphEventErrorV1.invalidRecord(line: 0, reason: "duplicate binding")
            }
            bindings[binding.name] = try TLCValueParserV1.parse(binding.tla)
        }
        return CanonicalStateV1(bindings: bindings)
    }
}

enum TLCValueParserV1 {
    static func parse(_ text: String) throws -> CanonicalValueV1 {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
        if value == "TRUE" { return .boolean(true) }
        if value == "FALSE" { return .boolean(false) }
        if let integer = Int(value) { return .integer(integer) }
        if value.first == "\"", value.last == "\"" {
            let wrapped = Data("[\(value)]".utf8)
            if let object = try? JSONSerialization.jsonObject(with: wrapped),
               let strings = object as? [String], let string = strings.first {
                return .string(string)
            }
            throw TLCGraphEventErrorV1.unsupportedValue(text)
        }
        if value.hasPrefix("<<"), value.hasSuffix(">>") {
            return .tuple(try components(String(value.dropFirst(2).dropLast(2))).map(parse))
        }
        if value.hasPrefix("{"), value.hasSuffix("}") {
            return .set(try components(String(value.dropFirst().dropLast())).map(parse))
        }
        if value.hasPrefix("["), value.hasSuffix("]") {
            let fields = try components(String(value.dropFirst().dropLast())).map { field -> (String, CanonicalValueV1) in
                guard let separator = field.range(of: "|->") else {
                    throw TLCGraphEventErrorV1.unsupportedValue(text)
                }
                let name = String(field[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rhs = String(field[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
                return (name, try parse(rhs))
            }
            guard Set(fields.map(\.0)).count == fields.count else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
            return .record(Dictionary(uniqueKeysWithValues: fields))
        }
        if value.hasPrefix("("), value.hasSuffix(")"), value.contains(":>") {
            let entries = try splitTopLevel(String(value.dropFirst().dropLast()), separator: "@@").map { entry -> CanonicalFunctionEntryV1 in
                let pair = try splitTopLevel(entry, separator: ":>")
                guard pair.count == 2 else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
                return CanonicalFunctionEntryV1(key: try parse(pair[0]), value: try parse(pair[1]))
            }
            guard Set(entries.map(\.key)).count == entries.count else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
            return .function(entries)
        }
        guard value.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
            throw TLCGraphEventErrorV1.unsupportedValue(text)
        }
        return .constant(value)
    }

    private static func components(_ text: String) throws -> [String] {
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
                guard depth >= 0 else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
                index = text.index(index, offsetBy: 2)
                continue
            } else if "{[(".contains(character) {
                depth += 1
            } else if "}])".contains(character) {
                depth -= 1
                guard depth >= 0 else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
            } else if depth == 0, text[index...].hasPrefix(separator) {
                parts.append(String(text[start..<index]).trimmingCharacters(in: .whitespaces))
                index = text.index(index, offsetBy: separator.count)
                start = index
                continue
            }
            index = text.index(after: index)
        }
        guard !quoted, depth == 0 else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
        let last = String(text[start...]).trimmingCharacters(in: .whitespaces)
        guard !last.isEmpty else { throw TLCGraphEventErrorV1.unsupportedValue(text) }
        parts.append(last)
        return parts
    }
}

private func decodeObject(_ data: Data, line: Int) throws -> [String: Any] {
    var scanner = JSONDuplicateKeyScannerV1(data: data)
    do { try scanner.validate() }
    catch let error as TLCGraphEventErrorV1 { throw error }
    catch { throw TLCGraphEventErrorV1.malformedJSON(line: line) }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TLCGraphEventErrorV1.malformedJSON(line: line) }
    return object
}

private func exactKeys(_ object: [String: Any], _ expected: Set<String>, _ line: Int) throws {
    guard Set(object.keys) == expected else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: "record fields") }
}

private func string(_ object: [String: Any], _ key: String, _ line: Int) throws -> String {
    guard let value = object[key] as? String else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: key) }
    return value
}

private func int(_ object: [String: Any], _ key: String, _ line: Int) throws -> Int {
    guard let value = object[key] as? NSNumber,
          CFGetTypeID(value) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(value),
          let integer = Int(exactly: value.int64Value)
    else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: key) }
    return integer
}

private func bool(_ object: [String: Any], _ key: String, _ line: Int) throws -> Bool {
    guard let value = object[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
        throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: key)
    }
    return value.boolValue
}

private func dictionary(_ object: [String: Any], _ key: String, _ line: Int) throws -> [String: Any] {
    guard let value = object[key] as? [String: Any] else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: key) }
    return value
}

private func array(_ object: [String: Any], _ key: String, _ line: Int) throws -> [Any] {
    guard let value = object[key] as? [Any] else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: key) }
    return value
}

private func strings(_ object: [String: Any], _ key: String, _ line: Int) throws -> [String] {
    guard let values = object[key] as? [Any], values.allSatisfy({ $0 is String }) else {
        throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: key)
    }
    return values.compactMap { $0 as? String }
}

private func stringDictionary(_ object: [String: Any], _ key: String, _ line: Int) throws -> [String: String] {
    guard let values = object[key] as? [String: Any] else {
        throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: key)
    }
    var strings: [String: String] = [:]
    for (name, value) in values {
        guard let text = value as? String else { throw TLCGraphEventErrorV1.invalidRecord(line: line, reason: key) }
        strings[name] = text
    }
    return strings
}

private struct JSONDuplicateKeyScannerV1 {
    let bytes: [UInt8]
    var index = 0

    init(data: Data) { bytes = Array(data) }

    mutating func validate() throws { try value(); skip(); guard index == bytes.count else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) } }
    private mutating func value() throws {
        skip(); guard index < bytes.count else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
        switch bytes[index] {
        case 123: try object()
        case 91: try list()
        case 34: _ = try text()
        default: while index < bytes.count, ![44, 93, 125, 32, 9, 10, 13].contains(bytes[index]) { index += 1 }
        }
    }
    private mutating func object() throws {
        index += 1; skip(); var keys = Set<String>(); if consume(125) { return }
        while true {
            let key = try text(); guard keys.insert(key).inserted else { throw TLCGraphEventErrorV1.duplicateKey(line: 0, key: key) }
            skip(); guard consume(58) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }; try value(); skip()
            if consume(125) { return }; guard consume(44) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }; skip()
        }
    }
    private mutating func list() throws {
        index += 1; skip(); if consume(93) { return }
        while true { try value(); skip(); if consume(93) { return }; guard consume(44) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }; skip() }
    }
    private mutating func text() throws -> String {
        guard consume(34) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
        var value = String()
        var plain = Data()
        func appendPlain() throws {
            guard let text = String(data: plain, encoding: .utf8) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
            value += text
            plain.removeAll(keepingCapacity: true)
        }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { try appendPlain(); return value }
            guard byte == 92 else { plain.append(byte); continue }
            try appendPlain()
            guard index < bytes.count else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
            let escaped = bytes[index]
            index += 1
            switch escaped {
            case 34: value.append("\"")
            case 92: value.append("\\")
            case 47: value.append("/")
            case 98: value.append("\u{08}")
            case 102: value.append("\u{0C}")
            case 110: value.append("\n")
            case 114: value.append("\r")
            case 116: value.append("\t")
            case 117: try appendUnicodeEscape(to: &value)
            default: throw TLCGraphEventErrorV1.malformedJSON(line: 0)
            }
        }
        throw TLCGraphEventErrorV1.malformedJSON(line: 0)
    }
    private mutating func appendUnicodeEscape(to value: inout String) throws {
        let first = try unicodeUnit()
        if (0xD800...0xDBFF).contains(first) {
            guard consume(92), consume(117) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
            let second = try unicodeUnit()
            guard (0xDC00...0xDFFF).contains(second) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
            let scalar = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00
            guard let unicode = UnicodeScalar(scalar) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
            value.unicodeScalars.append(unicode)
        } else {
            guard !(0xDC00...0xDFFF).contains(first), let unicode = UnicodeScalar(first) else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
            value.unicodeScalars.append(unicode)
        }
    }
    private mutating func unicodeUnit() throws -> UInt32 {
        guard index + 4 <= bytes.count,
              let unit = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16)
        else { throw TLCGraphEventErrorV1.malformedJSON(line: 0) }
        index += 4
        return unit
    }
    private mutating func consume(_ byte: UInt8) -> Bool { guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true }
    private mutating func skip() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
}
