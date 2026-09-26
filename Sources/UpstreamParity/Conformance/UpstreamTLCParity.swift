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
    package let generatedDeadlock: ValidationVerdict?
    package let referenceDeadlock: ValidationVerdict?
}

package enum UpstreamTLCParityError: Error, Equatable {
    case inputMismatch(String)
    case configurationMismatch(String)
    case invalidOutcome(String)
}

/// The upstream comparison runs TLC on both module bundles. It never invokes
/// the Swift machine or native checker.
package enum UpstreamTLCParity {
    package static func run(
        id: String, rendered: RenderedSpecification, reference: TLAModuleBundle,
        expectedModuleSHA256: String, expectedCFGSHA256: String,
        maximumStates: Int, timeout: TimeInterval, decisive: Bool,
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

        let graphChecks = Set(configuration.invariants).intersection(rendered.invariantNames)
        let generatedGraphBundle = try rendered.tlaBundle(
            checking: graphChecks,
            checkDeadlock: configuration.checksDeadlock)
        let referenceGraphBundle = try rendered.referenceBundle(
            checking: graphChecks,
            checkDeadlock: configuration.checksDeadlock,
            declarations: configuration.declarations, in: reference)
        let generatedGraphOutput = directory.appendingPathComponent("generated-graph")
        let referenceGraphOutput = directory.appendingPathComponent("reference-graph")
        let generatedOutcome = try GeneratedTLCOracle.run(
            bundle: generatedGraphBundle, id: id, maximumStates: maximumStates, timeout: timeout,
            tools: tools, pin: pin, workRoot: work, retained: generatedGraphOutput,
            invocation: .finiteGraph, renderedActions: rendered.actions, process: process)
        let referenceOutcome = try GeneratedTLCOracle.run(
            bundle: referenceGraphBundle, id: id, maximumStates: maximumStates, timeout: timeout,
            tools: tools, pin: pin, workRoot: work, retained: referenceGraphOutput,
            invocation: .finiteGraph, renderedActions: rendered.actions, process: process)
        let generatedComplete = generatedOutcome == .completed
        let referenceComplete = referenceOutcome == .completed
        for outcome in [generatedOutcome, referenceOutcome] {
            guard outcome == .completed || outcome == .safetyViolation || outcome == .deadlock else {
                throw UpstreamTLCParityError.invalidOutcome("\(id): \(outcome)")
            }
        }
        var generatedResults: [String: ValidationVerdict] = [:]
        var referenceResults: [String: ValidationVerdict] = [:]
        for name in names.sorted() {
            let generated: ValidationVerdict
            if generatedComplete && rendered.invariantNames.contains(name) {
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
            if referenceComplete && rendered.invariantNames.contains(name) {
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
                graphOutcome: generatedOutcome, rendered: rendered, reference: nil,
                declarations: configuration.declarations, id: id, maximumStates: maximumStates,
                timeout: timeout, tools: tools, pin: pin, work: work,
                output: directory.appendingPathComponent("generated-deadlock"), process: process)
            referenceDeadlock = try deadlockVerdict(
                graphOutcome: referenceOutcome, rendered: rendered, reference: reference,
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
        if difference == nil && !decisive && !graphCompared {
            difference = "exhaustive configuration stopped early"
        }
        if difference == nil && graphCompared {
            difference = try ValidationEvidenceComparison.compareTLCGraphs(
                caseID: id,
                generated: generatedGraphOutput.appendingPathComponent("graph-events.jsonl"),
                reference: referenceGraphOutput.appendingPathComponent("graph-events.jsonl"),
                actions: rendered.actions, in: directory)
        }
        let report = UpstreamTLCParityReport(
            schema: "swifttla.upstream-tlc-parity", caseID: id,
            result: difference == nil ? "exact" : "different",
            graphCompared: graphCompared, difference: difference,
            generatedProperties: generatedResults, referenceProperties: referenceResults,
            generatedDeadlock: generatedDeadlock, referenceDeadlock: referenceDeadlock)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
        return report
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
