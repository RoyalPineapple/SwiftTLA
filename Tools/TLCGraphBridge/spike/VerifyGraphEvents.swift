import CryptoKit
import Foundation

enum JSONValue {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Int)
    case bool(Bool)
    case null
}

private struct JSONParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = Array(data) }

    mutating func parse() throws -> JSONValue {
        skipWhitespace()
        let result = try value()
        skipWhitespace()
        guard index == bytes.count else { throw error("trailing JSON bytes") }
        return result
    }

    private mutating func value() throws -> JSONValue {
        guard index < bytes.count else { throw error("unexpected end") }
        switch bytes[index] {
        case 123: return .object(try object())
        case 91: return .array(try array())
        case 34: return .string(try string())
        case 45, 48...57: return .number(try number())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default: throw error("invalid JSON token")
        }
    }

    private mutating func object() throws -> [String: JSONValue] {
        try byte(123)
        skipWhitespace()
        var result: [String: JSONValue] = [:]
        if consume(125) { return result }
        while true {
            skipWhitespace()
            let key = try string()
            guard result[key] == nil else { throw error("duplicate key: \(key)") }
            skipWhitespace()
            try byte(58)
            skipWhitespace()
            result[key] = try value()
            skipWhitespace()
            if consume(125) { return result }
            try byte(44)
        }
    }

    private mutating func array() throws -> [JSONValue] {
        try byte(91)
        skipWhitespace()
        var result: [JSONValue] = []
        if consume(93) { return result }
        while true {
            result.append(try value())
            skipWhitespace()
            if consume(93) { return result }
            try byte(44)
            skipWhitespace()
        }
    }

    private mutating func string() throws -> String {
        try byte(34)
        var result = String.UnicodeScalarView()
        while index < bytes.count {
            let current = bytes[index]
            index += 1
            if current == 34 { return String(result) }
            if current == 92 {
                guard index < bytes.count else { throw error("unterminated escape") }
                let escaped = bytes[index]
                index += 1
                switch escaped {
                case 34: result.append("\"")
                case 92: result.append("\\")
                case 47: result.append("/")
                case 98: result.append("\u{08}")
                case 102: result.append("\u{0C}")
                case 110: result.append("\n")
                case 114: result.append("\r")
                case 116: result.append("\t")
                case 117:
                    guard index + 4 <= bytes.count,
                          let scalar = UInt32(
                            String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16
                          ).flatMap(UnicodeScalar.init) else { throw error("invalid unicode escape") }
                    result.append(scalar)
                    index += 4
                default: throw error("invalid escape")
                }
            } else if current < 32 {
                throw error("unescaped control character")
            } else {
                result.append(UnicodeScalar(current))
            }
        }
        throw error("unterminated string")
    }

    private mutating func number() throws -> Int {
        let start = index
        _ = consume(45)
        guard index < bytes.count else { throw error("truncated number") }
        if consume(48) {
            guard index == bytes.count || !(48...57).contains(bytes[index]) else { throw error("leading zero") }
        } else {
            guard index < bytes.count, (49...57).contains(bytes[index]) else { throw error("invalid number") }
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }
        guard let value = Int(String(decoding: bytes[start..<index], as: UTF8.self)) else { throw error("number range") }
        return value
    }

    private mutating func literal(_ text: String) throws {
        let expected = Array(text.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else { throw error("invalid literal") }
        index += expected.count
    }

    private mutating func byte(_ expected: UInt8) throws {
        guard consume(expected) else { throw error("expected JSON byte") }
    }

    private mutating func consume(_ expected: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == expected else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "TLCGraphEvent", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("BridgeSpikeVerdict: KILL — \(message)\n".utf8))
    exit(2)
}

private func string(_ record: [String: JSONValue], _ key: String) -> String? {
    guard case let .string(value) = record[key] else { return nil }
    return value
}

private func number(_ record: [String: JSONValue], _ key: String) -> Int? {
    guard case let .number(value) = record[key] else { return nil }
    return value
}

private func object(_ record: [String: JSONValue], _ key: String) -> [String: JSONValue]? {
    guard case let .object(value) = record[key] else { return nil }
    return value
}

private func array(_ record: [String: JSONValue], _ key: String) -> [JSONValue]? {
    guard case let .array(value) = record[key] else { return nil }
    return value
}

private func bool(_ record: [String: JSONValue], _ key: String) -> Bool? {
    guard case let .bool(value) = record[key] else { return nil }
    return value
}

