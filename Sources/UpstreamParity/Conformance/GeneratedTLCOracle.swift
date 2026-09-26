import Foundation
import SwiftTLA

package struct GeneratedTLCOracleReport: Codable, Sendable {
    package let schema: String
    package let caseID: String
    package let scenario: String
    package let graphComplete: Bool
    package let graphInputSHA256: String
    package let properties: [String: ValidationVerdict]
    package let deadlock: ValidationVerdict?
}

/// TLC receives only generated TLA+ and never reads native checker results.
package enum GeneratedTLCOracle {
    package enum Error: Swift.Error, Equatable {
        case checkingMismatch
        case invalidOutcome(String)
        case expectationMismatch(String)
        case unsafeModuleName(String)
    }

    package static func capture<Scenario: ModelValidationScenario>(
        scenario: Scenario, id: String, maximumStates: Int, timeout: TimeInterval,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin, to directory: URL,
        process: TLCProcessAdapter = TLCProcessAdapter()
    ) throws -> GeneratedTLCOracleReport {
        let rendered = try scenario.render()
        let names = scenario.formalPropertyNames
        let selected = try Set(scenario.checking.properties.map { property -> String in
            guard let name = names[property] else { throw Error.checkingMismatch }
            return name
        })
        guard names == Scenario.Machine.formalPropertyNames,
              names.values.allSatisfy({
                  $0.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil
              }),
              selected == rendered.checkNames,
              scenario.checking.properties == Set(scenario.expectations.keys),
              scenario.checking.checkDeadlock == rendered.checksDeadlock,
              (scenario.deadlockExpectation != nil) == rendered.checksDeadlock,
              scenario.behavior == rendered.behavior else { throw Error.checkingMismatch }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let graphBundle = try rendered.tlaBundle(checking: selected.intersection(rendered.invariantNames),
                                                 checkDeadlock: rendered.checksDeadlock)
        try retainGeneratedInputs(graphBundle, in: directory.appendingPathComponent("generated"))
        let graphIdentity = try inputIdentity(bundle: graphBundle, pin: pin,
                                              arguments: ["-workers", "1", "-fp", "1"])
        let work = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        let graphOutcome = try run(bundle: graphBundle, id: id, maximumStates: maximumStates,
                                   timeout: timeout, tools: tools, pin: pin,
                                   workRoot: work, retained: directory.appendingPathComponent("tlc-graph"),
                                   invocation: .finiteGraph, renderedActions: rendered.actions, process: process)
        let graphComplete = graphOutcome == .completed
        guard graphComplete || graphOutcome == .safetyViolation || graphOutcome == .deadlock else {
            throw Error.invalidOutcome("graph pass: \(graphOutcome)")
        }

        var properties: [String: ValidationVerdict] = [:]
        for property in scenario.checking.properties.sorted(by: { names[$0]! < names[$1]! }) {
            let name = names[property]!
            let verdict: ValidationVerdict
            if graphComplete && rendered.invariantNames.contains(name) {
                verdict = .satisfied
            } else {
                let selectedBundles = try rendered.temporalObligationBundles(checking: name)
                    ?? [rendered.tlaBundle(checking: [name], checkDeadlock: false)]
                var outcomes: [ValidationVerdict] = []
                for (index, bundle) in selectedBundles.enumerated() {
                    let suffix = selectedBundles.count == 1 ? "" : "-\(index)"
                    let retained = directory.appendingPathComponent("check-\(name)\(suffix)")
                    try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: false)
                    try retainGeneratedInputs(bundle, in: retained.appendingPathComponent("generated"))
                    let outcome = try run(bundle: bundle, id: id, maximumStates: maximumStates,
                                          timeout: timeout, tools: tools, pin: pin,
                                          workRoot: work, retained: retained.appendingPathComponent("tlc"),
                                          invocation: .propertyCheck, renderedActions: rendered.actions,
                                          process: process)
                    outcomes.append(try Self.verdict(for: name, outcome: outcome, rendered: rendered,
                                                retained: retained.appendingPathComponent("tlc")))
                }
                verdict = if rendered.reachabilityNames.contains(name) {
                    outcomes.contains(.reached) ? .reached : .unreachable
                } else {
                    outcomes.contains(.violated) ? .violated : .satisfied
                }
            }
            guard scenario.expectations[property].map({ accepts($0, verdict) }) == true else {
                throw Error.expectationMismatch(name)
            }
            properties[name] = verdict
        }

        let deadlock: ValidationVerdict?
        if rendered.checksDeadlock {
            if graphComplete { deadlock = .satisfied }
            else if graphOutcome == .deadlock { deadlock = .violated }
            else {
                let bundle = try rendered.tlaBundle(checking: [], checkDeadlock: true)
                let retained = directory.appendingPathComponent("check-deadlock")
                try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: false)
                try retainGeneratedInputs(bundle, in: retained.appendingPathComponent("generated"))
                let outcome = try run(bundle: bundle, id: id, maximumStates: maximumStates,
                                      timeout: timeout, tools: tools, pin: pin,
                                      workRoot: work, retained: retained.appendingPathComponent("tlc"),
                                      invocation: .propertyCheck, renderedActions: rendered.actions,
                                      process: process)
                deadlock = try verdict(for: "deadlock", outcome: outcome, rendered: rendered,
                                       retained: retained.appendingPathComponent("tlc"))
            }
            guard scenario.deadlockExpectation.map({ accepts($0, deadlock!) }) == true else {
                throw Error.expectationMismatch("deadlock")
            }
        } else {
            deadlock = nil
        }

        let report = GeneratedTLCOracleReport(
            schema: "swifttla.generated-tlc-oracle", caseID: id, scenario: scenario.name,
            graphComplete: graphComplete, graphInputSHA256: graphIdentity,
            properties: properties, deadlock: deadlock)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("oracle.json"), options: .atomic)
        return report
    }

    package static func run(
        bundle: TLAModuleBundle, id: String, maximumStates: Int, timeout: TimeInterval,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin, workRoot: URL,
        retained: URL, invocation: TLCInvocationKind, renderedActions: [RenderedAction],
        process: TLCProcessAdapter
    ) throws -> TLCExecutionOutcome {
        let work = workRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        let launch = try FiniteGraphCase(
            id: id, exploration: .init(maximumStateLimit: maximumStates, symmetryReduction: .disabled),
            moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)),
            cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
            arguments: ["-workers", "1", "-fp", "1"], environment: [:], pin: pin,
            renderedActions: renderedActions)
        let request = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            bundle: bundle, graphEvents: work.appendingPathComponent("events.jsonl"),
            traceOutput: work.appendingPathComponent("counterexample.json"),
            workingDirectory: work, finiteGraphCase: launch, runID: UUID(),
            timeout: timeout, invocation: invocation, referenceArtifacts: tools.artifacts)
        return try process.run(request, retainingIn: retained)
    }

    package static func verdict(for name: String, outcome: TLCExecutionOutcome,
        rendered: RenderedSpecification, retained: URL) throws -> ValidationVerdict {
        if outcome == .completed {
            return rendered.reachabilityNames.contains(name) ? .unreachable : .satisfied
        }
        if outcome == .temporalTautology && rendered.temporalNames.contains(name) {
            return .satisfied
        }
        let violated = if name == "deadlock" { outcome == .deadlock }
            else { outcome == .safetyViolation || outcome == .livenessViolation }
        guard violated else { throw Error.invalidOutcome("\(name): \(outcome)") }
        let trace = retained.appendingPathComponent("counterexample.json")
        guard FileManager.default.fileExists(atPath: trace.path),
              let data = try? Data(contentsOf: trace), !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw Error.invalidOutcome("\(name): missing counterexample")
        }
        return rendered.reachabilityNames.contains(name) ? .reached : .violated
    }

    private static func accepts(_ expected: ValidationExpectation, _ actual: ValidationVerdict) -> Bool {
        switch (expected, actual) {
        case (.satisfied, .satisfied), (.satisfied, .reached),
             (.violated, .violated), (.violated, .unreachable): true
        default: false
        }
    }

    private static func retainGeneratedInputs(_ bundle: TLAModuleBundle, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        for file in bundle.files {
            guard file.name.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw Error.unsafeModuleName(file.name)
            }
            try Data(file.tla.utf8).write(to: directory.appendingPathComponent("\(file.name).tla"), options: .atomic)
        }
        try Data(bundle.cfg.utf8).write(to: directory.appendingPathComponent("\(bundle.root.name).cfg"), options: .atomic)
    }

    package static func inputIdentity(bundle: TLAModuleBundle, pin: TLCReferencePin, arguments: [String]) throws -> String {
        let sources = bundle.files.sorted { $0.name < $1.name }.map {
            ["name": $0.name, "sha256": SHA256.hex(Data($0.tla.utf8))]
        }
        let input: [String: Any] = [
            "schema": "swifttla.tlc-oracle-input", "version": 1,
            "sources": sources, "cfgSHA256": SHA256.hex(Data(bundle.cfg.utf8)),
            "jarSHA256": pin.jarSHA256, "javaArchiveSHA256": pin.javaArchiveSHA256,
            "tlcTag": pin.tag, "tlcCommit": pin.commit,
            "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion,
            "bridgeClass": pin.bridgeClass, "bridgeBinarySHA256": pin.bridgeBinarySHA256,
            "bridgeSourceHashes": pin.bridgeSourceHashes, "arguments": arguments
        ]
        let canonical = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        return SHA256.hex(canonical)
    }
}
