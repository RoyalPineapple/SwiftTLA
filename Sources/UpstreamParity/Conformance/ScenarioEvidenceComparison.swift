import Foundation
import SwiftTLA

package enum ScenarioEvidenceComparison {
    package static func compare<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, native: URL, oracle: URL,
        actions: [RenderedAction], to directory: URL, spoolExecutable: URL? = nil
    ) throws -> ValidationEvidenceComparisonReport {
        if case .simulation = scenario.checkingMode {
            return try compareSampled(scenario: scenario, caseID: caseID,
                native: native, oracle: oracle, to: directory)
        }
        let decoder = JSONDecoder()
        let swift = try decoder.decode(NativeValidationReport.self,
            from: Data(contentsOf: native.appendingPathComponent("report.json")))
        let tlc = try decoder.decode(GeneratedTLCOracleReport.self,
            from: Data(contentsOf: oracle.appendingPathComponent("oracle.json")))
        let coverage = try ScenarioCheckCoverage(scenario)
        let rendered = try scenario.render()
        let graphChecks = rendered.checkNames.intersection(
            rendered.invariantNames.union(rendered.reachabilityNames))
        let checkedBundle = try rendered.tlaBundle(checking: graphChecks,
            checkDeadlock: rendered.checksDeadlock)
        let checkFreeBundle = try rendered.tlaBundle(checking: [], checkDeadlock: false)
        let processURL = oracle.appendingPathComponent("tlc-graph/tlc-process.json")
        let process = try JSONSerialization.jsonObject(with: Data(contentsOf: processURL)) as? [String: Any]
        let inputs = process?["inputs"] as? [[String: String]]
        let inputPairs = inputs?.compactMap { input -> (String, String)? in
            guard input.count == 2, let file = input["file"], let hash = input["sha256"] else {
                return nil
            }
            return (file, hash)
        }
        guard process?["caseID"] as? String == caseID,
              let inputs, let inputPairs, inputPairs.count == inputs.count,
              Set(inputPairs.map(\.0)).count == inputPairs.count,
              let configuration = process?["configuration"] as? String else {
            throw ValidationEvidenceComparisonError.invalidEvidence("generated TLC graph input")
        }
        let inputMap = Dictionary(uniqueKeysWithValues: inputPairs)
        func matches(_ bundle: TLAModuleBundle) -> Bool {
            configuration == bundle.cfg && inputMap == Dictionary(uniqueKeysWithValues:
                bundleInputJSON(bundle).map { ($0["file"]!, $0["sha256"]!) })
        }
        let checkedMatches = matches(checkedBundle)
        let checkFreeMatches = tlc.graphComplete && matches(checkFreeBundle)
        guard checkedMatches || checkFreeMatches else {
            throw ValidationEvidenceComparisonError.invalidEvidence("generated TLC graph input")
        }
        if checkedMatches, tlc.graphComplete {
            let graphVerdictsMatch = graphChecks.allSatisfy { name in
                tlc.properties[name] == (rendered.reachabilityNames.contains(name) ? .unreachable : .satisfied)
            }
            guard graphVerdictsMatch,
                  !rendered.checksDeadlock || tlc.deadlock == .satisfied else {
                throw ValidationEvidenceComparisonError.invalidEvidence("completed TLC graph verdict")
            }
        }
        if checkFreeMatches && !checkedMatches &&
            !FileManager.default.fileExists(atPath: oracle.appendingPathComponent("tlc-check/tlc-process.json").path) {
            throw ValidationEvidenceComparisonError.invalidEvidence("missing checked TLC pass")
        }
        guard swift.scenario == scenario.name,
              swift.deadlockSelected == coverage.checksDeadlock,
              tlc.deadlockSelected == coverage.checksDeadlock,
              swift.postconditionName == coverage.postconditionName,
              tlc.postconditionName == coverage.postconditionName,
              (coverage.postconditionName == nil || (swift.postcondition != nil && tlc.postcondition != nil)),
              Set(swift.properties.keys) == Set(coverage.selectedProperties),
              Set(tlc.properties.keys) == Set(coverage.selectedProperties) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("scenario check coverage")
        }
        if !coverage.checksDeadlock && (swift.deadlock != nil || tlc.deadlock != nil) {
            throw ValidationEvidenceComparisonError.invalidEvidence("unselected deadlock verdict")
        }
        if coverage.checksDeadlock && (swift.deadlock == nil || tlc.deadlock == nil) {
            throw ValidationEvidenceComparisonError.invalidEvidence("missing deadlock verdict")
        }
        let result = try ValidationEvidenceComparison.compare(
            scenario: scenario, caseID: caseID, native: native, oracle: oracle,
            actions: actions, to: directory, spoolExecutable: spoolExecutable)
        try coverage.attach(to: directory.appendingPathComponent("comparison.json"))
        guard result.result == "exact" else { return result }
        for (property, expected) in scenario.expectations {
            guard let name = scenario.formalPropertyNames[property],
                  let nativeVerdict = swift.properties[name], nativeVerdict.satisfies(expected),
                  let oracleVerdict = tlc.properties[name], oracleVerdict.satisfies(expected) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("scenario expected outcome")
            }
        }
        if let expected = scenario.deadlockExpectation {
            guard let nativeVerdict = swift.deadlock,
                  (nativeVerdict == .unavailable && !swift.graphComplete && expected == .satisfied
                    || nativeVerdict.satisfies(expected)) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("scenario expected deadlock")
            }
            guard let oracleVerdict = tlc.deadlock,
                  (oracleVerdict == .unavailable && !tlc.graphComplete && expected == .satisfied
                    || oracleVerdict.satisfies(expected)) else {
                throw ValidationEvidenceComparisonError.invalidEvidence("scenario expected deadlock")
            }
        }
        if let expected = scenario.postconditionExpectation {
            guard swift.postcondition?.satisfies(expected) == true,
                  tlc.postcondition?.satisfies(expected) == true else {
                throw ValidationEvidenceComparisonError.invalidEvidence("scenario expected postcondition")
            }
        }
        return result
    }

    private static func compareSampled<Scenario: ModelValidationScenario>(
        scenario: Scenario, caseID: String, native: URL, oracle: URL,
        to directory: URL
    ) throws -> ValidationEvidenceComparisonReport {
        guard case .simulation(let traces, let maximumDepth) = scenario.checkingMode else {
            throw ValidationEvidenceComparisonError.invalidEvidence("sampled scenario")
        }
        let decoder = JSONDecoder()
        let swift = try decoder.decode(NativeValidationReport.self,
            from: Data(contentsOf: native.appendingPathComponent("report.json")))
        let tlc = try decoder.decode(GeneratedTLCOracleReport.self,
            from: Data(contentsOf: oracle.appendingPathComponent("oracle.json")))
        let coverage = try ScenarioCheckCoverage(scenario)
        let rendered = try scenario.render()
        guard swift.schema == "swifttla.native-validation-report",
              tlc.schema == "swifttla.generated-tlc-oracle",
              tlc.caseID == caseID, swift.scenario == scenario.name,
              tlc.scenario == scenario.name, swift.maximumStates == tlc.maximumStates,
              !swift.graphComplete, !tlc.graphComplete,
              Set(swift.properties.keys) == Set(coverage.selectedProperties),
              Set(tlc.properties.keys) == Set(coverage.selectedProperties),
              swift.deadlockSelected == coverage.checksDeadlock,
              tlc.deadlockSelected == coverage.checksDeadlock,
              swift.postconditionName == nil, tlc.postconditionName == nil,
              swift.postcondition == nil, tlc.postcondition == nil else {
            throw ValidationEvidenceComparisonError.invalidEvidence("sampled check coverage")
        }
        let bundle = try rendered.tlaBundle(checking: rendered.checkNames,
            checkDeadlock: rendered.checksDeadlock)
        let process = try JSONSerialization.jsonObject(with:
            Data(contentsOf: oracle.appendingPathComponent("tlc-graph/tlc-process.json"))) as? [String: Any]
        let inputs = process?["inputs"] as? [[String: String]]
        let pairs = inputs?.compactMap { input -> (String, String)? in
            guard input.count == 2, let file = input["file"], let hash = input["sha256"] else { return nil }
            return (file, hash)
        }
        let expectedInputs = Dictionary(uniqueKeysWithValues: bundleInputJSON(bundle).map {
            ($0["file"]!, $0["sha256"]!)
        })
        let invocation = process?["invocation"] as? [String: Any]
        let arguments = invocation?["arguments"] as? [String]
        let retainedPin = process?["toolPin"] as? [String: Any]
        let simulationArguments = GeneratedTLCOracle.simulationArguments(
            traces: traces, maximumDepth: maximumDepth)
        guard process?["caseID"] as? String == caseID,
              process?["configuration"] as? String == bundle.cfg,
              let inputs, let pairs, pairs.count == inputs.count,
              Set(pairs.map(\.0)).count == pairs.count,
              Dictionary(uniqueKeysWithValues: pairs) == expectedInputs,
              let arguments,
              let retainedPin,
              let tag = retainedPin["tag"] as? String,
              let commit = retainedPin["commit"] as? String,
              let jarSHA256 = retainedPin["jarSHA256"] as? String,
              let javaDistribution = retainedPin["javaDistribution"] as? String,
              let javaVersion = retainedPin["javaVersion"] as? String,
              let javaArchiveSHA256 = retainedPin["javaArchiveSHA256"] as? String,
              let bridgeClass = retainedPin["bridgeClass"] as? String,
              let bridgeSourceHashes = retainedPin["bridgeSourceHashes"] as? [String: String],
              let bridgeBinarySHA256 = retainedPin["bridgeBinarySHA256"] as? String,
              let start = arguments.firstIndex(of: "-simulate"),
              let end = arguments.firstIndex(of: "-config"), start < end,
              Array(arguments[start..<end]) == simulationArguments else {
            throw ValidationEvidenceComparisonError.invalidEvidence("sampled TLC input")
        }
        let pin = try TLCReferencePin(tag: tag, commit: commit, jarSHA256: jarSHA256,
            javaDistribution: javaDistribution, javaVersion: javaVersion,
            javaArchiveSHA256: javaArchiveSHA256, bridgeClass: bridgeClass,
            bridgeSourceHashes: bridgeSourceHashes, bridgeBinarySHA256: bridgeBinarySHA256)
        guard tlc.graphInputSHA256 == (try GeneratedTLCOracle.inputIdentity(
            bundle: bundle, pin: pin, arguments: simulationArguments, invocation: .propertyCheck)) else {
            throw ValidationEvidenceComparisonError.invalidEvidence("sampled TLC identity")
        }
        let difference: String?
        if swift.properties != tlc.properties || swift.deadlock != tlc.deadlock {
            difference = "selected sampled verdict"
        } else if scenario.expectations.contains(where: { entry in
            let (property, expected) = entry
            guard let name = scenario.formalPropertyNames[property] else { return true }
            return swift.properties[name]?.satisfies(expected) != true
        }) || (scenario.deadlockExpectation.map { swift.deadlock?.satisfies($0) != true } ?? false) {
            difference = "selected sampled counterexample absent"
        } else {
            try NativeValidationRunner.verifySampledWitness(
                scenario: scenario, caseID: caseID, report: swift, in: native)
            try TLCWitnessVerification.verifySampled(
                scenario: scenario, report: tlc, caseID: caseID, oracle: oracle,
                rendered: rendered)
            difference = nil
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let report = ValidationEvidenceComparisonReport(
            schema: "swifttla.validation-evidence-comparison", caseID: caseID,
            result: difference == nil ? "exact" : "different", graphCompared: false,
            difference: difference, properties: swift.properties, deadlock: swift.deadlock,
            deadlockSelected: swift.deadlockSelected,
            postconditionName: nil, postcondition: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
        try coverage.attach(to: directory.appendingPathComponent("comparison.json"))
        return report
    }
}