private func exactKeys(_ record: [String: JSONValue], _ expected: Set<String>, _ context: String) {
    guard Set(record.keys) == expected else { fail("\(context) has unknown, missing, or duplicate-schema fields") }
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func sha256File(_ url: URL) -> String {
    guard let data = try? Data(contentsOf: url) else { fail("cannot read locked input: \(url.path)") }
    return sha256(data)
}

private func isUUID(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil
}

private let bridgeRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func compiledBridgeDigest() -> String {
    sha256File(bridgeRoot.appendingPathComponent("build/classes/org/swifttla/conformance/LosslessStateWriter.class"))
}

private let common = Set(["schema", "version", "type", "callback", "seq", "runId", "caseId"])
private let headerKeys = common.union(["provenance"])
private let initialKeys = common.union(["state"])
private let transitionKeys = common.union(["source", "target", "action", "stateFlags", "visualization", "predicateLocation", "reachable"])
private let unsupportedKeys = common.union(["reason"])
private let footerKeys = common.union(["status", "counts", "lastBodySeq", "bodySha256"])
private let provenanceKeys: Set<String> = [
    "tlcTag", "tlcCommit", "tlcJarSha256", "javaDistribution", "javaVersion", "javaArchiveSha256",
    "bridgeClass", "bridgeSourceSha256", "bridgeBinarySha256", "moduleSha256", "cfgSha256",
    "arguments", "argumentsSha256", "workers", "fingerprintPolynomial", "deadlock", "os", "architecture", "environment"
]
private let stateKeys: Set<String> = ["fingerprint", "level", "bindings"]
private let bindingKeys: Set<String> = ["ordinal", "name", "tla", "tlaSha256"]
private let actionKeys: Set<String> = ["name", "location", "named"]
private let flagsKeys: Set<String> = ["raw", "seen", "notInModel"]

private let fingerprints = [
    "0": "1139230162306704134", "1": "3166707766929968548", "2": "5167075194509819458",
    "3": "7172017208952492256", "4": "11473952881614133646", "5": "13476625506548414252"
]
private let levels = ["0": Set([1]), "1": Set([1]), "2": Set([2]), "3": Set([3, 4]), "4": Set([4]), "5": Set([5])]
private let fixedBindings = [
    (0, "record", "[kind |-> \"fixture\"]"), (1, "text", "\"bridge\""),
    (2, "tuple", "<<1, TRUE>>"), (3, "set", "{1, 2}"), (4, "function", "<<1, 2>>"),
    (6, "boolean", "TRUE"), (7, "integer", "7")
]

struct StateRef: Hashable {
    let x: String
    let level: Int
}

private func stateRef(_ value: JSONValue?, _ context: String) -> StateRef {
    guard case let .object(state) = value else { fail("\(context) is not a state") }
    exactKeys(state, stateKeys, context)
    guard let fingerprint = string(state, "fingerprint"),
          let level = number(state, "level"),
          let bindings = array(state, "bindings"), bindings.count == 8 else { fail("\(context) has invalid state fields") }

    for binding in bindings {
        guard case let .object(value) = binding else { fail("\(context) binding is not an object") }
        exactKeys(value, bindingKeys, "\(context) binding")
        guard let text = string(value, "tla"), string(value, "tlaSha256") == sha256(Data(text.utf8)) else {
            fail("\(context) binding digest mismatch")
        }
    }

    for (ordinal, name, tla) in fixedBindings {
        let binding = objectAt(bindings, ordinal, context)
        guard number(binding, "ordinal") == ordinal, string(binding, "name") == name, string(binding, "tla") == tla else {
            fail("\(context) has an unexpected binding")
        }
    }

    let x = objectAt(bindings, 5, context)
    guard number(x, "ordinal") == 5, string(x, "name") == "x", let xValue = string(x, "tla"),
          let expectedFingerprint = fingerprints[xValue], levels[xValue]?.contains(level) == true, expectedFingerprint == fingerprint else {
        fail("\(context) is not one of the locked fixture states")
    }
    return StateRef(x: xValue, level: level)
}

private func objectAt(_ values: [JSONValue], _ index: Int, _ context: String) -> [String: JSONValue] {
    guard index < values.count, case let .object(value) = values[index] else { fail("\(context) binding shape is invalid") }
    return value
}

struct Edge: Hashable {
    let source: StateRef
    let action: String
    let target: StateRef
    let rawFlags: Int
}

private let expectedEdges: [Edge: Int] = [
    Edge(source: StateRef(x: "0", level: 1), action: "ToMidA", target: StateRef(x: "2", level: 2), rawFlags: 0): 1,
    Edge(source: StateRef(x: "0", level: 1), action: "ToMidB", target: StateRef(x: "2", level: 2), rawFlags: 1): 1,
    Edge(source: StateRef(x: "1", level: 1), action: "ToMidA", target: StateRef(x: "2", level: 2), rawFlags: 1): 1,
    Edge(source: StateRef(x: "1", level: 1), action: "ToMidB", target: StateRef(x: "2", level: 2), rawFlags: 1): 1,
    Edge(source: StateRef(x: "2", level: 2), action: "Repeat", target: StateRef(x: "3", level: 3), rawFlags: 0): 1,
    Edge(source: StateRef(x: "2", level: 2), action: "Repeat", target: StateRef(x: "3", level: 3), rawFlags: 1): 1,
    Edge(source: StateRef(x: "3", level: 3), action: "SelfLoop", target: StateRef(x: "3", level: 4), rawFlags: 1): 1,
    Edge(source: StateRef(x: "3", level: 3), action: "ToTerminal", target: StateRef(x: "4", level: 4), rawFlags: 0): 1,
    Edge(source: StateRef(x: "4", level: 4), action: "TerminalStep", target: StateRef(x: "5", level: 5), rawFlags: 0): 1
]

private func validateProvenance(_ value: JSONValue?) {
    guard case let .object(provenance) = value else { fail("header provenance is not an object") }
    exactKeys(provenance, provenanceKeys, "header provenance")
    let expectedArguments = ["-workers", "1", "-fp", "1", "-seed", "1", "-deadlock"]
    let source = bridgeRoot.appendingPathComponent("src/org/swifttla/conformance/LosslessStateWriter.java")
    let module = bridgeRoot.appendingPathComponent("spike/BridgeGraph.tla")
    let cfg = bridgeRoot.appendingPathComponent("spike/BridgeGraph.cfg")
    guard string(provenance, "tlcTag") == "v1.8.0",
          string(provenance, "tlcCommit") == "0894c3407f4717fec7cc18bde3bf3c857fa47333",
          string(provenance, "tlcJarSha256") == "ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f",
          string(provenance, "javaDistribution") == "Eclipse Temurin",
          string(provenance, "javaVersion") == "17.0.19+10",
          string(provenance, "javaArchiveSha256") == "8fa1eff40bb637a33613b2ccb8b12c70dc3661cc22cf8e784943715769a05336",
          string(provenance, "bridgeClass") == "org.swifttla.conformance.LosslessStateWriter",
          string(provenance, "bridgeSourceSha256") == sha256File(source),
          string(provenance, "bridgeBinarySha256") == compiledBridgeDigest(),
          string(provenance, "moduleSha256") == sha256File(module),
          string(provenance, "cfgSha256") == sha256File(cfg),
          let arguments = array(provenance, "arguments"),
          arguments.compactMap({ if case let .string(value) = $0 { value } else { nil } }) == expectedArguments,
          string(provenance, "argumentsSha256") == sha256(Data("[\"-workers\",\"1\",\"-fp\",\"1\",\"-seed\",\"1\",\"-deadlock\"]".utf8)),
          number(provenance, "workers") == 1, number(provenance, "fingerprintPolynomial") == 1,
          bool(provenance, "deadlock") == false, string(provenance, "os") == "macos", string(provenance, "architecture") == "arm64",
          let environment = object(provenance, "environment"), environment.isEmpty else {
        fail("header provenance does not match the immutable lock")
    }
}

private func validateTLCCompletion(_ logPath: String?) {
    guard let logPath else { return }
    guard let log = try? String(contentsOfFile: logPath, encoding: .utf8),
          log.contains("Finished computing initial states: 2 distinct states generated"),
          log.contains("Model checking completed. No error has been found."),
          log.contains("11 states generated, 6 distinct states found, 0 states left on queue.") else {
        fail("TLC completion/count evidence is missing or mismatched")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let streamPath = arguments.first else { fail("missing JSONL path") }
let expectsAdversarial = arguments.contains("--expect-adversarial")
let logIndex = arguments.firstIndex(of: "--tlc-log")
let tlcLog = logIndex.flatMap { index in index + 1 < arguments.count ? arguments[index + 1] : nil }
if logIndex != nil && tlcLog == nil { fail("--tlc-log requires a path") }
if expectsAdversarial && tlcLog == nil { fail("adversarial verification requires TLC completion evidence") }

let stream = URL(fileURLWithPath: streamPath)
guard let data = try? Data(contentsOf: stream) else { fail("cannot read JSONL path") }
guard String(data: data, encoding: .utf8) != nil else { fail("invalid UTF-8 event stream") }
guard data.last == 10 else { fail("missing final LF") }
let splitLines = data.split(separator: 10, omittingEmptySubsequences: false)
guard splitLines.last?.isEmpty == true else { fail("trailing bytes") }
let lines = splitLines.dropLast()
guard lines.count >= 2 else { fail("missing body or footer") }

var records: [[String: JSONValue]] = []
for (index, raw) in lines.enumerated() {
    do {
        var parser = JSONParser(Data(raw))
        guard case let .object(record) = try parser.parse() else { fail("line \(index + 1) is not an object") }
        records.append(record)
    } catch {
        fail("line \(index + 1): \(error.localizedDescription)")
    }
}

var counts: [String: Int] = [:]
var initials: [StateRef: Int] = [:]
var edges: [Edge: Int] = [:]
var observedStates = Set<StateRef>()
var footerSeen = false

for (index, record) in records.enumerated() {
    guard string(record, "schema") == "swifttla.tlc.graph-events", number(record, "version") == 1,
          number(record, "seq") == index, string(record, "caseId") == "adversarial-core-graph-v1",
          let runID = string(record, "runId"), isUUID(runID), let type = string(record, "type") else {
        fail("line \(index + 1) violates common schema")
    }
    switch type {
    case "header":
        exactKeys(record, headerKeys, "header")
        guard index == 0, string(record, "callback") == "writer.header" else { fail("header position or callback is invalid") }
        validateProvenance(record["provenance"])
        counts[type, default: 0] += 1
    case "initial":
        exactKeys(record, initialKeys, "initial")
        guard string(record, "callback") == "writeState.initial" else { fail("invalid initial callback") }
        let state = stateRef(record["state"], "initial")
        initials[state, default: 0] += 1
        observedStates.insert(state)
        counts[type, default: 0] += 1
    case "transition":
        exactKeys(record, transitionKeys, "transition")
        guard string(record, "callback") == "writeState.action",
              let action = object(record, "action"),
              let flags = object(record, "stateFlags") else {
            fail("transition relation fields are invalid")
        }
        exactKeys(action, actionKeys, "transition action")
        exactKeys(flags, flagsKeys, "transition flags")
        guard let name = string(action, "name"), !name.isEmpty, string(action, "location")?.isEmpty == false, bool(action, "named") == true,
              let raw = number(flags, "raw"), raw >= 0, raw <= 65535, bool(flags, "seen") == ((raw & 1) == 1), bool(flags, "notInModel") == false,
              string(record, "visualization") == "none", case .null? = record["predicateLocation"], string(record, "reachable") == "reachable" else {
            fail("transition metadata is invalid")
        }
        let source = stateRef(record["source"], "transition source")
        let target = stateRef(record["target"], "transition target")
        observedStates.insert(source)
        observedStates.insert(target)
        edges[Edge(source: source, action: name, target: target, rawFlags: raw), default: 0] += 1
        counts[type, default: 0] += 1
    case "unsupported":
        exactKeys(record, unsupportedKeys, "unsupported")
        fail("unsupported callback: \(string(record, "callback") ?? "unknown")")
    case "footer":
        exactKeys(record, footerKeys, "footer")
        guard index == records.count - 1,
              string(record, "callback") == "writer.close",
              string(record, "status") == "closed",
              number(record, "lastBodySeq") == index - 1,
              let digest = string(record, "bodySha256"),
              case let .object(footerCounts)? = record["counts"] else {
            fail("footer is invalid")
        }
        let body = lines.dropLast().reduce(into: Data()) { bytes, line in bytes.append(contentsOf: line); bytes.append(10) }
        guard sha256(body) == digest else { fail("footer digest mismatch") }
        let expectedCounts: [String: Int] = ["header": 1, "initial": 2, "transition": 9]
        exactKeys(footerCounts, Set(expectedCounts.keys), "footer counts")
        for (name, expected) in expectedCounts where number(footerCounts, name) != expected { fail("footer count mismatch for \(name)") }
        footerSeen = true
    default:
        fail("unknown record type")
    }
}

guard footerSeen, counts == ["header": 1, "initial": 2, "transition": 9],
      initials == [StateRef(x: "0", level: 1): 1, StateRef(x: "1", level: 1): 1],
      observedStates == Set([
        StateRef(x: "0", level: 1), StateRef(x: "1", level: 1), StateRef(x: "2", level: 2),
        StateRef(x: "3", level: 3), StateRef(x: "3", level: 4), StateRef(x: "4", level: 4),
        StateRef(x: "5", level: 5)
      ]),
      edges == expectedEdges else {
    fail("complete adversarial initial-state or transition multiset does not match the locked fixture")
}
validateTLCCompletion(tlcLog)
print("BridgeSpikeVerdict: PASS")
