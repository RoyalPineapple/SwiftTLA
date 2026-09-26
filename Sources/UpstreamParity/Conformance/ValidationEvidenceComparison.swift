import CryptoKit
import Foundation
import SwiftTLA

package struct ValidationEvidenceComparisonReport: Codable, Sendable {
    package let schema: String
    package let caseID: String
    package let result: String
    package let graphCompared: Bool
    package let difference: String?
    package let properties: [String: ValidationVerdict]
    package let deadlock: ValidationVerdict?
}

package enum ValidationEvidenceComparisonError: Error, Equatable {
    case invalidEvidence(String)
    case sortingFailed(Int32)
}

/// Exact, bounded-memory comparison. State keys are sorted once and assigned
/// common ranks; full edges are then compared as sorted rank/action/rank records.
package enum ValidationEvidenceComparison {
    package static func compareTLCGraphs(
        caseID: String, generated: URL, reference: URL,
        actions: [RenderedAction], in directory: URL
    ) throws -> String? {
        let generatedRoot = directory.appendingPathComponent("generated-graph-spool")
        let referenceRoot = directory.appendingPathComponent("reference-graph-spool")
        try FileManager.default.createDirectory(at: generatedRoot, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: referenceRoot, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: generatedRoot)
            try? FileManager.default.removeItem(at: referenceRoot)
        }
        let generatedGraph = try readTLC(generated, caseID: caseID, actions: actions, in: generatedRoot)
        let referenceGraph = try readTLC(reference, caseID: caseID, actions: actions, in: referenceRoot)
        let generatedStates = try sorted(generatedGraph.states, in: generatedRoot)
        let referenceStates = try sorted(referenceGraph.states, in: referenceRoot)
        var generatedRanks: [String: Int] = [:]
        var referenceRanks: [String: Int] = [:]
        generatedRanks.reserveCapacity(generatedGraph.stateCount)
        referenceRanks.reserveCapacity(referenceGraph.stateCount)
        var left = try ValidationLineReader(generatedStates)
        var right = try ValidationLineReader(referenceStates)
        defer { left.close(); right.close() }
        var rank = 0
        var previousKey: Data?
        while let generatedLine = try left.next() {
            guard let referenceLine = try right.next(),
                  let generatedField = generatedLine.lastIndex(of: 9),
                  let referenceField = referenceLine.lastIndex(of: 9),
                  generatedLine[..<generatedField] == referenceLine[..<referenceField],
                  previousKey != generatedLine[..<generatedField] else {
                return "complete state set"
            }
            let generatedFP = String(decoding: generatedLine[generatedLine.index(after: generatedField)...], as: UTF8.self)
            let referenceFP = String(decoding: referenceLine[referenceLine.index(after: referenceField)...], as: UTF8.self)
            guard generatedRanks.updateValue(rank, forKey: generatedFP) == nil,
                  referenceRanks.updateValue(rank, forKey: referenceFP) == nil else {
                return "duplicate TLC fingerprint"
            }
            previousKey = Data(generatedLine[..<generatedField])
            rank += 1
        }
        guard try right.next() == nil, rank == generatedGraph.stateCount,
              rank == referenceGraph.stateCount else { return "complete state set" }
        let generatedInitial = try rankInitials(generatedGraph.initial, ranks: generatedRanks, in: generatedRoot)
        let referenceInitial = try rankInitials(referenceGraph.initial, ranks: referenceRanks, in: referenceRoot)
        if try firstDifference(generatedInitial, referenceInitial) != nil { return "initial state set" }
        let generatedEdges = try rankEdges(generatedGraph.edges, ranks: generatedRanks, in: generatedRoot)
        let referenceEdges = try rankEdges(referenceGraph.edges, ranks: referenceRanks, in: referenceRoot)
        if try firstDifference(generatedEdges, referenceEdges) != nil { return "complete labeled edge set" }
        return nil
    }

    package static func compare(
        caseID: String, native: URL, oracle: URL, actions: [RenderedAction], to directory: URL
    ) throws -> ValidationEvidenceComparisonReport {
        let decoder = JSONDecoder()
        let swift = try decoder.decode(NativeValidationReport.self,
            from: Data(contentsOf: native.appendingPathComponent("report.json")))
        let tlc = try decoder.decode(GeneratedTLCOracleReport.self,
            from: Data(contentsOf: oracle.appendingPathComponent("oracle.json")))
        guard swift.schema == "swifttla.native-validation-report",
              tlc.schema == "swifttla.generated-tlc-oracle",
              tlc.caseID == caseID, swift.scenario == tlc.scenario else {
            throw ValidationEvidenceComparisonError.invalidEvidence("report identity")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var difference: String?
        if swift.properties != tlc.properties || swift.deadlock != tlc.deadlock {
            difference = "selected property or deadlock verdict"
        }
        let compareGraph = swift.graphComplete && tlc.graphComplete
        if difference == nil {
            let swiftRoot = directory.appendingPathComponent("swift")
            let tlcRoot = directory.appendingPathComponent("tlc")
            try FileManager.default.createDirectory(at: swiftRoot, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: tlcRoot, withIntermediateDirectories: false)
            defer {
                try? FileManager.default.removeItem(at: swiftRoot)
                try? FileManager.default.removeItem(at: tlcRoot)
            }
            let swiftGraph = try readNative(native.appendingPathComponent("machine.jsonl"),
                expectedComplete: swift.graphComplete, actions: actions, in: swiftRoot)
            let tlcGraph = try readTLC(oracle.appendingPathComponent("tlc-graph/graph-events.jsonl"),
                caseID: caseID, actions: actions, in: tlcRoot)
            try verifyTLCProcess(oracle.appendingPathComponent("tlc-graph/tlc-process.json"),
                expectedComplete: tlc.graphComplete)
            if compareGraph {
                difference = try Self.compareGraph(swiftGraph: swiftGraph, tlcGraph: tlcGraph,
                    swiftRoot: swiftRoot, tlcRoot: tlcRoot)
            }
        }
        let report = ValidationEvidenceComparisonReport(
            schema: "swifttla.validation-evidence-comparison", caseID: caseID,
            result: difference == nil ? "exact" : "different", graphCompared: compareGraph,
            difference: difference, properties: swift.properties, deadlock: swift.deadlock)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
        return report
    }

    private static func compareGraph(swiftGraph: Spool, tlcGraph: Spool,
        swiftRoot: URL, tlcRoot: URL) throws -> String? {
        let swiftStates = try sorted(swiftGraph.states, in: swiftRoot)
        let tlcStates = try sorted(tlcGraph.states, in: tlcRoot)
        var swiftRanks = [Int](repeating: -1, count: swiftGraph.stateCount)
        var tlcRanks: [String: Int] = [:]
        tlcRanks.reserveCapacity(tlcGraph.stateCount)
        var left = try ValidationLineReader(swiftStates)
        var right = try ValidationLineReader(tlcStates)
        defer { left.close(); right.close() }
        var rank = 0
        var previousKey: Data?
        while let nativeLine = try left.next() {
            guard let tlcLine = try right.next(),
                  let nativeField = nativeLine.lastIndex(of: 9),
                  let tlcField = tlcLine.lastIndex(of: 9),
                  nativeLine[..<nativeField] == tlcLine[..<tlcField],
                  previousKey != nativeLine[..<nativeField],
                  let nativeID = Int(String(decoding: nativeLine[nativeLine.index(after: nativeField)...], as: UTF8.self)),
                  nativeID >= 0, nativeID < swiftRanks.count, swiftRanks[nativeID] == -1 else {
                return "complete state set"
            }
            let fingerprint = String(decoding: tlcLine[tlcLine.index(after: tlcField)...], as: UTF8.self)
            guard tlcRanks.updateValue(rank, forKey: fingerprint) == nil else {
                return "duplicate TLC fingerprint"
            }
            previousKey = Data(nativeLine[..<nativeField])
            swiftRanks[nativeID] = rank
            rank += 1
        }
        guard try right.next() == nil, rank == swiftGraph.stateCount,
              rank == tlcGraph.stateCount else { return "complete state set" }
        let swiftInitial = try rankInitials(swiftGraph.initial, ranks: swiftRanks, in: swiftRoot)
        let tlcInitial = try rankInitials(tlcGraph.initial, ranks: tlcRanks, in: tlcRoot)
        if try firstDifference(swiftInitial, tlcInitial) != nil { return "initial state set" }
        let swiftEdges = try rankEdges(swiftGraph.edges, ranks: swiftRanks, in: swiftRoot)
        let tlcEdges = try rankEdges(tlcGraph.edges, ranks: tlcRanks, in: tlcRoot)
        if try firstDifference(swiftEdges, tlcEdges) != nil { return "complete labeled edge set" }
        return nil
    }

    private struct Spool {
        let states: URL
        let initial: URL
        let edges: URL
        let stateCount: Int
    }

    private static func readNative(_ url: URL, expectedComplete: Bool,
        actions: [RenderedAction], in directory: URL) throws -> Spool {
        let states = directory.appendingPathComponent("states.raw")
        let initial = directory.appendingPathComponent("initial.raw")
        let edges = directory.appendingPathComponent("edges.raw")
        var stateOut = try ValidationLineWriter(states)
        var initialOut = try ValidationLineWriter(initial)
        var edgeOut = try ValidationLineWriter(edges)
        let actionNames = Dictionary(uniqueKeysWithValues: actions.map { ($0.sourceInvocationName, $0.renderedName) })
        defer { try? stateOut.close(); try? initialOut.close(); try? edgeOut.close() }
        var reader = try ValidationLineReader(url)
        defer { reader.close() }
        var digest = CryptoKit.SHA256()
        var count = 0
        var stateCount = 0
        var edgeCount = 0
        var initialCount = 0
        var sawFooter = false
        while let line = try reader.next() {
            let record = try decodeJSONObject(line, line: count + 1)
            guard let type = record["type"] as? String, !sawFooter else {
                throw ValidationEvidenceComparisonError.invalidEvidence("native record order")
            }
            if type != "complete" {
                digest.update(data: line)
                digest.update(data: Data([10]))
            }
            switch type {
            case "header":
                guard count == 0, record["schema"] as? String == "swifttla.native-validation",
                      record["version"] as? Int == 1 else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native header")
                }
            case "state":
                guard let id = record["id"] as? Int, id == stateCount,
                      let key = record["key"] as? String, validField(key),
                      let isInitial = record["initial"] as? Bool else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native state")
                }
                try stateOut.append("\(key)\t\(id)")
                if isInitial {
                    try initialOut.append(String(id))
                    initialCount += 1
                }
                stateCount += 1
            case "edge":
                guard let source = record["source"] as? Int, source >= 0, source < stateCount,
                      let target = record["target"] as? Int, target >= 0, target < stateCount,
                      let action = record["action"] as? String,
                      let label = actionNames[action] else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native edge")
                }
                try edgeOut.append("\(source)\t\(target)\t\(encodedBytes(label))")
                edgeCount += 1
            case "invariant-failure", "deadlock", "reachability":
                break
            case "complete":
                let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
                let completion = record["completion"] as? String
                guard (expectedComplete && completion == "exhausted")
                        || (!expectedComplete && (completion == "decisive-violation"
                            || completion == "decisive-reachability")),
                      record["bodySha256"] as? String == hash,
                      record["states"] as? Int == stateCount,
                      record["initialStates"] as? Int == initialCount,
                      record["edges"] as? Int == edgeCount else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native completion")
                }
                sawFooter = true
            default:
                throw ValidationEvidenceComparisonError.invalidEvidence("native event type")
            }
            count += 1
        }
        guard sawFooter else { throw ValidationEvidenceComparisonError.invalidEvidence("native footer") }
        try stateOut.close()
        try initialOut.close()
        try edgeOut.close()
        return Spool(states: states, initial: initial, edges: edges, stateCount: stateCount)
    }

    private static func readTLC(_ url: URL, caseID: String, actions: [RenderedAction],
        in directory: URL) throws -> Spool {
        let states = directory.appendingPathComponent("states.raw")
        let initial = directory.appendingPathComponent("initial.raw")
        let edges = directory.appendingPathComponent("edges.raw")
        var stateOut = try ValidationLineWriter(states)
        var initialOut = try ValidationLineWriter(initial)
        var edgeOut = try ValidationLineWriter(edges)
        defer { try? stateOut.close(); try? initialOut.close(); try? edgeOut.close() }
        var reader = try ValidationLineReader(url)
        defer { reader.close() }
        let actionNames = Dictionary(uniqueKeysWithValues: actions.map {
            (tlaInvocationLocationIdentity(action: $0.sourceName,
                arguments: $0.arguments.map(\.description)), $0.renderedName)
        })
        var fingerprints: Set<String> = []
        var digest = CryptoKit.SHA256()
        var counts: [String: Int] = [:]
        var runID: String?
        var sequence = 0
        var sawFooter = false
        while let line = try reader.next() {
            let record = try decodeJSONObject(line, line: sequence + 1)
            guard !sawFooter,
                  record["schema"] as? String == "swifttla.tlc.graph-events",
                  record["version"] as? Int == 3,
                  record["seq"] as? Int == sequence,
                  record["caseId"] as? String == caseID,
                  let currentRun = record["runId"] as? String,
                  UUID(uuidString: currentRun) != nil,
                  runID == nil || runID == currentRun,
                  let type = record["type"] as? String else {
                throw ValidationEvidenceComparisonError.invalidEvidence("TLC event identity")
            }
            runID = currentRun
            if type != "footer" {
                digest.update(data: line)
                digest.update(data: Data([10]))
                counts[type, default: 0] += 1
            }
            switch type {
            case "header":
                guard sequence == 0, record["callback"] as? String == "writer.header" else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("TLC header")
                }
            case "initial":
                guard record["callback"] as? String == "writeState.initial",
                      let state = record["state"] as? [String: Any] else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("TLC initial state")
                }
                let fingerprint = try register(state, known: &fingerprints, output: &stateOut)
                try initialOut.append(fingerprint)
            case "transition":
                guard let source = record["source"] as? [String: Any],
                      let target = record["target"] as? [String: Any],
                      let sourceFP = source["fingerprint"] as? String,
                      let targetFP = target["fingerprint"] as? String,
                      let flags = record["stateFlags"] as? [String: Any],
                      let rawFlags = flags["raw"] as? Int,
                      let seen = flags["seen"] as? Bool,
                      let excluded = flags["notInModel"] as? Bool,
                      let reachable = record["reachable"] as? String,
                      let callback = record["callback"] as? String,
                      record["visualization"] as? String == "none",
                      let rawActions = record["resolvedActions"] as? [[String: Any]] else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("TLC transition")
                }
                if callback == "writeState.actionPredicate" {
                    guard excluded, !seen, rawFlags == 2, reachable == "excluded",
                          record["predicateLocation"] is String else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("TLC excluded transition")
                    }
                } else {
                    guard callback == "writeState.action", !excluded, reachable == "reachable",
                          record["predicateLocation"] is NSNull,
                          fingerprints.contains(sourceFP) else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("TLC reachable transition")
                    }
                    if seen {
                        guard fingerprints.contains(targetFP) else {
                            throw ValidationEvidenceComparisonError.invalidEvidence("TLC unseen target")
                        }
                    } else {
                        _ = try register(target, known: &fingerprints, output: &stateOut)
                    }
                    guard !rawActions.isEmpty else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("TLC missing action")
                    }
                    for action in rawActions {
                        let name = try resolvedAction(action, declared: actionNames)
                        try edgeOut.append("\(sourceFP)\t\(targetFP)\t\(encodedBytes(name))")
                    }
                }
            case "unsupported":
                guard record["callback"] as? String == "writeState.visualization",
                      record["reason"] as? String == "callback has no Action identity: STUTTERING" else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("unsupported TLC callback")
                }
            case "footer":
                let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
                guard record["status"] as? String == "closed",
                      record["lastBodySeq"] as? Int == sequence - 1,
                      record["bodySha256"] as? String == hash,
                      let footerCounts = record["counts"] as? [String: Int],
                      footerCounts == counts, counts["header"] == 1 else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("TLC footer")
                }
                sawFooter = true
            default:
                throw ValidationEvidenceComparisonError.invalidEvidence("TLC event type")
            }
            sequence += 1
        }
        guard sawFooter else { throw ValidationEvidenceComparisonError.invalidEvidence("TLC missing footer") }
        try stateOut.close()
        try initialOut.close()
        try edgeOut.close()
        return Spool(states: states, initial: initial, edges: edges, stateCount: fingerprints.count)
    }

    private static func register(_ state: [String: Any], known: inout Set<String>,
        output: inout ValidationLineWriter) throws -> String {
        guard let fingerprint = state["fingerprint"] as? String,
              UInt64(fingerprint) != nil,
              known.insert(fingerprint).inserted,
              let bindings = state["bindings"] as? [[String: Any]] else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC state identity")
        }
        var values: [String: CanonicalValue] = [:]
        for (ordinal, binding) in bindings.enumerated() {
            guard binding["ordinal"] as? Int == ordinal,
                  let name = binding["name"] as? String,
                  let raw = binding["tla"] as? String,
                  values[name] == nil else {
                throw ValidationEvidenceComparisonError.invalidEvidence("TLC state binding")
            }
            values[name] = try TLCValueParser.parse(raw)
        }
        let key = CanonicalState(bindings: values).key.canonicalEncoding
        guard validField(key) else { throw ValidationEvidenceComparisonError.invalidEvidence("TLC state key") }
        try output.append("\(key)\t\(fingerprint)")
        return fingerprint
    }

    private static func resolvedAction(_ action: [String: Any],
        declared: [String: String]) throws -> String {
        guard action["named"] as? Bool == true,
              let name = action["name"] as? String,
              let location = action["location"] as? String else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC action")
        }
        let direct = tlaInvocationLocationIdentity(action: name, arguments: [])
        if let label = declared[direct] { return label }
        let prefix = "<\(name)("
        guard location.hasPrefix(prefix),
              let suffix = location.range(of: ") line ", options: .backwards) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC action location")
        }
        let arguments = String(location[location.index(location.startIndex, offsetBy: prefix.count)..<suffix.lowerBound])
        let identity = tlaInvocationLocationIdentity(action: name,
            arguments: try TLCValueParser.components(arguments))
        guard let label = declared[identity] else {
            throw ValidationEvidenceComparisonError.invalidEvidence("undeclared TLC action")
        }
        return label
    }

    private static func rankInitials(_ raw: URL, ranks: [Int], in directory: URL) throws -> URL {
        try rewrite(raw, in: directory) { fields in
            guard fields.count == 1, let id = Int(fields[0]), id >= 0, id < ranks.count,
                  ranks[id] >= 0 else { throw ValidationEvidenceComparisonError.invalidEvidence("native initial ID") }
            return String(ranks[id])
        }
    }

    private static func rankInitials(_ raw: URL, ranks: [String: Int], in directory: URL) throws -> URL {
        try rewrite(raw, in: directory) { fields in
            guard fields.count == 1, let rank = ranks[fields[0]] else {
                throw ValidationEvidenceComparisonError.invalidEvidence("TLC initial fingerprint")
            }
            return String(rank)
        }
    }

    private static func rankEdges(_ raw: URL, ranks: [Int], in directory: URL) throws -> URL {
        try rewrite(raw, in: directory) { fields in
            guard fields.count == 3,
                  let source = Int(fields[0]), let target = Int(fields[1]),
                  source >= 0, source < ranks.count, target >= 0, target < ranks.count,
                  ranks[source] >= 0, ranks[target] >= 0 else {
                throw ValidationEvidenceComparisonError.invalidEvidence("native edge ID")
            }
            return "\(ranks[source])\t\(fields[2])\t\(ranks[target])"
        }
    }

    private static func rankEdges(_ raw: URL, ranks: [String: Int], in directory: URL) throws -> URL {
        try rewrite(raw, in: directory) { fields in
            guard fields.count == 3, let source = ranks[fields[0]], let target = ranks[fields[1]] else {
                throw ValidationEvidenceComparisonError.invalidEvidence("TLC edge fingerprint")
            }
            return "\(source)\t\(fields[2])\t\(target)"
        }
    }

    private static func rewrite(_ raw: URL, in directory: URL,
        transform: ([String]) throws -> String) throws -> URL {
        var reader = try ValidationLineReader(raw)
        defer { reader.close() }
        let ranked = directory.appendingPathComponent(raw.lastPathComponent + ".ranked")
        var writer = try ValidationLineWriter(ranked)
        defer { try? writer.close() }
        while let line = try reader.next() {
            let fields = String(decoding: line, as: UTF8.self).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            try writer.append(transform(fields))
        }
        try writer.close()
        return try sorted(ranked, in: directory, unique: true)
    }

    private static func sorted(_ input: URL, in directory: URL, unique: Bool = false) throws -> URL {
        let output = directory.appendingPathComponent(input.lastPathComponent + ".sorted")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sort")
        process.arguments = (unique ? ["-u"] : []) + ["-o", output.path, input.path]
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationEvidenceComparisonError.sortingFailed(process.terminationStatus)
        }
        return output
    }

    private static func firstDifference(_ left: URL, _ right: URL) throws -> String? {
        var lhs = try ValidationLineReader(left)
        var rhs = try ValidationLineReader(right)
        defer { lhs.close(); rhs.close() }
        while true {
            let a = try lhs.next()
            let b = try rhs.next()
            if a != b { return "records differ" }
            if a == nil { return nil }
        }
    }

    private static func validField(_ value: String) -> Bool {
        !value.isEmpty && !value.utf8.contains(9) && !value.utf8.contains(10)
    }

    private static func verifyTLCProcess(_ url: URL, expectedComplete: Bool) throws {
        let data = try Data(contentsOf: url)
        guard let process = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let invocation = process["invocation"] as? [String: Any],
              let status = invocation["exitStatus"] as? Int,
              (expectedComplete ? status == 0 : status != 0) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC process outcome")
        }
    }
}

private struct ValidationLineReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var cursor = 0

    init(_ url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
    mutating func next() throws -> Data? {
        while true {
            if let newline = buffer[cursor...].firstIndex(of: 10) {
                let line = buffer.subdata(in: cursor..<newline)
                cursor = newline + 1
                return line
            }
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty {
                guard cursor == buffer.count else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("unterminated line")
                }
                return nil
            }
            if cursor > 0 {
                buffer.removeSubrange(0..<cursor)
                cursor = 0
            }
            buffer.append(chunk)
        }
    }
    func close() { try? handle.close() }
}

private struct ValidationLineWriter {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ url: URL) throws {
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        buffer.reserveCapacity(1_048_576)
    }
    mutating func append(_ line: String) throws {
        let size = line.utf8.count + 1
        if buffer.count + size > 1_048_576 { try flush() }
        buffer.append(contentsOf: line.utf8)
        buffer.append(10)
    }
    mutating func close() throws {
        try flush()
        try handle.close()
    }
    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
    }
}
