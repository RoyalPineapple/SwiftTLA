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
    private static let stateBucketCount = 64
    private static let edgeBucketCount = 64

    private static func measured<Result>(_ phase: String, _ body: () throws -> Result) rethrows -> Result {
        let started = DispatchTime.now().uptimeNanoseconds
        fputs("comparison phase \(phase): started\n", stderr)
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
        defer {
            try? FileManager.default.removeItem(at: generatedRoot)
            try? FileManager.default.removeItem(at: referenceRoot)
        }
        let generatedGraph = try measured("generated TLC spool") {
            try spoolTLC(generated, caseID: caseID, actions: actions,
                in: generatedRoot, executable: spoolExecutable, kind: "upstream")
        }
        let referenceGraph = try measured("reference TLC spool") {
            try spoolTLC(reference, caseID: caseID, actions: actions,
                in: referenceRoot, executable: spoolExecutable, kind: "upstream")
        }
        var generatedRanks = [UInt32](repeating: .max, count: generatedGraph.stateCount)
        var referenceRanks = [UInt32](repeating: .max, count: referenceGraph.stateCount)
        let equalStates = try matchStates(
            generatedGraph.states, referenceGraph.states,
            expectedCount: generatedGraph.stateCount
        ) { generatedID, referenceID, rank in
            guard generatedID < UInt64(generatedRanks.count),
                  referenceID < UInt64(referenceRanks.count),
                  generatedRanks[Int(generatedID)] == .max,
                  referenceRanks[Int(referenceID)] == .max,
                  let value = UInt32(exactly: rank), value != .max else {
                throw ValidationEvidenceComparisonError.invalidEvidence("duplicate state identity")
            }
            generatedRanks[Int(generatedID)] = value
            referenceRanks[Int(referenceID)] = value
        }
        guard equalStates, generatedGraph.stateCount == referenceGraph.stateCount else {
            return "complete state set"
        }
        try removeMatchedStateBuckets(generatedGraph.states, referenceGraph.states)
        let generatedInitial = try rankInitials(generatedGraph.initial, ranks: generatedRanks, in: generatedRoot)
        let referenceInitial = try rankInitials(referenceGraph.initial, ranks: referenceRanks, in: referenceRoot)
        if try firstDifference(generatedInitial, referenceInitial) != nil { return "initial state set" }
        let same = try compareBinaryEdges(generatedGraph.edges, referenceGraph.edges,
            stateCount: generatedGraph.stateCount,
            leftEdgeCount: generatedGraph.edgeCount, rightEdgeCount: referenceGraph.edgeCount,
            leftRank: { try Self.rank($0, in: generatedRanks) },
            rightRank: { try Self.rank($0, in: referenceRanks) })
        if !same { return "complete labeled edge set" }
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
        var spoolDirectories: [URL] = []
        defer {
            for spool in spoolDirectories { try? FileManager.default.removeItem(at: spool) }
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
                try spoolNative(native.appendingPathComponent("machine.bin.gz"),
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
                        oracle.appendingPathComponent("tlc-graph/graph-events.bin.gz"),
                        caseID: caseID, actions: actions, in: tlcRoot,
                        executable: spoolExecutable, kind: "native")
                }
                difference = try measured("complete graph") {
                    try Self.compareGraph(swiftGraph: swiftGraph, tlcGraph: tlcGraph,
                        swiftRoot: swiftRoot, tlcRoot: tlcRoot)
                }
            } else {
                guard let witness = swiftGraph.witness else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native decisive witness")
                }
                let nativeVerdict = witness.kind == "violation" ? ValidationVerdict.violated
                    : witness.kind == "reachability" ? .reached : .violated
                let reported = witness.kind == "deadlock" ? swift.deadlock : swift.properties[witness.property]
                guard reported == nativeVerdict else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native decisive witness")
                }
                let tlcWitnessStates = try TLCWitnessVerification.verifyPartial(scenario: scenario, report: tlc,
                    exitStatus: tlcExitStatus, oracle: oracle, rendered: scenario.render())
                if scenario.checkingMode == .decisiveCounterexample && witness.states != tlcWitnessStates {
                    difference = "shortest decisive witness length"
                }
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
        return report
    }

    private static func compareGraph(swiftGraph: Spool, tlcGraph: Spool,
        swiftRoot: URL, tlcRoot: URL) throws -> String? {
        guard swiftGraph.stateCount <= Int(UInt32.max) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("native state count")
        }
        var swiftRanks = [UInt32](repeating: .max, count: swiftGraph.stateCount)
        var tlcRanks = [UInt32](repeating: .max, count: tlcGraph.stateCount)
        let equalStates = try matchStates(
            swiftGraph.states, tlcGraph.states,
            expectedCount: swiftGraph.stateCount
        ) { nativeID, tlcID, rank in
            guard nativeID < UInt64(swiftRanks.count),
                  tlcID < UInt64(tlcRanks.count),
                  swiftRanks[Int(nativeID)] == .max,
                  tlcRanks[Int(tlcID)] == .max,
                  let value = UInt32(exactly: rank), value != .max else {
                throw ValidationEvidenceComparisonError.invalidEvidence("duplicate state identity")
            }
            swiftRanks[Int(nativeID)] = value
            tlcRanks[Int(tlcID)] = value
        }
        guard equalStates, swiftGraph.stateCount == tlcGraph.stateCount else {
            return "complete state set"
        }
        try removeMatchedStateBuckets(swiftGraph.states, tlcGraph.states)
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
        _ leftBuckets: [URL], _ rightBuckets: [URL],
        expectedCount: Int, assign: (UInt64, UInt64, Int) throws -> Void
    ) throws -> Bool {
        guard leftBuckets.count == rightBuckets.count else {
            throw ValidationEvidenceComparisonError.invalidEvidence("state bucket count")
        }
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

    private static func removeMatchedStateBuckets(_ left: [URL], _ right: [URL]) throws {
        for file in left + right {
            try FileManager.default.removeItem(at: file)
        }
    }

    private static func stateBucketURLs(in directory: URL) -> [URL] {
        (0..<stateBucketCount).map {
            directory.appendingPathComponent("state-bucket-\($0).bin")
        }
    }

    private static func stateRecords(_ input: URL) throws -> [StateRecord] {
        var reader = try BinaryGraphEvidenceReader(input)
        defer { reader.close() }
        var records: [StateRecord] = []
        while try !reader.isAtEnd() {
            let key = try reader.bytes(Int(reader.uint32()))
            let id = try reader.uint64()
            let sortKey = try reader.uint64()
            records.append(StateRecord(key: key, id: id, sortKey: sortKey))
        }
        records.sort {
            if $0.sortKey != $1.sortKey { return $0.sortKey < $1.sortKey }
            return $0.key.lexicographicallyPrecedes($1.key)
        }
        return records
    }

    private struct Spool {
        let states: [URL]
        let initial: URL
        let edges: URL
        let stateCount: Int
        let initialCount: Int
        let edgeCount: Int
        let binaryEdges: Bool
        let witness: NativeDecisiveWitness?

        init(states: [URL], initial: URL, edges: URL, stateCount: Int,
            initialCount: Int = 0, edgeCount: Int = 0, binaryEdges: Bool = false,
            witness: NativeDecisiveWitness? = nil) {
            self.states = states
            self.initial = initial
            self.edges = edges
            self.stateCount = stateCount
            self.initialCount = initialCount
            self.edgeCount = edgeCount
            self.binaryEdges = binaryEdges
            self.witness = witness
        }
    }

    private struct NativeDecisiveWitness: Codable {
        let kind: String
        let property: String
        let states: Int
    }

    private struct SpoolManifest: Codable {
        let schema: String
        let stateCount: Int
        let initialCount: Int
        let edgeCount: Int
        let binaryEdges: Bool
        let witness: NativeDecisiveWitness?
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
        let manifest = SpoolManifest(schema: "swifttla.validation-spool-v7",
            stateCount: spool.stateCount, initialCount: spool.initialCount,
            edgeCount: spool.edgeCount, binaryEdges: spool.binaryEdges, witness: spool.witness)
        try JSONEncoder().encode(manifest).write(
            to: directory.appendingPathComponent("spool.json"), options: .atomic)
    }

    private static func readManifest(in directory: URL) throws -> Spool {
        let manifest = try JSONDecoder().decode(SpoolManifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("spool.json")))
        guard manifest.schema == "swifttla.validation-spool-v7", manifest.binaryEdges,
              manifest.stateCount >= 0, manifest.initialCount >= 0,
              manifest.edgeCount >= 0 else {
            throw ValidationEvidenceComparisonError.invalidEvidence("spool manifest")
        }
        let states = stateBucketURLs(in: directory)
        let initial = directory.appendingPathComponent("initial.raw")
        let edges = directory.appendingPathComponent("edges.raw")
        let files = states + [initial, edges]
        for file in files {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ValidationEvidenceComparisonError.invalidEvidence("spool file")
            }
        }
        return Spool(states: states, initial: initial, edges: edges,
            stateCount: manifest.stateCount, initialCount: manifest.initialCount,
            edgeCount: manifest.edgeCount, binaryEdges: manifest.binaryEdges,
            witness: manifest.witness)
    }

    private static func readBinary(_ url: URL, caseID: String, actions: [RenderedAction],
        producer: UInt8, expectedComplete: Bool, in directory: URL) throws -> Spool {
        let states = stateBucketURLs(in: directory)
        let initial = directory.appendingPathComponent("initial.raw")
        let edges = directory.appendingPathComponent("edges.raw")
        var stateOut = try states.map(BinaryStateWriter.init)
        var initialOut = try ValidationLineWriter(initial)
        var edgeOut = try BinaryEdgeWriter(edges)
        defer {
            for index in stateOut.indices { try? stateOut[index].close() }
            try? initialOut.close()
            try? edgeOut.close()
        }
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
            ($0.emittedInvocationName, $0.renderedName)
        })
        let declaredTLC = Dictionary(uniqueKeysWithValues: actions.map {
            (tlaInvocationLocationIdentity(action: $0.emittedBaseName,
                arguments: $0.arguments.map(\.description)), $0.renderedName)
        })
        let labels = Array(Set(actions.map(\.renderedName))).sorted()
        let labelIDs = Dictionary(uniqueKeysWithValues: labels.enumerated().map {
            ($0.element, UInt32($0.offset))
        })
        var actionIDs: [UInt32] = []
        var fingerprintIDs: [UInt64: UInt32] = [:]
        var stateCount = 0
        var initialCount = 0
        var edgeCount = 0
        var excludedCount = 0
        var unsupportedCount = 0
        var violationCount = 0
        var deadlockCount = 0
        var reachabilityCount = 0
        var depths: [Int?] = []
        var witness: NativeDecisiveWitness?
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
                let localID: UInt64
                if producer == 1 {
                    guard stateCount < Int(UInt32.max),
                          fingerprintIDs.updateValue(UInt32(stateCount), forKey: identity) == nil else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("TLC state identity")
                    }
                    localID = UInt64(stateCount)
                } else {
                    guard identity == UInt64(stateCount) else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("native state identity")
                    }
                    localID = identity
                }
                let key = try reader.bytes(Int(reader.uint32()))
                do { try CanonicalBinaryState.validate(key) }
                catch { throw ValidationEvidenceComparisonError.invalidEvidence("binary state key") }
                let digest = CryptoKit.SHA256.hash(data: key)
                let bucket = digest.withUnsafeBytes { Int($0[0]) & (stateBucketCount - 1) }
                let sortKey = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                try stateOut[bucket].append(key: key, id: localID, sortKey: sortKey)
                stateCount += 1
                if producer == 2 && !expectedComplete { depths.append(initialFlag == 1 ? 0 : nil) }
                if initialFlag == 1 {
                    initialCount += 1
                    try initialOut.append(String(localID))
                }
            case 3:
                let source = try reader.uint64()
                let action = try reader.uint32()
                let target = try reader.uint64()
                let sourceID: UInt64
                let targetID: UInt64
                if producer == 1 {
                    guard let sourceIndex = fingerprintIDs[source],
                          let targetIndex = fingerprintIDs[target] else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("binary edge identity")
                    }
                    sourceID = UInt64(sourceIndex)
                    targetID = UInt64(targetIndex)
                } else {
                    guard source < UInt64(stateCount), target < UInt64(stateCount) else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("binary edge identity")
                    }
                    sourceID = source
                    targetID = target
                }
                guard UInt64(action) < UInt64(actionIDs.count) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("binary edge identity")
                }
                try edgeOut.append(source: sourceID, action: actionIDs[Int(action)], target: targetID)
                if producer == 2 && !expectedComplete && depths[Int(target)] == nil {
                    guard let sourceDepth = depths[Int(source)] else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("native witness path")
                    }
                    depths[Int(target)] = sourceDepth + 1
                }
                edgeCount += 1
            case 4:
                let source = try reader.uint64()
                _ = try reader.uint64()
                let flags = try reader.uint16()
                let predicate = try reader.string()
                guard producer == 1, fingerprintIDs[source] != nil, flags == 2,
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
                if !expectedComplete {
                    guard witness == nil,
                          (predecessor == UInt64.max) == (action == UInt32.max) else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("native decisive witness")
                    }
                    let length: Int
                    if predecessor == UInt64.max { length = 1 }
                    else {
                        guard let predecessorDepth = depths[Int(predecessor)] else {
                            throw ValidationEvidenceComparisonError.invalidEvidence("native witness path")
                        }
                        length = predecessorDepth + 2
                    }
                    witness = NativeDecisiveWitness(kind: tag == 6 ? "violation" : "reachability",
                        property: property, states: length)
                }
            case 7:
                let state = try reader.uint64()
                guard producer == 2, state < UInt64(stateCount) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("native deadlock event")
                }
                deadlockCount += 1
                if !expectedComplete {
                    guard witness == nil, let depth = depths[Int(state)] else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("native decisive witness")
                    }
                    witness = NativeDecisiveWitness(kind: "deadlock", property: "", states: depth + 1)
                }
            case 255:
                let counts = try (0..<8).map { _ in try reader.uint64() }
                let completion = try reader.byte()
                let checksum = try reader.bytes(32)
                let expectedCompletion = producer == 1 ? completion == 0
                    : expectedComplete ? completion == 0 : completion == 1 || completion == 2
                guard counts == [stateCount, initialCount, edgeCount, excludedCount,
                    unsupportedCount, violationCount, deadlockCount, reachabilityCount].map(UInt64.init),
                    expectedCompletion, (try reader.isAtEnd()),
                    checksum == (try reader.sha256Prefix(endingAt: footerOffset)) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("binary graph footer")
                }
                if producer == 2 && !expectedComplete {
                    guard let witness,
                          (completion == 1 && witness.kind != "reachability")
                            || (completion == 2 && witness.kind == "reachability") else {
                        throw ValidationEvidenceComparisonError.invalidEvidence("native decisive witness")
                    }
                }
                for index in stateOut.indices { try stateOut[index].close() }
                try initialOut.close()
                try edgeOut.close()
                return Spool(states: states, initial: initial, edges: edges,
                    stateCount: stateCount, initialCount: initialCount,
                    edgeCount: edgeCount, binaryEdges: true, witness: witness)
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
        guard url.pathExtension == "bin" || url.lastPathComponent.hasSuffix(".bin.gz") else {
            throw ValidationEvidenceComparisonError.invalidEvidence("native binary evidence required")
        }
        return try readBinary(url, caseID: caseID, actions: actions,
            producer: 2, expectedComplete: expectedComplete, in: directory)
    }

    private static func readTLC(_ url: URL, caseID: String, actions: [RenderedAction],
        in directory: URL) throws -> Spool {
        guard url.pathExtension == "bin" || url.lastPathComponent.hasSuffix(".bin.gz") else {
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
            throw ValidationEvidenceComparisonError.invalidEvidence("undeclared TLC action \(identity)")
        }
        return label
    }

    private static func rankInitials(_ raw: URL, ranks: [UInt32], in directory: URL) throws -> URL {
        try rewrite(raw, in: directory) { fields in
            guard fields.count == 1, let id = Int(fields[0]), id >= 0, id < ranks.count,
                  ranks[id] != .max else { throw ValidationEvidenceComparisonError.invalidEvidence("initial state ID") }
            return String(ranks[id])
        }
    }

    private static func rank(_ id: UInt64, in ranks: [UInt32]) throws -> UInt32 {
        guard id < UInt64(ranks.count), ranks[Int(id)] != .max else {
            throw ValidationEvidenceComparisonError.invalidEvidence("edge rank")
        }
        return ranks[Int(id)]
    }

    private struct RankedAdjacency {
        let offsets: [Int]
        let pairs: [UInt64]
    }

    private struct RankedEdgeBuckets {
        let files: [URL]
        let counts: [Int]
    }

    private static func compareBinaryEdges(_ left: URL, _ right: URL,
        stateCount: Int, leftEdgeCount: Int, rightEdgeCount: Int,
        leftRank: (UInt64) throws -> UInt32,
        rightRank: (UInt64) throws -> UInt32) throws -> Bool {
        let lhs = try measured("left edge ranking") {
            try rankEdgeBuckets(left, stateCount: stateCount,
                edgeCount: leftEdgeCount, rank: leftRank)
        }
        try FileManager.default.removeItem(at: left)
        let rhs = try measured("right edge ranking") {
            try rankEdgeBuckets(right, stateCount: stateCount,
                edgeCount: rightEdgeCount, rank: rightRank)
        }
        try FileManager.default.removeItem(at: right)
        return try measured("edge match") {
            for bucket in 0..<edgeBucketCount {
                let left = try rankedAdjacency(lhs.files[bucket], stateCount: stateCount,
                    bucket: bucket, edgeCount: lhs.counts[bucket])
                let right = try rankedAdjacency(rhs.files[bucket], stateCount: stateCount,
                    bucket: bucket, edgeCount: rhs.counts[bucket])
                for source in 0..<(left.offsets.count - 1) {
                    var leftIndex = left.offsets[source]
                    var rightIndex = right.offsets[source]
                    let leftEnd = left.offsets[source + 1]
                    let rightEnd = right.offsets[source + 1]
                    while leftIndex < leftEnd && rightIndex < rightEnd {
                        let pair = left.pairs[leftIndex]
                        if pair != right.pairs[rightIndex] { return false }
                        repeat { leftIndex += 1 } while leftIndex < leftEnd && left.pairs[leftIndex] == pair
                        repeat { rightIndex += 1 } while rightIndex < rightEnd && right.pairs[rightIndex] == pair
                    }
                    if leftIndex != leftEnd || rightIndex != rightEnd { return false }
                }
            }
            return true
        }
    }

    private static func rankEdgeBuckets(_ input: URL, stateCount: Int, edgeCount: Int,
        rank: (UInt64) throws -> UInt32) throws -> RankedEdgeBuckets {
        let bytes = try Data(contentsOf: input, options: .mappedIfSafe)
        guard stateCount >= 0, edgeCount >= 0, edgeCount <= Int.max / 12,
              bytes.count == edgeCount * 12 else {
            throw ValidationEvidenceComparisonError.invalidEvidence("raw edge length")
        }
        let directory = input.deletingLastPathComponent().appendingPathComponent("ranked-edge-buckets")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let files = (0..<edgeBucketCount).map {
            directory.appendingPathComponent("bucket-\($0).bin")
        }
        var writers = try files.map(RankedEdgeBucketWriter.init)
        var closed = false
        defer {
            if !closed {
                for index in writers.indices { try? writers[index].close() }
            }
        }
        var counts = [Int](repeating: 0, count: edgeBucketCount)
        var previousSourceID: UInt64?
        var previousSourceRank: UInt32 = 0
        try bytes.withUnsafeBytes { raw in
            for edge in 0..<edgeCount {
                let base = edge * 12
                let sourceID = UInt64(UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: base, as: UInt32.self)))
                let action = UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: base + 4, as: UInt32.self))
                let targetID = UInt64(UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self)))
                let source: UInt32
                if previousSourceID == sourceID {
                    source = previousSourceRank
                } else {
                    source = try rank(sourceID)
                    previousSourceID = sourceID
                    previousSourceRank = source
                }
                let target = try rank(targetID)
                guard UInt64(source) < UInt64(stateCount), UInt64(target) < UInt64(stateCount) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("edge rank")
                }
                let bucket = Int(source) % edgeBucketCount
                try writers[bucket].append(source: source, action: action, target: target)
                counts[bucket] += 1
            }
        }
        for index in writers.indices { try writers[index].close() }
        closed = true
        return RankedEdgeBuckets(files: files, counts: counts)
    }

    private static func rankedAdjacency(_ input: URL, stateCount: Int,
        bucket: Int, edgeCount: Int) throws -> RankedAdjacency {
        let bytes = try Data(contentsOf: input, options: .mappedIfSafe)
        guard edgeCount >= 0, edgeCount <= Int.max / 12,
              bytes.count == edgeCount * 12 else {
            throw ValidationEvidenceComparisonError.invalidEvidence("ranked edge length")
        }
        let localSources = stateCount / edgeBucketCount
            + (bucket < stateCount % edgeBucketCount ? 1 : 0)
        var offsets = [Int](repeating: 0, count: localSources + 1)
        try bytes.withUnsafeBytes { raw in
            for edge in 0..<edgeCount {
                let base = edge * 12
                let source = UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: base, as: UInt32.self))
                guard UInt64(source) < UInt64(stateCount), Int(source) % edgeBucketCount == bucket else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("source edge rank")
                }
                offsets[Int(source) / edgeBucketCount + 1] += 1
            }
        }
        for index in 1..<offsets.count { offsets[index] += offsets[index - 1] }
        var cursors = offsets
        var pairs = [UInt64](repeating: 0, count: edgeCount)
        try bytes.withUnsafeBytes { raw in
            for edge in 0..<edgeCount {
                let base = edge * 12
                let source = UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: base, as: UInt32.self))
                let action = UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: base + 4, as: UInt32.self))
                let target = UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: base + 8, as: UInt32.self))
                guard UInt64(target) < UInt64(stateCount) else {
                    throw ValidationEvidenceComparisonError.invalidEvidence("target edge rank")
                }
                let localSource = Int(source) / edgeBucketCount
                pairs[cursors[localSource]] = (UInt64(action) << 32) | UInt64(target)
                cursors[localSource] += 1
            }
        }
        pairs.withUnsafeMutableBufferPointer { buffer in
            for source in 0..<localSources {
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
            || (!report.graphComplete && status == 12 && decisiveSafety
                && (!report.deadlockSelected || report.deadlock == .unavailable)) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("TLC process outcome")
        }
        return status
    }
}

private struct RankedEdgeBucketWriter {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ url: URL) throws {
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        buffer.reserveCapacity(262_144)
    }

    mutating func append(source: UInt32, action: UInt32, target: UInt32) throws {
        uint32(source)
        uint32(action)
        uint32(target)
        if buffer.count >= 262_144 { try flush() }
    }

    mutating func close() throws {
        try flush()
        try handle.close()
    }

    private mutating func uint32(_ value: UInt32) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { buffer.append(contentsOf: $0) }
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        try handle.write(contentsOf: buffer)
        buffer.removeAll(keepingCapacity: true)
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
