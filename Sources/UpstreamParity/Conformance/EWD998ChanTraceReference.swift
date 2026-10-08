import CoreFoundation
import Foundation
import SwiftTLA

/// Captures the published trace check without changing its TLA+ semantics.
package enum EWD998ChanTraceReference {
    private static let caseID = "ewd998-chan-trace"
    private static let fixture = "Verification/FiniteGraph/fixtures/ewd998"
    private static let expectedModules: Set<String> = [
        "FiniteSetsExt", "Folds", "Functions", "IOUtils", "SequencesExt", "VectorClocks"
    ]
    private static let examplePins = [
        "EWD998Chan": "ebdb5e9c6469fb1afc3b12198e1e2159b3ff3fa76d7bd15e5e11dce92b72313c",
        "Utils": "386c5319fd101fdde36610466f82151e8a39e01d1c6c8c44e894f7589bcc2b7b",
        "EWD998": "b51ba3587e0d1b88a38cc15cd667b7a50ccb72e7f5f79f7260c97e473f9392e8",
        "AsyncTerminationDetection": "c1b15be68a73c6e5f69c5c09f2736870182a9b0765ad9860452240119911b030"
    ]

    private struct CommunityLock: Decodable {
        let schema: String
        let tag: String
        let commit: String
        let jar: Jar
        let modules: [String: String]

        struct Jar: Decodable {
            let url: String
            let sha256: String
        }
    }

    package static func capture(
        repositoryRoot: URL, toolRoot: URL, tools: ResolvedTLCToolchain,
        pin: TLCReferencePin, timeout: TimeInterval, to output: URL,
        process: TLCProcessAdapter = TLCProcessAdapter()
    ) throws {
        let root = repositoryRoot.appendingPathComponent(fixture)
        let module = try pinnedText(root.appendingPathComponent("EWD998ChanTrace.tla"),
            sha256: "da182795698ff457ae8979b7d97cd47842d75e3d860323ca02031dc47c940171")
        let cfg = try pinnedText(root.appendingPathComponent("EWD998ChanTrace.cfg"),
            sha256: "e9e662c8672fff1a2affafb90efebbf1201f084e8f0e33698e2a42a9721bff64")
        let logURL = root.appendingPathComponent("EWD998ChanTrace.ndjson")
        let log = try Data(contentsOf: logURL)
        let logSHA = "0d288659698fe0a4db105988cdb326065aba82bf547b3473b94c760fc31bada5"
        guard SHA256.hex(log) == logSHA else {
            throw FiniteGraphCaseError.pinMismatch(logURL.lastPathComponent)
        }
        let input = try EWD998ChanTraceInput(ndjson: log)

        let lockURL = repositoryRoot.appendingPathComponent("Verification/FiniteGraph/community-modules.json")
        let lock = try JSONDecoder().decode(CommunityLock.self, from: Data(contentsOf: lockURL))
        guard lock.schema == "PinnedCommunityModules", lock.tag == "202609120237",
              lock.commit == "9aae8ea1318b3ded4629abdccec2c4754b528d70",
              lock.jar.url == "https://github.com/tlaplus/CommunityModules/releases/download/202609120237/CommunityModules-deps-202609120237.jar",
              Set(lock.modules.keys) == expectedModules else {
            throw FiniteGraphCaseError.pinMismatch("CommunityModules release")
        }
        let jar = try PinnedTLCModuleJar(
            url: toolRoot.appendingPathComponent("downloads/CommunityModules-deps.jar"),
            sha256: lock.jar.sha256)
        try jar.validate()

        let examples = try examplePins.sorted { $0.key < $1.key }.map { name, digest in
            TLAModuleFile(name: name, tla: try pinnedText(root.appendingPathComponent("\(name).tla"),
                sha256: digest))
        }
        let community = try lock.modules.sorted { $0.key < $1.key }.map { name, digest in
            TLAModuleFile(name: name, tla: try pinnedText(
                toolRoot.appendingPathComponent("community-modules/\(name).tla"), sha256: digest))
        }
        let edges: [(String, String)] = [
            ("EWD998ChanTrace", "EWD998Chan"), ("EWD998ChanTrace", "IOUtils"),
            ("EWD998ChanTrace", "VectorClocks"), ("EWD998Chan", "SequencesExt"),
            ("EWD998Chan", "Utils"), ("EWD998Chan", "EWD998"),
            ("Utils", "Functions"), ("EWD998", "Functions"),
            ("EWD998", "AsyncTerminationDetection"), ("IOUtils", "SequencesExt"),
            ("VectorClocks", "Functions"), ("SequencesExt", "FiniteSetsExt"),
            ("SequencesExt", "Folds"), ("SequencesExt", "Functions"),
            ("FiniteSetsExt", "Folds"), ("FiniteSetsExt", "Functions"),
            ("Functions", "Folds")
        ]
        let dependencies = edges.enumerated().map { index, edge in
            TLAModuleBundle.ModuleDependency(
                importingModule: edge.0, importedModule: edge.1,
                structuralPath: [caseID, "dependencies", String(index)])
        }
        let bundle = TLAModuleBundle.external(
            root: TLAModuleFile(name: "EWD998ChanTrace", tla: module, cfg: cfg),
            imports: examples + community, dependencies: dependencies)
        try bundle.validateDeclaredClosure()

        try RetainedFiles.outputDirectory(output, beneath: output.deletingLastPathComponent())
        let retainedInput = output.appendingPathComponent("reference-input")
        try GeneratedTLCOracle.retainGeneratedInputs(bundle, in: retainedInput)
        try log.write(to: retainedInput.appendingPathComponent("EWD998ChanTrace.ndjson"), options: .atomic)
        let work = output.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        let stagedLog = work.appendingPathComponent("EWD998ChanTrace.ndjson")
        try log.write(to: stagedLog, options: .atomic)
        let arguments = ["-workers", "1", "-fp", "1"]
        let configuration = try FiniteGraphCase(
            id: caseID, exploration: .init(maximumStateLimit: Int.max, symmetryReduction: .disabled),
            moduleSHA256: SHA256.hex(Data(module.utf8)), cfgSHA256: SHA256.hex(Data(cfg.utf8)),
            arguments: arguments, environment: ["JSON": stagedLog.path], pin: pin)
        let request = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            supplementalJar: jar, bundle: bundle,
            graphEvents: work.appendingPathComponent("unused.bin"),
            traceOutput: work.appendingPathComponent("counterexample.json"),
            workingDirectory: work, finiteGraphCase: configuration, runID: UUID(),
            timeout: timeout, invocation: .propertyCheck, referenceArtifacts: tools.artifacts)
        let outcome = try process.run(request, retainingIn: output.appendingPathComponent("tlc"))
        guard outcome == .completed else {
            throw EvidenceFormatError.invalidField(record: caseID, field: "pinned trace check: \(outcome)")
        }
        let marker = "\n============================================================================="
        guard module.components(separatedBy: marker).count == 2 else {
            throw EvidenceFormatError.invalidField(record: caseID, field: "trace module footer")
        }
        let instrumentedModule = module.replacingOccurrences(of: marker,
            with: "\nASSUME PrintT(TraceLog)\n" + marker)
        let instrumentedBundle = TLAModuleBundle.external(
            root: TLAModuleFile(name: "EWD998ChanTrace", tla: instrumentedModule, cfg: cfg),
            imports: examples + community, dependencies: dependencies)
        try GeneratedTLCOracle.retainGeneratedInputs(instrumentedBundle,
            in: output.appendingPathComponent("order-input"))
        let instrumentedCase = try FiniteGraphCase(
            id: caseID, exploration: .init(maximumStateLimit: Int.max, symmetryReduction: .disabled),
            moduleSHA256: SHA256.hex(Data(instrumentedModule.utf8)),
            cfgSHA256: SHA256.hex(Data(cfg.utf8)), arguments: arguments,
            environment: ["JSON": stagedLog.path], pin: pin)
        let orderRequest = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            supplementalJar: jar, bundle: instrumentedBundle,
            graphEvents: work.appendingPathComponent("unused-order.bin"),
            traceOutput: work.appendingPathComponent("order-counterexample.json"),
            evaluationOutput: work.appendingPathComponent("trace-log.bin"),
            workingDirectory: work, finiteGraphCase: instrumentedCase, runID: UUID(),
            timeout: timeout, invocation: .propertyCheck, referenceArtifacts: tools.artifacts)
        let orderOutcome = try process.run(orderRequest, retainingIn: output.appendingPathComponent("tlc-order"))
        guard orderOutcome == .completed else {
            throw EvidenceFormatError.invalidField(record: caseID, field: "instrumented trace check: \(orderOutcome)")
        }
        let printed = try TLCEvaluationOutput(reading:
            output.appendingPathComponent("tlc-order/tlc-evaluation.bin"))
        guard printed.values.count == 1 else {
            throw EvidenceFormatError.invalidField(record: caseID, field: "printed trace-log count")
        }
        let selectedOrder = try sourceLines(in: log, orderedBy: printed.values[0], input: input)
        let orderData = try JSONSerialization.data(withJSONObject: selectedOrder)
        try orderData.write(to: output.appendingPathComponent("selected-order.json"), options: .atomic)
        let tlcInput = try GeneratedTLCOracle.inputIdentity(
            bundle: bundle, pin: pin, arguments: arguments, invocation: .propertyCheck,
            supplementalJar: jar)
        let identity = try JSONSerialization.data(withJSONObject: [
            "tlcInput": tlcInput, "implementationLogSHA256": logSHA
        ], options: [.sortedKeys])
        try RetainedFiles.writeJSON([
            "schema": "swifttla.ewd998-trace-reference",
            "caseID": caseID, "result": "completed",
            "inputIdentity": SHA256.hex(identity),
            "implementationLogSHA256": logSHA,
            "nodeCount": input.nodeCount,
            "eventCount": input.events.count,
            "communityJarSHA256": jar.sha256,
            "causalOrderCaptured": true,
            "selectedOrderSHA256": SHA256.hex(orderData),
            "instrumentedModuleSHA256": instrumentedCase.moduleSHA256
        ], to: output.appendingPathComponent("report.json"))
    }

    package static func sourceLines(
        in ndjson: Data, orderedBy printed: CanonicalValue, input: EWD998ChanTraceInput
    ) throws -> [Int] {
        guard case .orderedTuple(let ordered) = printed, ordered.count == input.events.count else {
            throw EvidenceFormatError.invalidField(record: caseID, field: "printed trace-log shape")
        }
        let lines = ndjson.split(separator: 0x0A, omittingEmptySubsequences: true)
        guard lines.count == input.events.count + 1 else {
            throw EvidenceFormatError.invalidField(record: caseID, field: "implementation log length")
        }
        var sourceLinesByValue: [CanonicalValue: [Int]] = [:]
        for (offset, line) in lines.dropFirst().enumerated() {
            let value = try canonicalJSON(Data(line))
            sourceLinesByValue[value, default: []].append(offset + 2)
        }
        var selected: [Int] = []
        selected.reserveCapacity(ordered.count)
        for value in ordered {
            guard var available = sourceLinesByValue[value], !available.isEmpty else {
                throw EvidenceFormatError.invalidField(record: caseID, field: "printed trace-log event")
            }
            selected.append(available.removeFirst())
            sourceLinesByValue[value] = available
        }
        guard sourceLinesByValue.values.allSatisfy(\.isEmpty) else {
            throw EvidenceFormatError.invalidField(record: caseID, field: "printed trace-log permutation")
        }
        _ = try input.events(inCausalOrder: selected)
        return selected
    }

    private static func canonicalJSON(_ data: Data) throws -> CanonicalValue {
        try canonicalJSONValue(decodeJSONObject(data, line: 0))
    }

    private static func canonicalJSONValue(_ value: Any) throws -> CanonicalValue {
        if let fields = value as? [String: Any] {
            return .record(try fields.mapValues(canonicalJSONValue))
        }
        if let values = value as? [Any] {
            return .tuple(try values.map(canonicalJSONValue))
        }
        if let string = value as? String { return .string(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            if !CFNumberIsFloatType(number), let integer = Int(number.stringValue) {
                return .integer(integer)
            }
        }
        throw EvidenceFormatError.invalidField(record: caseID, field: "JSON trace-log value")
    }

    private static func pinnedText(_ url: URL, sha256: String) throws -> String {
        let data = try Data(contentsOf: url)
        guard SHA256.hex(data) == sha256, let value = String(data: data, encoding: .utf8) else {
            throw FiniteGraphCaseError.pinMismatch(url.lastPathComponent)
        }
        return value
    }
}
