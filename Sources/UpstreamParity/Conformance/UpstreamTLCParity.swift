import Foundation
import SwiftTLA

package struct UpstreamTLCParityReport: Codable, Sendable {
    package let schema: String
    package let caseID: String
    package let result: String
    package let graphCompared: Bool
    package let difference: String?
    package let generatedProperties: [String: ValidationVerdict]
    package let referenceProperties: [String: ValidationVerdict]
    /// State predicates checked by generated TLC and transferred to the
    /// reference only after the complete state graphs compare exactly.
    package let referenceGraphDerivedProperties: [String]?
    package let generatedDeadlock: ValidationVerdict?
    package let referenceDeadlock: ValidationVerdict?
    package let deadlockSelected: Bool
}

package enum UpstreamTLCParityError: Error, Equatable {
    case inputMismatch(String)
    case configurationMismatch(String)
    case invalidOutcome(String)
}

/// The upstream comparison runs TLC on both module bundles. It never invokes
/// the Swift machine or native checker.
package enum UpstreamTLCParity {
    package static func sampledCacheKey(
        id: String, rendered: RenderedSpecification, reference: TLAModuleBundle,
        expectedModuleSHA256: String, expectedCFGSHA256: String,
        maximumStates: Int, traces: Int, maximumDepth: Int, pin: TLCReferencePin
    ) throws -> String {
        guard SHA256.hex(Data(reference.tla.utf8)) == expectedModuleSHA256,
              SHA256.hex(Data(reference.cfg.utf8)) == expectedCFGSHA256,
              rendered.checkNames.count == 1,
              rendered.checkNames.isSubset(of: rendered.invariantNames),
              !rendered.checksDeadlock else {
            throw UpstreamTLCParityError.inputMismatch(id)
        }
        let arguments = GeneratedTLCOracle.simulationArguments(
            traces: traces, maximumDepth: maximumDepth)
        let identity: [String: Any] = [
            "schema": "swifttla.sampled-upstream-cache-key-v1",
            "caseID": id,
            "maximumStates": maximumStates,
            "expectedModuleSHA256": expectedModuleSHA256,
            "expectedCFGSHA256": expectedCFGSHA256,
            "generated": try GeneratedTLCOracle.inputIdentity(
                bundle: rendered.tlaBundle(checking: rendered.checkNames, checkDeadlock: false),
                pin: pin, arguments: arguments, invocation: .propertyCheck),
            "reference": try GeneratedTLCOracle.inputIdentity(
                bundle: reference, pin: pin, arguments: arguments, invocation: .propertyCheck),
            "actions": rendered.actions.map {
                ["invocation": $0.sourceInvocationName, "rendered": $0.renderedName]
            }
        ]
        return SHA256.hex(try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys]))
    }

    package static func runSampled(
        id: String, rendered: RenderedSpecification, reference: TLAModuleBundle,
        expectedModuleSHA256: String, expectedCFGSHA256: String,
        maximumStates: Int, timeout: TimeInterval, traces: Int, maximumDepth: Int,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin, to directory: URL,
        process: TLCProcessAdapter = TLCProcessAdapter()
    ) throws -> UpstreamTLCParityReport {
        guard SHA256.hex(Data(reference.tla.utf8)) == expectedModuleSHA256,
              SHA256.hex(Data(reference.cfg.utf8)) == expectedCFGSHA256 else {
            throw UpstreamTLCParityError.inputMismatch(id)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let work = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        let bundles = try sampledBundles(id: id, rendered: rendered, reference: reference,
            maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin, work: work)
        let arguments = GeneratedTLCOracle.simulationArguments(
            traces: traces, maximumDepth: maximumDepth)
        let generatedOutput = directory.appendingPathComponent("generated-sampled")
        let referenceOutput = directory.appendingPathComponent("reference-sampled")
        _ = try GeneratedTLCOracle.run(bundle: bundles.generated, id: id,
            maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
            workRoot: work, retained: generatedOutput, invocation: .propertyCheck,
            renderedActions: rendered.actions, process: process, arguments: arguments)
        _ = try GeneratedTLCOracle.run(bundle: bundles.reference, id: id,
            maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
            workRoot: work, retained: referenceOutput, invocation: .propertyCheck,
            renderedActions: rendered.actions, process: process, arguments: arguments)
        return try compareSampled(id: id, name: bundles.name, generated: bundles.generated,
            reference: bundles.reference, pin: pin, arguments: arguments, in: directory)
    }

    package static func recompareCachedSampled(
        id: String, rendered: RenderedSpecification, reference: TLAModuleBundle,
        expectedModuleSHA256: String, expectedCFGSHA256: String,
        maximumStates: Int, timeout: TimeInterval, traces: Int, maximumDepth: Int,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin, in directory: URL
    ) throws -> UpstreamTLCParityReport {
        guard SHA256.hex(Data(reference.tla.utf8)) == expectedModuleSHA256,
              SHA256.hex(Data(reference.cfg.utf8)) == expectedCFGSHA256 else {
            throw UpstreamTLCParityError.inputMismatch(id)
        }
        let previous = try JSONDecoder().decode(UpstreamTLCParityReport.self,
            from: Data(contentsOf: directory.appendingPathComponent("comparison.json")))
        guard previous.schema == "swifttla.upstream-tlc-parity", previous.caseID == id,
              previous.result == "exact", !previous.graphCompared,
              !previous.deadlockSelected, previous.generatedDeadlock == nil,
              previous.referenceDeadlock == nil else {
            throw UpstreamTLCParityError.invalidOutcome("cached sampled comparison: \(id)")
        }
        let work = directory.appendingPathComponent("recompare-work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        let bundles = try sampledBundles(id: id, rendered: rendered, reference: reference,
            maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin, work: work)
        let arguments = GeneratedTLCOracle.simulationArguments(
            traces: traces, maximumDepth: maximumDepth)
        let report = try compareSampled(id: id, name: bundles.name, generated: bundles.generated,
            reference: bundles.reference, pin: pin, arguments: arguments, in: directory)
        guard report.generatedProperties == previous.generatedProperties,
              report.referenceProperties == previous.referenceProperties else {
            throw UpstreamTLCParityError.invalidOutcome("changed cached sampled verdict: \(id)")
        }
        return report
    }

    private static func sampledBundles(
        id: String, rendered: RenderedSpecification, reference: TLAModuleBundle,
        maximumStates: Int, timeout: TimeInterval,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin, work: URL
    ) throws -> (name: String, generated: TLAModuleBundle, reference: TLAModuleBundle) {
        guard rendered.checkNames.count == 1, let name = rendered.checkNames.first,
              rendered.invariantNames.contains(name), !rendered.checksDeadlock else {
            throw UpstreamTLCParityError.configurationMismatch(id)
        }
        let parseWork = work.appendingPathComponent("parse")
        try FileManager.default.createDirectory(at: parseWork, withIntermediateDirectories: false)
        let referenceCase = try FiniteGraphCase(
            id: id, exploration: .init(maximumStateLimit: maximumStates, symmetryReduction: .disabled),
            moduleSHA256: SHA256.hex(Data(reference.tla.utf8)),
            cfgSHA256: SHA256.hex(Data(reference.cfg.utf8)),
            arguments: ["-workers", "1", "-fp", "1"], environment: [:], pin: pin,
            renderedActions: rendered.actions)
        let parseRequest = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            bundle: reference, graphEvents: parseWork.appendingPathComponent("events.jsonl"),
            traceOutput: parseWork.appendingPathComponent("counterexample.json"),
            workingDirectory: parseWork, finiteGraphCase: referenceCase, runID: UUID(),
            timeout: timeout, invocation: .propertyCheck, referenceArtifacts: tools.artifacts)
        let configuration = try TLCReferenceConfiguration.parse(
            parseRequest, checking: rendered.checkNames)
        guard configuration.invariants == [name], configuration.properties.isEmpty,
              !configuration.checksDeadlock else {
            throw UpstreamTLCParityError.configurationMismatch(id)
        }
        return (name,
            try rendered.tlaBundle(checking: [name], checkDeadlock: false),
            try rendered.referenceBundle(checking: [name], checkDeadlock: false,
                declarations: configuration.declarations, in: reference))
    }

    private static func compareSampled(
        id: String, name: String, generated: TLAModuleBundle,
        reference: TLAModuleBundle, pin: TLCReferencePin,
        arguments: [String], in directory: URL
    ) throws -> UpstreamTLCParityReport {
        let generatedVerdict = try sampledVerdict(id: id, name: name, bundle: generated,
            pin: pin, arguments: arguments, in: directory.appendingPathComponent("generated-sampled"))
        let referenceVerdict = try sampledVerdict(id: id, name: name, bundle: reference,
            pin: pin, arguments: arguments, in: directory.appendingPathComponent("reference-sampled"))
        let difference: String? = generatedVerdict == .violated && referenceVerdict == .violated
            ? nil : "sampled counterexample absent or verdict differs"
        let report = UpstreamTLCParityReport(
            schema: "swifttla.upstream-tlc-parity", caseID: id,
            result: difference == nil ? "exact" : "different", graphCompared: false,
            difference: difference,
            generatedProperties: [name: generatedVerdict],
            referenceProperties: [name: referenceVerdict],
            referenceGraphDerivedProperties: nil,
            generatedDeadlock: nil, referenceDeadlock: nil, deadlockSelected: false)
        try write(report, to: directory)
        return report
    }

    private static func sampledVerdict(
        id: String, name: String, bundle: TLAModuleBundle, pin: TLCReferencePin,
        arguments: [String], in directory: URL
    ) throws -> ValidationVerdict {
        let receipt = try JSONSerialization.jsonObject(with:
            Data(contentsOf: directory.appendingPathComponent("tlc-process.json"))) as? [String: Any]
        let inputs = receipt?["inputs"] as? [[String: String]]
        let pairs = inputs?.compactMap { item -> (String, String)? in
            guard item.count == 2, let file = item["file"], let hash = item["sha256"] else { return nil }
            return (file, hash)
        }
        let expectedInputs = Dictionary(uniqueKeysWithValues: bundleInputJSON(bundle).map {
            ($0["file"]!, $0["sha256"]!)
        })
        let expectedPin: [String: Any] = [
            "tag": pin.tag, "commit": pin.commit, "jarSHA256": pin.jarSHA256,
            "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion,
            "javaArchiveSHA256": pin.javaArchiveSHA256, "bridgeClass": pin.bridgeClass,
            "bridgeSourceHashes": pin.bridgeSourceHashes,
            "bridgeBinarySHA256": pin.bridgeBinarySHA256
        ]
        let invocation = receipt?["invocation"] as? [String: Any]
        let command = invocation?["arguments"] as? [String]
        let toolPin = receipt?["toolPin"] as? [String: Any]
        guard receipt?["caseID"] as? String == id,
              receipt?["configuration"] as? String == bundle.cfg,
              let inputs, let pairs, pairs.count == inputs.count,
              Set(pairs.map(\.0)).count == pairs.count,
              Dictionary(uniqueKeysWithValues: pairs) == expectedInputs,
              let command, let start = command.firstIndex(of: "-simulate"),
              let end = command.firstIndex(of: "-config"), start < end,
              Array(command[start..<end]) == arguments,
              let toolPin,
              try JSONSerialization.data(withJSONObject: toolPin, options: [.sortedKeys])
                  == JSONSerialization.data(withJSONObject: expectedPin, options: [.sortedKeys]),
              let status = invocation?["exitStatus"] as? Int else {
            throw UpstreamTLCParityError.invalidOutcome("sampled TLC receipt: \(id)")
        }
        if status == 0 { return .unavailable }
        guard status == 12 else {
            throw UpstreamTLCParityError.invalidOutcome("sampled TLC status: \(id): \(status)")
        }
        let stdout = try String(contentsOf: directory.appendingPathComponent("logs/tlc.stdout.log"),
            encoding: .utf8)
        let trace = try JSONSerialization.jsonObject(with:
            Data(contentsOf: directory.appendingPathComponent("counterexample.json"))) as? [String: Any]
        let counterexample = trace?["counterexample"] as? [String: Any]
        guard stdout.split(whereSeparator: \.isNewline).contains(where: {
            $0 == "Error: Invariant \(name) is violated."
                || $0 == "Error: Invariant \(name) is violated by the initial state:"
        }), let states = counterexample?["state"] as? [Any], !states.isEmpty else {
            throw UpstreamTLCParityError.invalidOutcome("sampled TLC witness: \(id)")
        }
        return .violated
    }

    package static func cacheKey(
        id: String, rendered: RenderedSpecification, reference: TLAModuleBundle,
        expectedModuleSHA256: String, expectedCFGSHA256: String,
        maximumStates: Int, decisive: Bool, pin: TLCReferencePin
    ) throws -> String {
        guard SHA256.hex(Data(reference.tla.utf8)) == expectedModuleSHA256,
              SHA256.hex(Data(reference.cfg.utf8)) == expectedCFGSHA256 else {
            throw UpstreamTLCParityError.inputMismatch(id)
        }
        let generated = try rendered.tlaBundle(
            checking: rendered.checkNames, checkDeadlock: rendered.checksDeadlock)
        let identity: [String: Any] = [
            "schema": "swifttla.upstream-cache-key-v1",
            "caseID": id,
            "maximumStates": maximumStates,
            "decisive": decisive,
            "expectedModuleSHA256": expectedModuleSHA256,
            "expectedCFGSHA256": expectedCFGSHA256,
            "generated": try GeneratedTLCOracle.inputIdentity(bundle: generated, pin: pin,
                arguments: ["-workers", "1", "-fp", "1"]),
            "reference": try GeneratedTLCOracle.inputIdentity(bundle: reference, pin: pin,
                arguments: ["-workers", "1", "-fp", "1"]),
            "actions": rendered.actions.map {
                ["invocation": $0.sourceInvocationName, "rendered": $0.renderedName]
            }
        ]
        return SHA256.hex(try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys]))
    }

    package static func run(
        id: String, rendered: RenderedSpecification, reference: TLAModuleBundle,
        expectedModuleSHA256: String, expectedCFGSHA256: String,
        maximumStates: Int, timeout: TimeInterval, decisive: Bool,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin, to directory: URL,
        process: TLCProcessAdapter = TLCProcessAdapter(), spoolExecutable: URL? = nil,
        generatedOracle: URL? = nil
    ) throws -> UpstreamTLCParityReport {
        guard SHA256.hex(Data(reference.tla.utf8)) == expectedModuleSHA256,
              SHA256.hex(Data(reference.cfg.utf8)) == expectedCFGSHA256 else {
            throw UpstreamTLCParityError.inputMismatch(id)
        }
        guard generatedOracle == nil || !decisive else {
            throw UpstreamTLCParityError.invalidOutcome("decisive generated oracle: \(id)")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let work = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        let parseWork = work.appendingPathComponent("parse")
        try FileManager.default.createDirectory(at: parseWork, withIntermediateDirectories: false)
        let referenceCase = try FiniteGraphCase(
            id: id, exploration: .init(maximumStateLimit: maximumStates, symmetryReduction: .disabled),
            moduleSHA256: expectedModuleSHA256, cfgSHA256: expectedCFGSHA256,
            arguments: ["-workers", "1", "-fp", "1"], environment: [:], pin: pin,
            renderedActions: rendered.actions)
        let parseRequest = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            bundle: reference, graphEvents: parseWork.appendingPathComponent("events.jsonl"),
            traceOutput: parseWork.appendingPathComponent("counterexample.json"),
            workingDirectory: parseWork, finiteGraphCase: referenceCase, runID: UUID(),
            timeout: timeout, invocation: .propertyCheck, referenceArtifacts: tools.artifacts)
        let configuration = try TLCReferenceConfiguration.parse(
            parseRequest, checking: rendered.checkNames)
        let names = configuration.invariants + configuration.properties
        guard Set(names).count == names.count,
              Set(configuration.invariants).isSubset(of: rendered.invariantNames.union(rendered.reachabilityNames)),
              Set(configuration.properties).isSubset(of: rendered.temporalNames.union(rendered.refinementNames)),
              Set(names).isSubset(of: rendered.checkNames) else {
            throw UpstreamTLCParityError.configurationMismatch(id)
        }

        if decisive {
            var generatedResults: [String: ValidationVerdict] = [:]
            var referenceResults: [String: ValidationVerdict] = [:]
            var generatedDeadlock: ValidationVerdict?
            var referenceDeadlock: ValidationVerdict?
            if names.count == 1, let name = names.first {
                let generatedOutput = directory.appendingPathComponent("generated-decisive")
                let referenceOutput = directory.appendingPathComponent("reference-decisive")
                let generatedOutcome = try GeneratedTLCOracle.run(
                    bundle: rendered.tlaBundle(checking: [name],
                        checkDeadlock: configuration.checksDeadlock), id: id,
                    maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
                    workRoot: work, retained: generatedOutput, invocation: .propertyCheck,
                    renderedActions: rendered.actions, process: process)
                let referenceBundle = try rendered.referenceBundle(checking: [name],
                    checkDeadlock: configuration.checksDeadlock,
                    declarations: configuration.declarations, in: reference)
                let referenceOutcome = try GeneratedTLCOracle.run(
                    bundle: referenceBundle, id: id,
                    maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
                    workRoot: work, retained: referenceOutput, invocation: .propertyCheck,
                    renderedActions: rendered.actions, process: process)
                if generatedOutcome == .deadlock { generatedDeadlock = .violated }
                else { generatedResults[name] = try GeneratedTLCOracle.verdict(
                    for: name, outcome: generatedOutcome, rendered: rendered, retained: generatedOutput) }
                if referenceOutcome == .deadlock { referenceDeadlock = .violated }
                else { referenceResults[name] = try GeneratedTLCOracle.verdict(
                    for: name, outcome: referenceOutcome, rendered: rendered, retained: referenceOutput) }
            } else {
                for name in names.sorted() {
                    let generatedBundles = try rendered.temporalObligationBundles(checking: name)
                        ?? [rendered.tlaBundle(checking: [name], checkDeadlock: false)]
                    generatedResults[name] = try check(name: name, bundles: generatedBundles, id: id,
                        maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
                        work: work, output: directory.appendingPathComponent("generated-\(name)"),
                        rendered: rendered, process: process)
                    let referenceBundle = try rendered.referenceBundle(checking: [name],
                        checkDeadlock: false, declarations: configuration.declarations, in: reference)
                    referenceResults[name] = try check(name: name, bundles: [referenceBundle], id: id,
                        maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
                        work: work, output: directory.appendingPathComponent("reference-\(name)"),
                        rendered: rendered, process: process)
                }
            }
            let decisiveResult = generatedResults.values.contains(.violated)
                || generatedResults.values.contains(.reached) || generatedDeadlock == .violated
            let difference: String? = if generatedResults != referenceResults
                || generatedDeadlock != referenceDeadlock {
                "selected property or deadlock verdict"
            } else if !decisiveResult {
                "declared decisive counterexample absent"
            } else {
                nil
            }
            let report = UpstreamTLCParityReport(
                schema: "swifttla.upstream-tlc-parity", caseID: id,
                result: difference == nil ? "exact" : "different",
                graphCompared: false, difference: difference,
                generatedProperties: generatedResults, referenceProperties: referenceResults,
                referenceGraphDerivedProperties: nil,
                generatedDeadlock: generatedDeadlock, referenceDeadlock: referenceDeadlock,
                deadlockSelected: configuration.checksDeadlock)
            try write(report, to: directory)
            return report
        }

        let compilerAssertions = rendered.checkNames.subtracting(names)
        guard compilerAssertions.isSubset(of: rendered.invariantNames),
              compilerAssertions.allSatisfy({ $0.hasPrefix("__pcal_assert_")
                  || $0.hasPrefix("__step_assert_") }) else {
            throw UpstreamTLCParityError.configurationMismatch(id)
        }
        let referenceGraphChecks = Set(configuration.invariants)
        let generatedGraphChecks = referenceGraphChecks.union(compilerAssertions)
        let generatedGraphBundle = try rendered.tlaBundle(
            checking: generatedGraphChecks,
            checkDeadlock: configuration.checksDeadlock)
        let referenceGraphBundle = try rendered.referenceBundle(
            checking: referenceGraphChecks,
            checkDeadlock: configuration.checksDeadlock,
            declarations: configuration.declarations, in: reference)
        var generatedGraphOutput = directory.appendingPathComponent("generated-graph")
        var referenceGraphOutput = directory.appendingPathComponent("reference-graph")
        let generatedCheckingOutcome: TLCExecutionOutcome
        if let generatedOracle, try reuseGeneratedGraph(
                from: generatedOracle, to: generatedGraphOutput, id: id,
                bundle: generatedGraphBundle, pin: pin) {
            generatedCheckingOutcome = .completed
        } else {
            generatedCheckingOutcome = try GeneratedTLCOracle.run(
                bundle: generatedGraphBundle, id: id, maximumStates: maximumStates, timeout: timeout,
                tools: tools, pin: pin, workRoot: work, retained: generatedGraphOutput,
                invocation: .finiteGraph, renderedActions: rendered.actions, process: process)
        }
        let referenceCheckingOutcome = try GeneratedTLCOracle.run(
            bundle: referenceGraphBundle, id: id, maximumStates: maximumStates, timeout: timeout,
            tools: tools, pin: pin, workRoot: work, retained: referenceGraphOutput,
            invocation: .finiteGraph, renderedActions: rendered.actions, process: process)
        for outcome in [generatedCheckingOutcome, referenceCheckingOutcome] {
            guard outcome == .completed || outcome == .safetyViolation || outcome == .deadlock else {
                throw UpstreamTLCParityError.invalidOutcome("\(id): \(outcome)")
            }
        }
        var generatedOutcome = generatedCheckingOutcome
        var referenceOutcome = referenceCheckingOutcome
        if generatedOutcome != .completed {
            generatedGraphOutput = directory.appendingPathComponent("generated-full-graph")
            generatedOutcome = try GeneratedTLCOracle.run(
                bundle: rendered.tlaBundle(checking: [], checkDeadlock: false), id: id,
                maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
                workRoot: work, retained: generatedGraphOutput, invocation: .finiteGraph,
                renderedActions: rendered.actions, process: process)
        }
        if referenceOutcome != .completed {
            referenceGraphOutput = directory.appendingPathComponent("reference-full-graph")
            referenceOutcome = try GeneratedTLCOracle.run(
                bundle: rendered.referenceBundle(checking: [], checkDeadlock: false,
                    declarations: configuration.declarations, in: reference), id: id,
                maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
                workRoot: work, retained: referenceGraphOutput, invocation: .finiteGraph,
                renderedActions: rendered.actions, process: process)
        }
        let generatedComplete = generatedOutcome == .completed
        let referenceComplete = referenceOutcome == .completed
        var generatedResults: [String: ValidationVerdict] = [:]
        var referenceResults: [String: ValidationVerdict] = [:]
        for name in names.sorted() {
            let generated: ValidationVerdict
            if generatedCheckingOutcome == .completed && rendered.invariantNames.contains(name) {
                generated = .satisfied
            } else {
                let bundles = try rendered.temporalObligationBundles(checking: name)
                    ?? [rendered.tlaBundle(checking: [name], checkDeadlock: false)]
                generated = try check(name: name, bundles: bundles, id: id,
                    maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
                    work: work, output: directory.appendingPathComponent("generated-\(name)"),
                    rendered: rendered, process: process)
            }
            let upstream: ValidationVerdict
            if referenceCheckingOutcome == .completed && rendered.invariantNames.contains(name) {
                upstream = .satisfied
            } else {
                let bundle = try rendered.referenceBundle(checking: [name],
                    checkDeadlock: false, declarations: configuration.declarations, in: reference)
                upstream = try check(name: name, bundles: [bundle], id: id,
                    maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
                    work: work, output: directory.appendingPathComponent("reference-\(name)"),
                    rendered: rendered, process: process)
            }
            generatedResults[name] = generated
            referenceResults[name] = upstream
        }

        let generatedDeadlock: ValidationVerdict?
        let referenceDeadlock: ValidationVerdict?
        if configuration.checksDeadlock {
            generatedDeadlock = try deadlockVerdict(
                graphOutcome: generatedCheckingOutcome, rendered: rendered, reference: nil,
                declarations: configuration.declarations, id: id, maximumStates: maximumStates,
                timeout: timeout, tools: tools, pin: pin, work: work,
                output: directory.appendingPathComponent("generated-deadlock"), process: process)
            referenceDeadlock = try deadlockVerdict(
                graphOutcome: referenceCheckingOutcome, rendered: rendered, reference: reference,
                declarations: configuration.declarations, id: id, maximumStates: maximumStates,
                timeout: timeout, tools: tools, pin: pin, work: work,
                output: directory.appendingPathComponent("reference-deadlock"), process: process)
        } else {
            generatedDeadlock = nil
            referenceDeadlock = nil
        }

        var difference: String?
        if generatedResults != referenceResults || generatedDeadlock != referenceDeadlock {
            difference = "selected property or deadlock verdict"
        }
        let graphCompared = generatedComplete && referenceComplete
        if difference == nil && !graphCompared {
            difference = "exhaustive configuration stopped early"
        }
        if difference == nil && graphCompared {
            difference = try ValidationEvidenceComparison.compareTLCGraphs(
                caseID: id,
                generated: generatedGraphOutput.appendingPathComponent("graph-events.bin.gz"),
                reference: referenceGraphOutput.appendingPathComponent("graph-events.bin.gz"),
                actions: rendered.actions, in: directory, spoolExecutable: spoolExecutable)
        }
        var graphDerived: [String] = []
        if difference == nil && graphCompared {
            guard generatedCheckingOutcome == .completed else {
                throw UpstreamTLCParityError.invalidOutcome("generated assertion check: \(id)")
            }
            for name in compilerAssertions {
                generatedResults[name] = .satisfied
                referenceResults[name] = .satisfied
            }
            graphDerived = compilerAssertions.sorted()
        }
        let report = UpstreamTLCParityReport(
            schema: "swifttla.upstream-tlc-parity", caseID: id,
            result: difference == nil ? "exact" : "different",
            graphCompared: graphCompared, difference: difference,
            generatedProperties: generatedResults, referenceProperties: referenceResults,
            referenceGraphDerivedProperties: graphDerived,
            generatedDeadlock: generatedDeadlock, referenceDeadlock: referenceDeadlock,
            deadlockSelected: configuration.checksDeadlock)
        try write(report, to: directory)
        return report
    }

    /// A cache hit retains TLC's output, not the comparator's previous verdict.
    package static func recompareCached(
        id: String, decisive: Bool, actions: [RenderedAction], in directory: URL,
        spoolExecutable: URL? = nil
    ) throws -> UpstreamTLCParityReport {
        let previous = try JSONDecoder().decode(UpstreamTLCParityReport.self,
            from: Data(contentsOf: directory.appendingPathComponent("comparison.json")))
        let decisiveResult = previous.generatedProperties.values.contains(.violated)
            || previous.generatedProperties.values.contains(.reached)
            || previous.generatedDeadlock == .violated
        guard previous.schema == "swifttla.upstream-tlc-parity", previous.caseID == id,
              previous.result == "exact", previous.difference == nil,
              previous.graphCompared != decisive,
              previous.generatedProperties == previous.referenceProperties,
              previous.generatedDeadlock == previous.referenceDeadlock,
              (previous.deadlockSelected || previous.generatedDeadlock == nil),
              (!previous.deadlockSelected || decisive || previous.generatedDeadlock != nil),
              (!decisive || decisiveResult) else {
            throw UpstreamTLCParityError.invalidOutcome("cached upstream evidence: \(id)")
        }
        if decisive { return previous }

        func report(_ difference: String?) -> UpstreamTLCParityReport {
            UpstreamTLCParityReport(
                schema: previous.schema, caseID: id,
                result: difference == nil ? "exact" : "different",
                graphCompared: true, difference: difference,
                generatedProperties: previous.generatedProperties,
                referenceProperties: previous.referenceProperties,
                referenceGraphDerivedProperties: previous.referenceGraphDerivedProperties,
                generatedDeadlock: previous.generatedDeadlock,
                referenceDeadlock: previous.referenceDeadlock,
                deadlockSelected: previous.deadlockSelected)
        }

        // A failed replay must not leave a previously exact verdict behind.
        try write(report("cached graph comparison incomplete"), to: directory)
        func graph(_ side: String) -> URL {
            let full = directory.appendingPathComponent("\(side)-full-graph")
            let retained = FileManager.default.fileExists(atPath: full.path)
                ? full : directory.appendingPathComponent("\(side)-graph")
            return retained.appendingPathComponent("graph-events.bin.gz")
        }
        let difference = try ValidationEvidenceComparison.compareTLCGraphs(
            caseID: id, generated: graph("generated"), reference: graph("reference"),
            actions: actions, in: directory, spoolExecutable: spoolExecutable)
        let refreshed = report(difference)
        try write(refreshed, to: directory)
        return refreshed
    }

    /// Diagnostic replay of two completed TLC graphs; selected verdicts remain separate.
    package static func compareRetainedGraphs(
        id: String, actions: [RenderedAction], in directory: URL, to output: URL,
        spoolExecutable: URL? = nil
    ) throws -> String? {
        try ValidationEvidenceComparison.compareTLCGraphs(
            caseID: id,
            generated: try completedRetainedGraph("generated", id: id, in: directory),
            reference: try completedRetainedGraph("reference", id: id, in: directory),
            actions: actions, in: output, spoolExecutable: spoolExecutable)
    }

    private static func completedRetainedGraph(_ side: String, id: String, in directory: URL) throws -> URL {
        for name in ["\(side)-full-graph", "\(side)-graph"] {
            let root = directory.appendingPathComponent(name)
            let graph = root.appendingPathComponent("graph-events.bin.gz")
            guard FileManager.default.fileExists(atPath: graph.path) else { continue }
            let process = try JSONSerialization.jsonObject(with:
                Data(contentsOf: root.appendingPathComponent("tlc-process.json"))) as? [String: Any]
            guard let invocation = process?["invocation"] as? [String: Any],
                  invocation["exitStatus"] as? Int == 0,
                  process?["caseID"] as? String == id else {
                throw UpstreamTLCParityError.invalidOutcome("retained TLC graph: \(name)")
            }
            return graph
        }
        throw UpstreamTLCParityError.invalidOutcome("missing retained TLC graph: \(side)")
    }

    package static func reuseGeneratedGraph(
        from oracle: URL, to output: URL, id: String,
        bundle: TLAModuleBundle, pin: TLCReferencePin
    ) throws -> Bool {
        let report = try JSONDecoder().decode(GeneratedTLCOracleReport.self,
            from: Data(contentsOf: oracle.appendingPathComponent("oracle.json")))
        let identity = try GeneratedTLCOracle.inputIdentity(
            bundle: bundle, pin: pin, arguments: ["-workers", "1", "-fp", "1"])
        guard report.schema == "swifttla.generated-tlc-oracle",
              report.caseID == id, report.graphComplete else {
            throw UpstreamTLCParityError.invalidOutcome("cached generated oracle identity: \(id)")
        }
        guard report.graphInputSHA256 == identity else { return false }
        let retained = oracle.appendingPathComponent("tlc-graph")
        let receipt = try JSONSerialization.jsonObject(with:
            Data(contentsOf: retained.appendingPathComponent("tlc-process.json"))) as? [String: Any]
        let expectedInputs = Dictionary(uniqueKeysWithValues:
            bundleInputJSON(bundle).map { ($0["file"]!, $0["sha256"]!) })
        let inputs = receipt?["inputs"] as? [[String: String]]
        let pairs = inputs?.compactMap { input -> (String, String)? in
            guard input.count == 2, let file = input["file"], let hash = input["sha256"] else {
                return nil
            }
            return (file, hash)
        }
        let invocation = receipt?["invocation"] as? [String: Any]
        let arguments = invocation?["arguments"] as? [String]
        let toolPin = receipt?["toolPin"] as? [String: Any]
        let expectedPin: [String: Any] = [
            "tag": pin.tag, "commit": pin.commit,
            "jarSHA256": pin.jarSHA256, "javaDistribution": pin.javaDistribution,
            "javaVersion": pin.javaVersion, "javaArchiveSHA256": pin.javaArchiveSHA256,
            "bridgeClass": pin.bridgeClass, "bridgeSourceHashes": pin.bridgeSourceHashes,
            "bridgeBinarySHA256": pin.bridgeBinarySHA256
        ]
        guard receipt?["caseID"] as? String == id,
              receipt?["configuration"] as? String == bundle.cfg,
              invocation?["exitStatus"] as? Int == 0,
              let inputs, let pairs, pairs.count == inputs.count,
              Set(pairs.map(\.0)).count == pairs.count,
              Dictionary(uniqueKeysWithValues: pairs) == expectedInputs,
              let arguments,
              arguments.contains("class,\(pin.bridgeClass)"),
              zip(arguments, arguments.dropFirst()).contains(where: {
                  $0.0 == "-workers" && $0.1 == "1"
              }),
              zip(arguments, arguments.dropFirst()).contains(where: {
                  $0.0 == "-fp" && $0.1 == "1"
              }),
              let toolPin,
              try JSONSerialization.data(withJSONObject: toolPin, options: [.sortedKeys])
                  == JSONSerialization.data(withJSONObject: expectedPin, options: [.sortedKeys]) else {
            throw UpstreamTLCParityError.invalidOutcome("cached generated oracle receipt: \(id)")
        }
        let origin = try JSONSerialization.jsonObject(with:
            Data(contentsOf: oracle.appendingPathComponent("evidence-origin.json"))) as? [String: Any]
        guard let sourceSHA = origin?["sourceSHA"] as? String,
              sourceSHA.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil,
              let runID = origin?["originRunID"] as? String, !runID.isEmpty,
              let cacheKey = origin?["cacheKey"] as? String, !cacheKey.isEmpty else {
            throw UpstreamTLCParityError.invalidOutcome("cached generated oracle origin: \(id)")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        for source in try FileManager.default.contentsOfDirectory(
            at: retained, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) {
            let destination = output.appendingPathComponent(source.lastPathComponent)
            if source.lastPathComponent == "graph-events.bin.gz" {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw UpstreamTLCParityError.invalidOutcome("cached generated oracle graph: \(id)")
                }
                do { try FileManager.default.linkItem(at: source, to: destination) }
                catch { try FileManager.default.copyItem(at: source, to: destination) }
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        }
        try FileManager.default.copyItem(at: oracle.appendingPathComponent("oracle.json"),
            to: output.appendingPathComponent("oracle.json"))
        try FileManager.default.copyItem(at: oracle.appendingPathComponent("evidence-origin.json"),
            to: output.appendingPathComponent("evidence-origin.json"))
        return true
    }

    private static func write(_ report: UpstreamTLCParityReport, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
    }

    private static func check(
        name: String, bundles: [TLAModuleBundle], id: String,
        maximumStates: Int, timeout: TimeInterval, tools: ResolvedTLCToolchain,
        pin: TLCReferencePin, work: URL, output: URL,
        rendered: RenderedSpecification, process: TLCProcessAdapter
    ) throws -> ValidationVerdict {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        var verdicts: [ValidationVerdict] = []
        for (index, bundle) in bundles.enumerated() {
            let retained = output.appendingPathComponent("obligation-\(index)")
            let outcome = try GeneratedTLCOracle.run(
                bundle: bundle, id: id, maximumStates: maximumStates, timeout: timeout,
                tools: tools, pin: pin, workRoot: work, retained: retained,
                invocation: .propertyCheck, renderedActions: rendered.actions, process: process)
            verdicts.append(try GeneratedTLCOracle.verdict(for: name, outcome: outcome,
                rendered: rendered, retained: retained))
        }
        if rendered.reachabilityNames.contains(name) {
            return verdicts.contains(.reached) ? .reached : .unreachable
        }
        return verdicts.contains(.violated) ? .violated : .satisfied
    }

    private static func deadlockVerdict(
        graphOutcome: TLCExecutionOutcome, rendered: RenderedSpecification,
        reference: TLAModuleBundle?, declarations: String, id: String,
        maximumStates: Int, timeout: TimeInterval, tools: ResolvedTLCToolchain,
        pin: TLCReferencePin, work: URL, output: URL, process: TLCProcessAdapter
    ) throws -> ValidationVerdict {
        if graphOutcome == .completed { return .satisfied }
        if graphOutcome == .deadlock { return .violated }
        let bundle = try reference.map {
            try rendered.referenceBundle(checking: [], checkDeadlock: true,
                declarations: declarations, in: $0)
        } ?? rendered.tlaBundle(checking: [], checkDeadlock: true)
        return try check(name: "deadlock", bundles: [bundle], id: id,
            maximumStates: maximumStates, timeout: timeout, tools: tools, pin: pin,
            work: work, output: output, rendered: rendered, process: process)
    }
}
