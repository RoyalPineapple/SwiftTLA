import CoreFoundation
import Foundation

package enum TLCGraphEventError: Error, Equatable, Sendable {
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

package struct TLCBinding: Equatable, Sendable {
    package let ordinal: Int
    package let name: String
    package let tla: String
    package let tlaSHA256: String
}

package struct TLCGraphState: Equatable, Sendable {
    package let fingerprint: String
    package let level: Int
    package let bindings: [TLCBinding]
}

package struct TLCGraphTransition: Equatable, Sendable {
    package let source: TLCGraphState
    package let target: TLCGraphState
    package let action: String
    package let seen: Bool
}

package struct TLCGraphEventStream: Equatable, Sendable {
    package let runID: UUID
    package let caseID: String
    package let fingerprintRepresentatives: [String: TLCGraphState]
    package let initialStates: [TLCGraphState]
    package let transitions: [TLCGraphTransition]
}

package struct TLCGraphReader: Sendable {
    private let finiteGraphCase: FiniteGraphCase
    private let invocationWrappers: [String: String]

    package init(finiteGraphCase: FiniteGraphCase) {
        self.finiteGraphCase = finiteGraphCase
        self.invocationWrappers = Dictionary(
            uniqueKeysWithValues: finiteGraphCase.renderedActions.compactMap {
                guard $0.sourceInvocationName != $0.renderedName else { return nil }
                return (
                    tlaInvocationLocationIdentity(
                        action: $0.sourceName,
                        arguments: $0.arguments.map(\.description)
                    ),
                    $0.renderedName
                )
            })
    }

    package func parse(_ data: Data) throws -> TLCGraphEventStream {
        guard String(data: data, encoding: .utf8) != nil else { throw TLCGraphEventError.invalidUTF8 }
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]), data.last == 10 else {
            throw TLCGraphEventError.invalidFooter("stream must be UTF-8 without BOM and LF-terminated")
        }
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        guard lines.last?.isEmpty == true else { throw TLCGraphEventError.invalidFooter("missing final LF") }
        let records = lines.dropLast()
        guard !records.isEmpty else { throw TLCGraphEventError.missingFooter }

        var runID: UUID?
        var initialStates: [TLCGraphState] = []
        var transitions: [TLCGraphTransition] = []
        var representatives: [String: TLCGraphState] = [:]
        var counts: [String: Int] = [:]
        var footer: [String: Any]?
        var body = Data()

        for (index, bytes) in records.enumerated() {
            let line = index + 1
            let lineData = Data(bytes)
            let object = try decodeObject(lineData, line: line)
            try validateCommon(object, line: line, expectedSequence: index, runID: &runID)
            guard footer == nil else { throw TLCGraphEventError.invalidRecord(line: line, reason: "record after footer") }
            let type = try string(object, "type", line)
            switch type {
            case "header":
                guard index == 0 else { throw TLCGraphEventError.invalidRecord(line: line, reason: "header is not first") }
                try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "provenance"], line)
                guard try string(object, "callback", line) == "writer.header" else {
                    throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid header callback")
                }
                try validateProvenance(try dictionary(object, "provenance", line))
            case "initial":
                try exactKeys(object, ["schema", "version", "type", "callback", "seq", "runId", "caseId", "state"], line)
                guard try string(object, "callback", line) == "writeState.initial" else {
                    throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid initial callback")
                }
                let state = try parseState(try dictionary(object, "state", line), line: line)
                try registerRepresentative(state, in: &representatives, line: line)
                initialStates.append(state)
            case "transition":
                try exactKeys(object, [
                    "schema", "version", "type", "callback", "seq", "runId", "caseId", "source",
                    "target", "action", "stateFlags", "visualization", "predicateLocation", "reachable"
                ], line)
                let callback = try string(object, "callback", line)
                guard callback == "writeState.action" || callback == "writeState.actionPredicate",
                      try string(object, "visualization", line) == "none"
                else { throw TLCGraphEventError.invalidRecord(line: line, reason: "unsupported transition transport") }
                let action = try dictionary(object, "action", line)
                try exactKeys(action, ["name", "location", "named"], line)
                let actionName = try string(action, "name", line)
                let actionLocation = try string(action, "location", line)
                guard try bool(action, "named", line), !actionName.isEmpty else {
                    throw TLCGraphEventError.invalidRecord(line: line, reason: "unnamed action")
                }
                let resolvedAction = try resolvedAction(
                    name: actionName, location: actionLocation, line: line)
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
                          predicateLocation.hasPrefix("line "), predicateLocation.contains(" of module "),
                          actionLocation.hasPrefix("<\(actionName)(")
                    else { throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid excluded predicate transition") }
                    _ = source
                    _ = target
                } else {
                    guard try string(object, "reachable", line) == "reachable",
                          object["predicateLocation"] is NSNull,
                          !notInModel
                    else { throw TLCGraphEventError.invalidRecord(line: line, reason: "invalid reachable transition") }
                    try validateReference(source, in: representatives, line: line)
                    if seen {
                        try validateReference(target, in: representatives, line: line)
                    } else {
                        try registerRepresentative(target, in: &representatives, line: line)
                    }
                    transitions.append(TLCGraphTransition(
                        source: source,
                        target: target,
                        action: resolvedAction,
                        seen: seen
                    ))
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
                body.append(lineData)
                body.append(10)
            }
        }

        guard let footer else { throw TLCGraphEventError.missingFooter }
        guard try string(footer, "status", records.count) == "closed" else { throw TLCGraphEventError.invalidFooter("not closed") }
        guard try int(footer, "lastBodySeq", records.count) == records.count - 2 else {
            throw TLCGraphEventError.invalidFooter("last body sequence")
        }
        guard try string(footer, "bodySha256", records.count) == SHA256.hex(body) else { throw TLCGraphEventError.invalidFooter("body digest") }
        let footerCounts = try dictionary(footer, "counts", records.count)
        for (type, count) in counts {
            guard try int(footerCounts, type, records.count) == count else {
                throw TLCGraphEventError.invalidFooter("count for \(type)")
            }
        }
        guard counts["header"] == 1, footerCounts.count == counts.count else { throw TLCGraphEventError.invalidFooter("counts") }
        guard let runID else { throw TLCGraphEventError.invalidRecord(line: 1, reason: "missing run ID") }
        func resolvedState(_ state: TLCGraphState) throws -> TLCGraphState {
            guard let representative = representatives[state.fingerprint] else {
                throw TLCGraphEventError.invalidRecord(line: 0, reason: "unmapped fingerprint")
            }
            return representative
        }
        return TLCGraphEventStream(
            runID: runID, caseID: finiteGraphCase.id,
            fingerprintRepresentatives: representatives,
            initialStates: try initialStates.map(resolvedState),
            transitions: try transitions.map {
                TLCGraphTransition(source: try resolvedState($0.source), target: try resolvedState($0.target), action: $0.action, seen: $0.seen)
            })
    }

    package func readCompletedGraph(_ data: Data, result: TLCProcessResult) throws -> CompletedGraphRun {
        let stream = try parse(data)
        return try makeCompletedGraphRun(stream, result: result)
    }

    package func makeCompletedGraphRun(_ stream: TLCGraphEventStream, result: TLCProcessResult) throws -> CompletedGraphRun {
        var canonicalStatesByFingerprint: [String: CanonicalState] = [:]
        func canonicalRepresentative(_ state: TLCGraphState) throws -> CanonicalState {
            if let existing = canonicalStatesByFingerprint[state.fingerprint] {
                return existing
            }
            let parsed = try canonicalState(state)
            canonicalStatesByFingerprint[state.fingerprint] = parsed
            return parsed
        }
        let initialStates = try stream.initialStates.map(canonicalRepresentative)
        let edges = try stream.transitions.map { transition in
            CanonicalEdge(
                source: try canonicalRepresentative(transition.source).key,
                action: transition.action,
                target: try canonicalRepresentative(transition.target).key
            )
        }
        let graph = try CanonicalGraph(
            initialStates: initialStates,
            states: Array(canonicalStatesByFingerprint.values),
            edges: edges
        )
        return try CompletedGraphRun(
            graph: graph,
            observableActions: Set(stream.transitions.map(\.action)),
            outcome: canonicalOutcome(result)
        )
    }

    private func canonicalOutcome(_ result: TLCProcessResult) -> GraphRunOutcome {
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

    private func validateProvenance(_ value: [String: Any]) throws {
        try exactKeys(value, [
            "tlcTag", "tlcCommit", "tlcJarSha256", "javaDistribution", "javaVersion", "javaArchiveSha256",
            "bridgeClass", "bridgeSourceSha256", "bridgeBinarySha256", "moduleSha256", "cfgSha256",
            "arguments", "argumentsSha256", "os", "architecture", "environment"
        ], 1)
        let expected: [String: String] = [
            "tlcTag": finiteGraphCase.pin.tag, "tlcCommit": finiteGraphCase.pin.commit, "tlcJarSha256": finiteGraphCase.pin.jarSHA256,
            "javaDistribution": finiteGraphCase.pin.javaDistribution, "javaVersion": finiteGraphCase.pin.javaVersion,
            "javaArchiveSha256": finiteGraphCase.pin.javaArchiveSHA256, "bridgeClass": finiteGraphCase.pin.bridgeClass,
            "bridgeSourceSha256": finiteGraphCase.pin.bridgeSourceSHA256, "bridgeBinarySha256": finiteGraphCase.pin.bridgeBinarySHA256
        ]
        for (key, expectedValue) in expected {
            guard try string(value, key, 1) == expectedValue else {
                throw TLCGraphEventError.provenanceMismatch(key)
            }
        }
        guard try string(value, "moduleSha256", 1) == finiteGraphCase.moduleSHA256,
              try string(value, "cfgSha256", 1) == finiteGraphCase.cfgSHA256,
              try strings(value, "arguments", 1) == finiteGraphCase.arguments,
              try string(value, "argumentsSha256", 1) == finiteGraphCase.argumentsSHA256,
              try string(value, "os", 1) == finiteGraphCase.operatingSystem,
              try string(value, "architecture", 1) == finiteGraphCase.architecture,
              try stringDictionary(value, "environment", 1) == finiteGraphCase.environment
        else { throw TLCGraphEventError.provenanceMismatch("case provenance") }
    }

    private func parseState(_ value: [String: Any], line: Int) throws -> TLCGraphState {
        try exactKeys(value, ["fingerprint", "level", "bindings"], line)
        let bindings = try array(value, "bindings", line).enumerated().map { index, item -> TLCBinding in
            guard let object = item as? [String: Any] else { throw TLCGraphEventError.invalidRecord(line: line, reason: "binding") }
            try exactKeys(object, ["ordinal", "name", "tla", "tlaSha256"], line)
            let text = try string(object, "tla", line)
            guard try string(object, "tlaSha256", line) == SHA256.hex(Data(text.utf8)) else {
                throw TLCGraphEventError.invalidRecord(line: line, reason: "binding digest")
            }
            guard try int(object, "ordinal", line) == index else { throw TLCGraphEventError.invalidRecord(line: line, reason: "binding ordinal") }
            return TLCBinding(
                ordinal: index,
                name: try string(object, "name", line),
                tla: text,
                tlaSHA256: try string(object, "tlaSha256", line)
            )
        }
        guard Set(bindings.map(\.name)).count == bindings.count else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "duplicate binding")
        }
        return TLCGraphState(fingerprint: try string(value, "fingerprint", line), level: try int(value, "level", line), bindings: bindings)
    }

    private func registerRepresentative(
        _ state: TLCGraphState, in representatives: inout [String: TLCGraphState], line: Int
    ) throws {
        if let existing = representatives[state.fingerprint] {
            guard try canonicalState(existing) == canonicalState(state) else {
                throw TLCGraphEventError.invalidRecord(line: line, reason: "fingerprint binding mismatch")
            }
            return
        }
        representatives[state.fingerprint] = state
    }

    private func validateReference(
        _ state: TLCGraphState, in representatives: [String: TLCGraphState], line: Int
    ) throws {
        guard let representative = representatives[state.fingerprint] else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "seen fingerprint without representative")
        }
        guard try canonicalState(representative) == canonicalState(state) else {
            throw TLCGraphEventError.invalidRecord(line: line, reason: "fingerprint binding mismatch")
        }
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
        guard !invocationWrappers.isEmpty else { return name }
        let identity = try actionLocationIdentity(name: name, location: location, line: line)
        guard let wrapper = invocationWrappers[identity] else {
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
            let wrapped = Data("[\(value)]".utf8)
            if let object = try? JSONSerialization.jsonObject(with: wrapped),
               let strings = object as? [String], let string = strings.first {
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

private func decodeObject(_ data: Data, line: Int) throws -> [String: Any] {
    var scanner = JSONDuplicateKeyScanner(data: data)
    do {
        try scanner.validate()
    } catch let error as TLCGraphEventError {
        throw error
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
          let integer = Int(exactly: value.int64Value)
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

private func strings(_ object: [String: Any], _ key: String, _ line: Int) throws -> [String] {
    guard let values = object[key] as? [Any], values.allSatisfy({ $0 is String }) else {
        throw TLCGraphEventError.invalidRecord(line: line, reason: key)
    }
    return values.compactMap { $0 as? String }
}

private func stringDictionary(_ object: [String: Any], _ key: String, _ line: Int) throws -> [String: String] {
    guard let values = object[key] as? [String: Any] else {
        throw TLCGraphEventError.invalidRecord(line: line, reason: key)
    }
    var strings: [String: String] = [:]
    for (name, value) in values {
        guard let text = value as? String else { throw TLCGraphEventError.invalidRecord(line: line, reason: key) }
        strings[name] = text
    }
    return strings
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
        case 34: _ = try text()
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
        guard consume(34) else { throw TLCGraphEventError.malformedJSON(line: 0) }
        var value = String()
        var plain = Data()
        func appendPlain() throws {
            guard let text = String(data: plain, encoding: .utf8) else { throw TLCGraphEventError.malformedJSON(line: 0) }
            value += text
            plain.removeAll(keepingCapacity: true)
        }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 34 { try appendPlain(); return value }
            guard byte == 92 else { plain.append(byte); continue }
            try appendPlain()
            guard index < bytes.count else { throw TLCGraphEventError.malformedJSON(line: 0) }
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
            default: throw TLCGraphEventError.malformedJSON(line: 0)
            }
        }
        throw TLCGraphEventError.malformedJSON(line: 0)
    }
    private mutating func appendUnicodeEscape(to value: inout String) throws {
        let first = try unicodeUnit()
        if (0xD800...0xDBFF).contains(first) {
            guard consume(92), consume(117) else { throw TLCGraphEventError.malformedJSON(line: 0) }
            let second = try unicodeUnit()
            guard (0xDC00...0xDFFF).contains(second) else { throw TLCGraphEventError.malformedJSON(line: 0) }
            let scalar = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00
            guard let unicode = UnicodeScalar(scalar) else { throw TLCGraphEventError.malformedJSON(line: 0) }
            value.unicodeScalars.append(unicode)
        } else {
            guard !(0xDC00...0xDFFF).contains(first), let unicode = UnicodeScalar(first) else { throw TLCGraphEventError.malformedJSON(line: 0) }
            value.unicodeScalars.append(unicode)
        }
    }
    private mutating func unicodeUnit() throws -> UInt32 {
        guard index + 4 <= bytes.count,
              let unit = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16)
        else { throw TLCGraphEventError.malformedJSON(line: 0) }
        index += 4
        return unit
    }
    private mutating func consume(_ byte: UInt8) -> Bool { guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true }
    private mutating func skip() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
}
