import CryptoKit
import Dispatch
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
    package let deadlockSelected: Bool
}

package enum ValidationEvidenceComparisonError: Error, Equatable {
    case invalidEvidence(String)
    case sortingFailed(Int32)
    case spoolingFailed(Int32)
}

/// Exact, bounded-memory comparison. State keys are sorted once and assigned
/// common ranks; full edges are then compared as sorted rank/action/rank records.
package enum ValidationEvidenceComparison {
    private static func measured<Result>(_ phase: String, _ body: () throws -> Result) rethrows -> Result {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            fputs("comparison phase \(phase): \(elapsed) s\n", stderr)
        }
        return try body()
    }

    package static func compareTLCGraphs(
        caseID: String, generated: URL, reference: URL,
        actions: [RenderedAction], in directory: URL, spoolExecutable: URL? = nil
    ) throws -> String? {
        let generatedRoot = directory.appendingPathComponent("generated-graph-spool")
        let referenceRoot = directory.appendingPathComponent("reference-graph-spool")
        try FileManager.default.createDirectory(at: generatedRoot, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: referenceRoot, withIntermediateDirectories: false)
        var exact = false
        defer {
            if exact {
                try? FileManager.default.removeItem(at: generatedRoot)
                try? FileManager.default.removeItem(at: referenceRoot)
            }
        }
        let generatedGraph = try spoolTLC(generated, caseID: caseID, actions: actions,
            in: generatedRoot, executable: spoolExecutable, kind: "upstream")
        let referenceGraph = try spoolTLC(reference, caseID: caseID, actions: actions,
            in: referenceRoot, executable: spoolExecutable, kind: "upstream")
        var generatedRanks: [UInt64: Int] = [:]
        var referenceRanks: [UInt64: Int] = [:]
        generatedRanks.reserveCapacity(generatedGraph.stateCount)
        referenceRanks.reserveCapacity(referenceGraph.stateCount)
        let equalStates = try matchStates(
            generatedGraph.states, referenceGraph.states,
            leftRoot: generatedRoot, rightRoot: referenceRoot,
            expectedCount: generatedGraph.stateCount
        ) { generatedID, referenceID, rank in
            guard generatedRanks.updateValue(rank, forKey: generatedID) == nil,
                  referenceRanks.updateValue(rank, forKey: referenceID) == nil else {
                throw ValidationEvidenceComparisonError.invalidEvidence("duplicate TLC fingerprint")
            }
        }
        guard equalStates, generatedGraph.stateCount == referenceGraph.stateCount else {
            return "complete state set"
        }
        let generatedInitial = try rankInitials(generatedGraph.initial, ranks: generatedRanks, in: generatedRoot)
        let referenceInitial = try rankInitials(referenceGraph.initial, ranks: referenceRanks, in: referenceRoot)
        if try firstDifference(generatedInitial, referenceInitial) != nil { return "initial state set" }
        let same = try compareBinaryEdges(generatedGraph.edges, referenceGraph.edges,
            stateCount: generatedGraph.stateCount,
            leftEdgeCount: generatedGraph.edgeCount, rightEdgeCount: referenceGraph.edgeCount,
            leftRank: { try Self.rank($0, in: generatedRanks) },
            rightRank: { try Self.rank($0, in: referenceRanks) })
        if !same { return "complete labeled edge set" }
        exact = true
        return nil
    }

    package static func compare<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, native: URL, oracle: URL,
        actions: [RenderedAction], to directory: URL, spoolExecutable: URL? = nil
    ) throws -> ValidationEvidenceComparisonReport {
        let decoder = JSONDecoder()
        let swift = try decoder.decode(NativeValidationReport.self,
            from: Data(contentsOf: native.appendingPathComponent("report.json")))
        let tlc = try decoder.decode(GeneratedTLCOracleReport.self,
            from: Data(contentsOf: oracle.appendingPathComponent("oracle.json")))
        guard swift.schema == "swifttla.native-validation-report",
              tlc.schema == "swifttla.generated-tlc-oracle",
              tlc.caseID == caseID, swift.scenario == tlc.scenario,
              swift.maximumStates > 0, swift.maximumStates == tlc.maximumStates,
              swift.deadlockSelected == tlc.deadlockSelected else {
            throw ValidationEvidenceComparisonError.invalidEvidence("report identity")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var exact = false
        var spoolDirectories: [URL] = []
        defer {
            if exact {
                for spool in spoolDirectories { try? FileManager.default.removeItem(at: spool) }
            }
        }
        var difference: String?
        if swift.graphComplete != tlc.graphComplete {
            difference = "exploration completion"
        } else if swift.properties != tlc.properties || swift.deadlock != tlc.deadlock {
            difference = "selected property or deadlock verdict"
        }
        let compareGraph = swift.graphComplete && tlc.graphComplete
        if difference == nil {
            let swiftRoot = directory.appendingPathComponent("swift")
            try FileManager.default.createDirectory(at: swiftRoot, withIntermediateDirectories: false)
            spoolDirectories.append(swiftRoot)
            let swiftGraph = try measured("native spool") {
                try spoolNative(native.appendingPathComponent("machine.bin"),
                    caseID: caseID, expectedComplete: swift.graphComplete, actions: actions,
                    in: swiftRoot, executable: spoolExecutable)
            }
            guard swiftGraph.stateCount == swift.states,
                  swiftGraph.initialCount == swift.initialStates,
                  swiftGraph.edgeCount == swift.edges else {
                throw ValidationEvidenceComparisonError.invalidEvidence("native report counts")
            }
            let tlcExitStatus = try verifyTLCProcess(
                oracle.appendingPathComponent("tlc-graph/tlc-process.json"), report: tlc)
            if compareGraph {
                if FileManager.default.fileExists(atPath: oracle.appendingPathComponent("tlc-check").path) {
                    try TLCWitnessVerification.verifyChecked(scenario: scenario, report: tlc,
                        caseID: caseID, oracle: oracle, rendered: scenario.render())
                }
                let tlcRoot = directory.appendingPathComponent("tlc")
                try FileManager.default.createDirectory(at: tlcRoot, withIntermediateDirectories: false)
                spoolDirectories.append(tlcRoot)
                let tlcGraph = try measured("TLC spool") {
                    try spoolTLC(
                        oracle.appendingPathComponent("tlc-graph/graph-events.bin"),
                        caseID: caseID, actions: actions, in: tlcRoot,
                        executable: spoolExecutable, kind: "native")
                }
                difference = try measured("complete graph") {
                    try Self.compareGraph(swiftGraph: swiftGraph, tlcGraph: tlcGraph,
                        swiftRoot: swiftRoot, tlcRoot: tlcRoot)
                }
            } else {
                try TLCWitnessVerification.verifyPartial(scenario: scenario, report: tlc,
                    exitStatus: tlcExitStatus, oracle: oracle, rendered: scenario.render())
            }
        }
        let report = ValidationEvidenceComparisonReport(
            schema: "swifttla.validation-evidence-comparison", caseID: caseID,
            result: difference == nil ? "exact" : "different", graphCompared: compareGraph,
            difference: difference, properties: swift.properties, deadlock: swift.deadlock,
            deadlockSelected: swift.deadlockSelected)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
        exact = difference == nil
        return report
    }

    private static func compareGraph(swiftGraph: Spool, tlcGraph: Spool,
        swiftRoot: URL, tlcRoot: URL) throws -> String? {
        var swiftRanks = [Int](repeating: -1, count: swiftGraph.stateCount)
        var tlcRanks: [UInt64: Int] = [:]
        tlcRanks.reserveCapacity(tlcGraph.stateCount)
        let equalStates = try matchStates(
            swiftGraph.states, tlcGraph.states,
            leftRoot: swiftRoot, rightRoot: tlcRoot,
            expectedCount: swiftGraph.stateCount
        ) { nativeID, fingerprint, rank in
            guard nativeID < UInt64(swiftRanks.count), swiftRanks[Int(nativeID)] == -1,
                  tlcRanks.updateValue(rank, forKey: fingerprint) == nil else {
                throw ValidationEvidenceComparisonError.invalidEvidence("duplicate state identity")
            }
            swiftRanks[Int(nativeID)] = rank
        }
        guard equalStates, swiftGraph.stateCount == tlcGraph.stateCount else {
            return "complete state set"
        }
        let swiftInitial = try rankInitials(swiftGraph.initial, ranks: swiftRanks, in: swiftRoot)
        let tlcInitial = try rankInitials(tlcGraph.initial, ranks: tlcRanks, in: tlcRoot)
        if try firstDifference(swiftInitial, tlcInitial) != nil { return "initial state set" }
        let same = try compareBinaryEdges(swiftGraph.edges, tlcGraph.edges,
            stateCount: swiftGraph.stateCount,
            leftEdgeCount: swiftGraph.edgeCount, rightEdgeCount: tlcGraph.edgeCount,
            leftRank: { try Self.rank($0, in: swiftRanks) },
            rightRank: { try Self.rank($0, in: tlcRanks) })
        if !same { return "complete labeled edge set" }
        return nil
    }

    private struct StateRecord {
        let key: Data
        let id: UInt64
        let sortKey: UInt64
    }

    private static func matchStates(
        _ left: URL, _ right: URL, leftRoot: URL, rightRoot: URL,
        expectedCount: Int, assign: (UInt64, UInt64, Int) throws -> Void
    ) throws -> Bool {
        let leftBuckets = try measured("left state partition") { try partitionStates(left, in: leftRoot) }
        let rightBuckets = try measured("right state partition") { try partitionStates(right, in: rightRoot) }
        return try measured("state sort and match") {
            var rank = 0
            for index in leftBuckets.indices {
                let lhs = try stateRecords(leftBuckets[index])
                let rhs = try stateRecords(rightBuckets[index])
                guard lhs.count == rhs.count else { return false }
                var previous: Data?
                for offset in lhs.indices {
                    guard lhs[offset].key == rhs[offset].key,
                          previous != lhs[offset].key else { return false }
                    try assign(lhs[offset].id, rhs[offset].id, rank)
                    previous = lhs[offset].key
                    rank += 1
                }
            }
            return rank == expectedCount
        }
    }

    private static func partitionStates(_ input: URL, in directory: URL) throws -> [URL] {
        let bucketCount = 64
        let urls = (0..<bucketCount).map {
            directory.appendingPathComponent("state-bucket-\($0).bin")
        }
        var writers = try urls.map(BinaryStateWriter.init)
        defer { for index in writers.indices { try? writers[index].close() } }
        var reader = try BinaryGraphEvidenceReader(input)
        defer { reader.close() }
        while !reader.atEnd {
            let key = try reader.bytes(Int(reader.uint32()))
            let id = try reader.uint64()
            let digest = CryptoKit.SHA256.hash(data: key)
            let bucket = digest.withUnsafeBytes { Int($0[0]) & (bucketCount - 1) }
            try writers[bucket].append(key: key, id: id)
        }
        for index in writers.indices { try writers[index].close() }
        return urls
    }

    private static func stateRecords(_ input: URL) throws -> [StateRecord] {
        var reader = try BinaryGraphEvidenceReader(input)
        defer { reader.close() }
        var records: [StateRecord] = []
        while !reader.atEnd {
            let key = try reader.bytes(Int(reader.uint32()))
            let id = try reader.uint64()
            let digest = CryptoKit.SHA256.hash(data: key)
            let sortKey = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            records.append(StateRecord(key: key, id: id, sortKey: sortKey))
        }
        records.sort {
            if $0.sortKey != $1.sortKey { return $0.sortKey < $1.sortKey }
            return $0.key.lexicographicallyPrecedes($1.key)
        }
        return records
    }

    private struct Spool {
        let states: URL
        let initial: URL
        let edges: URL
        let stateCount: Int
        let initialCount: Int
        let edgeCount: Int
        let binaryEdges: Bool

        init(states: URL, initial: URL, edges: URL, stateCount: Int,
            initialCount: Int = 0, edgeCount: Int = 0, binaryEdges: Bool = false) {
            self.states = states
            self.initial = initial
            self.edges = edges
            self.stateCount = stateCount
            self.initialCount = initialCount
            self.edgeCount = edgeCount
            self.binaryEdges = binaryEdges
        }
    }

    private struct SpoolManifest: Codable {
        let schema: String
        let stateCount: Int
        let initialCount: Int
        let edgeCount: Int
        let binaryEdges: Bool
    }

    package static func writeTLCSpool(_ input: URL, caseID: String,
        actions: [RenderedAction], in directory: URL) throws {
        let spool = try readTLC(input, caseID: caseID, actions: actions, in: directory)
        try writeManifest(spool, in: directory)
    }

    package static func writeNativeSpool(_ input: URL, caseID: String, expectedComplete: Bool,
        actions: [RenderedAction], in directory: URL) throws {
        let spool = try readNative(input, caseID: caseID, expectedComplete: expectedComplete,
            actions: actions, in: directory)
        try writeManifest(spool, in: directory)
    }

    private static func writeManifest(_ spool: Spool, in directory: URL) throws {
        let manifest = SpoolManifest(schema: "swifttla.validation-spool-v3",
            stateCount: spool.stateCount, initialCount: spool.initialCount,
            edgeCount: spool.edgeCount, binaryEdges: spool.binaryEdges)
        try JSONEncoder().encode(manifest).write(
            to: directory.appendingPathComponent("spool.json"), options: .atomic)
    }

    private static func readManifest(in directory: URL) throws -> Spool {
        let manifest = try JSONDecoder().decode(SpoolManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("spool.json")))
        guard manifest.schema == "swifttla.validation-spool-v3", manifest.binaryEdges,
              manifest.stateCount >= 0, manifest.initialCount >= 0,
              manifest.edgeCount >= 0 else {
            throw ValidationEvidenceComparisonError.invalidEvidence("spool manifest")
        }
        let files = ["states.raw", "initial.raw", "edges.raw"].map(directory.appendingPathComponent)
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ValidationEvidenceComparisonError.invalidEvidence("spool file")
            }
        }
        return Spool(states: files[0], initial: files[1], edges: files[2],
            stateCount: manifest.stateCount, initialCount: manifest.initialCount,
            edgeCount: manifest.edgeCount, binaryEdges: manifest.binaryEdges)
    }

    private static func readBinary(_ url: URL, caseID: String, actions: [RenderedAction],
        producer: UInt8, expectedComplete: Bool, in directory: URL) throws -> Spool {
        let states = directory.appendingPathComponent("states.raw")
        let initial = directory.appendingPathComponent("initial.raw")
        let edges = directory.appendingPathComponent("edges.raw")
        var stateOut = try BinaryStateWriter(states)
        var initialOut = try ValidationLineWriter(initial)
        var edgeOut = try BinaryEdgeWriter(edges)
        defer { try? stateOut.close(); try? initialOut.close(); try? edgeOut.close() }
        let footerLength: UInt64 = 1 + 8 * 8 + 1 + 32
        var reader = try BinaryGraphEvidenceReader(url, checksumFooterLength: footerLength)
        defer { reader.close() }
        guard try reader.bytes(8) == Data("STLAGRF2".utf8),
              try reader.byte() == producer,
              try reader.string() == caseID else {
            throw ValidationEvidenceComparisonError.invalidEvidence("binary graph header")
        }
        let runID = try reader.string()
        guard producer == 1 ? UUID(uuidString: runID) != nil : runID.isEmpty else {
            throw ValidationEvidenceComparisonError.invalidEvidence("binary graph run ID")
        }
        let declaredNative = Dictionary(uniqueKeysWithValues: actions.map {
            ($0.sourceInvocationName, $0.renderedName)
        })
        let declaredTLC = Dictionary(uniqueKeysWithValues: actions.map {
            (tlaInvocationLocationIdentity(action: $0.sourceName,
                arguments: $0.arguments.map(\.description)), $0.renderedName)
        })
        let labels = Array(Set(actions.map(\.renderedName))).sorted()
        let labelIDs = Dictionary(uniqueKeysWithValues: labels.enumerated().map {
            ($0.element, UInt32($0.offset))
        })
        var actionIDs: [UInt32] = []
        var fingerprints: Set<UInt64> = []
        var stateCount = 0
        var initialCount = 0
        var edgeCount = 0
        var excludedCount = 0
        var unsupportedCount = 0
        var violationCount = 0
        var deadlockCount = 0
        var reachabilityCount = 0
        while true {
            let footerOffset = reader.offset
            let tag = try reader.byte()
            switch tag {
            case 1:
                let id = try reader.uint32()
                guard UInt64(id) == UInt64(actionIDs.count) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("binary action order")
                }
                let name = try reader.string()
                let location = try reader.string()
                let label: String
                if producer == 1 {
                    label = try resolvedAction(name: name, location: location, declared: declaredTLC)
                } else {
                    guard location.isEmpty, let resolved = declaredNative[name] else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("native action")
                    }
                    label = resolved
                }
                guard let labelID = labelIDs[label] else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("binary action label")
                }
                actionIDs.append(labelID)
            case 2:
                let identity = try reader.uint64()
                let initialFlag = try reader.byte()
                guard initialFlag <= 1 else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("binary initial flag")
                }
                if producer == 1 {
                    guard fingerprints.insert(identity).inserted else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("TLC state identity")
                    }
                } else {
                    guard identity == UInt64(stateCount) else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("native state identity")
                    }
                }
                let key = try reader.bytes(Int(reader.uint32()))
                do { try CanonicalBinaryState.validate(key) }
                catch { throw ValidationEvidenceComparisonError.invalidEvidence("binary state key") }
                try stateOut.append(key: key, id: identity)
                stateCount += 1
                if initialFlag == 1 {
                    initialCount += 1
                    try initialOut.append(String(identity))
                }
            case 3:
                let source = try reader.uint64()
                let action = try reader.uint32()
                let target = try reader.uint64()
                let known = producer == 1
                    ? fingerprints.contains(source) && fingerprints.contains(target)
                    : source < UInt64(stateCount) && target < UInt64(stateCount)
                guard known, UInt64(action) < UInt64(actionIDs.count) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("binary edge identity")
                }
                try edgeOut.append(source: source, action: actionIDs[Int(action)], target: target)
                edgeCount += 1
            case 4:
                let source = try reader.uint64()
                _ = try reader.uint64()
                let flags = try reader.uint16()
                let predicate = try reader.string()
                guard producer == 1, fingerprints.contains(source), flags == 2,
                      !predicate.isEmpty else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("TLC excluded transition")
                }
                excludedCount += 1
            case 5:
                let callback = try reader.string()
                let reason = try reader.string()
                guard producer == 1, callback == "writeState.visualization",
                      reason == "callback has no Action identity: STUTTERING" else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("unsupported TLC callback")
                }
                unsupportedCount += 1
            case 6, 8:
                guard producer == 2 else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("TLC property event")
                }
                let property = try reader.string()
                let key = try reader.bytes(Int(reader.uint32()))
                let predecessor = try reader.uint64()
                let action = try reader.uint32()
                do { try CanonicalBinaryState.validate(key) }
                catch { throw ValidationEvidenceComparisonError.invalidEvidence("native property state") }
                guard !property.isEmpty,
                      predecessor == UInt64.max || predecessor < UInt64(stateCount),
                      action == UInt32.max || UInt64(action) < UInt64(actionIDs.count) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native property event")
                }
                if tag == 6 { violationCount += 1 }
                else { reachabilityCount += 1 }
            case 7:
                let state = try reader.uint64()
                guard producer == 2, state < UInt64(stateCount) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native deadlock event")
                }
                deadlockCount += 1
            case 255:
                let counts = try (0..<8).map { _ in try reader.uint64() }
                let completion = try reader.byte()
                let checksum = try reader.bytes(32)
                let expectedCompletion = producer == 1 ? completion == 0
                    : expectedComplete ? completion == 0 : completion == 1 || completion == 2
                guard counts == [stateCount, initialCount, edgeCount, excludedCount,
                    unsupportedCount, violationCount, deadlockCount, reachabilityCount].map(UInt64.init),
                    expectedCompletion, reader.atEnd,
                    checksum == (try reader.sha256Prefix(endingAt: footerOffset)) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("binary graph footer")
                }
                try stateOut.close()
                try initialOut.close()
                try edgeOut.close()
                return Spool(states: states, initial: initial, edges: edges,
                    stateCount: stateCount, initialCount: initialCount,
                    edgeCount: edgeCount, binaryEdges: true)
            default:
                throw ValidationEvidenceComparisonError.invalidEvidence("binary graph event")
            }
        }
    }

    private static func spoolTLC(_ input: URL, caseID: String, actions: [RenderedAction],
        in directory: URL, executable: URL?, kind: String) throws -> Spool {
        guard let executable else {
            return try readTLC(input, caseID: caseID, actions: actions, in: directory)
        }
        try runSpool(executable, arguments: ["compare", "spool-tlc", "--kind", kind,
            "--case", caseID, "--input", input.path, "--output", directory.path])
        return try readManifest(in: directory)
    }

    private static func spoolNative(_ input: URL, caseID: String, expectedComplete: Bool,
        actions: [RenderedAction], in directory: URL, executable: URL?) throws -> Spool {
        guard let executable else {
            return try readNative(input, caseID: caseID, expectedComplete: expectedComplete,
                actions: actions, in: directory)
        }
        try runSpool(executable, arguments: ["compare", "spool-native", "--case", caseID,
            "--input", input.path, "--complete", expectedComplete ? "true" : "false",
            "--output", directory.path])
        return try readManifest(in: directory)
    }

    private static func runSpool(_ executable: URL, arguments: [String]) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("spool executable")
        }
        let process = Process()
        #if canImport(Darwin)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
        process.arguments = ["-l", executable.path] + arguments
        #else
        process.executableURL = executable
        process.arguments = arguments
        #endif
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ValidationEvidenceComparisonError.spoolingFailed(process.terminationStatus)
        }
    }

    private static func readNative(_ url: URL, caseID: String, expectedComplete: Bool,
        actions: [RenderedAction], in directory: URL) throws -> Spool {
        guard url.pathExtension == "bin" else {
            throw ValidationEvidenceComparisonError.invalidEvidence("native binary evidence required")
        }
        return try readBinary(url, caseID: caseID, actions: actions,
            producer: 2, expectedComplete: expectedComplete, in: directory)
    }

    private static func readTLC(_ url: URL, caseID: String, actions: [RenderedAction],
        in directory: URL) throws -> Spool {
        guard url.pathExtension == "bin" else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC binary evidence required")
        }
        return try readBinary(url, caseID: caseID, actions: actions,
            producer: 1, expectedComplete: true, in: directory)
    }
    private static func resolvedAction(name: String, location: String,
        declared: [String: String]) throws -> String {
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

    private static func rank(_ id: UInt64, in ranks: [Int]) throws -> UInt32 {
        guard id < UInt64(ranks.count), ranks[Int(id)] >= 0,
              let result = UInt32(exactly: ranks[Int(id)]) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("native edge rank")
        }
        return result
    }

    private static func rank(_ id: UInt64, in ranks: [UInt64: Int]) throws -> UInt32 {
        guard let value = ranks[id], let result = UInt32(exactly: value) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC edge rank")
        }
        return result
    }

    private struct RankedAdjacency {
        let offsets: [Int]
        let pairs: [UInt64]
    }

    private static func compareBinaryEdges(_ left: URL, _ right: URL,
        stateCount: Int, leftEdgeCount: Int, rightEdgeCount: Int,
        leftRank: (UInt64) throws -> UInt32,
        rightRank: (UInt64) throws -> UInt32) throws -> Bool {
        let lhs = try measured("left edge ranking") {
            try rankedAdjacency(left, stateCount: stateCount,
                edgeCount: leftEdgeCount, rank: leftRank)
        }
        let rhs = try measured("right edge ranking") {
            try rankedAdjacency(right, stateCount: stateCount,
                edgeCount: rightEdgeCount, rank: rightRank)
        }
        return measured("edge match") {
            for source in 0..<stateCount {
                var leftIndex = lhs.offsets[source]
                var rightIndex = rhs.offsets[source]
                let leftEnd = lhs.offsets[source + 1]
                let rightEnd = rhs.offsets[source + 1]
                while leftIndex < leftEnd && rightIndex < rightEnd {
                    let pair = lhs.pairs[leftIndex]
                    if pair != rhs.pairs[rightIndex] { return false }
                    repeat { leftIndex += 1 } while leftIndex < leftEnd && lhs.pairs[leftIndex] == pair
                    repeat { rightIndex += 1 } while rightIndex < rightEnd && rhs.pairs[rightIndex] == pair
                }
                if leftIndex != leftEnd || rightIndex != rightEnd { return false }
            }
            return true
        }
    }

    private static func rankedAdjacency(_ input: URL, stateCount: Int, edgeCount: Int,
        rank: (UInt64) throws -> UInt32) throws -> RankedAdjacency {
        let bytes = try Data(contentsOf: input, options: .mappedIfSafe)
        guard stateCount >= 0, stateCount < Int.max,
              edgeCount >= 0, edgeCount <= Int.max / 20,
              bytes.count == edgeCount * 20 else {
            throw ValidationEvidenceComparisonError.invalidEvidence("raw edge length")
        }
        var offsets = [Int](repeating: 0, count: stateCount + 1)
        var sources = [UInt32](repeating: 0, count: edgeCount)
        try bytes.withUnsafeBytes { raw in
            for edge in 0..<edgeCount {
                let base = edge * 20
                let identity = UInt64(bigEndian: raw.loadUnaligned(fromByteOffset: base, as: UInt64.self))
                let source = try rank(identity)
                guard UInt64(source) < UInt64(stateCount) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("source edge rank")
                }
                sources[edge] = source
                offsets[Int(source) + 1] += 1
            }
        }
        for index in 1..<offsets.count { offsets[index] += offsets[index - 1] }
        var cursors = offsets
        var pairs = [UInt64](repeating: 0, count: edgeCount)
        try bytes.withUnsafeBytes { raw in
            for edge in 0..<edgeCount {
                let base = edge * 20
                let action = UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self))
                let identity = UInt64(bigEndian: raw.loadUnaligned(fromByteOffset: base + 12, as: UInt64.self))
                let target = try rank(identity)
                let source = Int(sources[edge])
                pairs[cursors[source]] = (UInt64(action) << 32) | UInt64(target)
                cursors[source] += 1
            }
        }
        pairs.withUnsafeMutableBufferPointer { buffer in
            for source in 0..<stateCount {
                let start = offsets[source]
                let end = offsets[source + 1]
                if end - start > 1 {
                    var segment = UnsafeMutableBufferPointer(rebasing: buffer[start..<end])
                    segment.sort()
                }
            }
        }
        return RankedAdjacency(offsets: offsets, pairs: pairs)
    }

    private static func rankInitials(_ raw: URL, ranks: [UInt64: Int], in directory: URL) throws -> URL {
        try rewrite(raw, in: directory) { fields in
            guard fields.count == 1, let fingerprint = UInt64(fields[0]), let rank = ranks[fingerprint] else {
                throw ValidationEvidenceComparisonError.invalidEvidence("TLC initial fingerprint")
            }
            return String(rank)
        }
    }

    private static func rewrite(_ raw: URL, in directory: URL,
        transform: ([String]) throws -> String) throws -> URL {
        var reader = try ValidationLineReader(raw)
        defer { reader.close() }
        let ranked = directory.appendingPathComponent(raw.lastPathComponent + ".ranked")
        var writer = try ValidationLineWriter(ranked)
        defer { try? writer.close() }
        try consumeValidationLines(&reader) { line in
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

    private static func verifyTLCProcess(_ url: URL, report: GeneratedTLCOracleReport) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let process = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let invocation = process["invocation"] as? [String: Any],
              let status = invocation["exitStatus"] as? Int else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC process outcome")
        }
        let decisiveSafety = report.properties.values.contains { $0 == .violated || $0 == .reached }
        guard (report.graphComplete && status == 0)
            || (!report.graphComplete && status == 11 && report.deadlock == .violated)
            || (!report.graphComplete && status == 12 && decisiveSafety) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC process outcome")
        }
        return status
    }
}

private func withValidationAutoreleasePool<Result>(_ body: () throws -> Result) rethrows -> Result {
    #if canImport(Darwin)
    return try autoreleasepool(invoking: body)
    #else
    return try body()
    #endif
}

private func consumeValidationLines(_ reader: inout ValidationLineReader,
    _ consume: (Data) throws -> Void) throws {
    var finished = false
    while !finished {
        try withValidationAutoreleasePool {
            for _ in 0..<1_024 {
                guard let line = try reader.next() else {
                    finished = true
                    break
                }
                try consume(line)
            }
        }
    }
}

private struct ValidationLineReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var cursor = 0

    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
    }
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
    func close() {
        try? handle.close()
    }
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
