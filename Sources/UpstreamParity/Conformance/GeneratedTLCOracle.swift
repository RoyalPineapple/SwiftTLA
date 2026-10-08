import Foundation
import SwiftTLA

package struct GeneratedTLCOracleReport: Codable, Sendable {
    package let schema: String
    package let caseID: String
    package let scenario: String
    package let maximumStates: Int
    package let graphComplete: Bool
    package let graphInputSHA256: String
    package let properties: [String: ValidationVerdict]
    package let deadlock: ValidationVerdict?
    package let deadlockSelected: Bool
    package let postconditionName: String?
    package let postcondition: ValidationVerdict?
}

/// TLC receives only generated TLA+ and never reads native checker results.
package enum GeneratedTLCOracle {
    package enum Error: Swift.Error, Equatable {
        case checkingMismatch
        case invalidOutcome(String)
        case unsafeModuleName(String)
    }

    /// Identifies every TLC input used by a scenario, independent of the Swift source SHA.
    /// An unchanged generated machine can reuse its previously captured TLC evidence.
    package static func cacheKey<Scenario: ModelValidationScenario>(
        scenario: Scenario, id: String, maximumStates: Int, pin: TLCReferencePin
    ) throws -> String {
        let rendered = try scenario.render()
        let names = scenario.formalPropertyNames
        let selected = try Set(scenario.checking.properties.map { property -> String in
            guard let name = names[property] else { throw Error.checkingMismatch }
            return name
        })
        guard names == Scenario.Machine.formalPropertyNames,
              names.values.allSatisfy({
                  $0.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
              }),
              selected == rendered.checkNames,
              scenario.checking.properties == Set(scenario.expectations.keys),
              scenario.checking.checkDeadlock == rendered.checksDeadlock,
              scenario.postconditionName == rendered.postconditionName,
              (scenario.postconditionExpectation != nil) == (scenario.postconditionName != nil),
              (scenario.deadlockExpectation != nil) == rendered.checksDeadlock,
              scenario.behavior == rendered.behavior else {
            throw Error.checkingMismatch
        }
        if case .simulation(let traces, let maximumDepth) = scenario.checkingMode {
            guard selected.count == 1, selected.isSubset(of: rendered.invariantNames),
                  rendered.postconditionName == nil else {
                throw Error.checkingMismatch
            }
            let identity: [String: Any] = [
                "schema": "swifttla.simulation-oracle-cache-key-v1",
                "caseID": id,
                "scenario": scenario.name,
                "maximumStates": maximumStates,
                "input": try inputIdentity(
                    bundle: rendered.tlaBundle(checking: selected,
                        checkDeadlock: rendered.checksDeadlock),
                    pin: pin, arguments: simulationArguments(traces: traces, maximumDepth: maximumDepth),
                    invocation: .propertyCheck),
                "actions": rendered.actions.sorted {
                    ($0.sourceInvocationName, $0.renderedName) < ($1.sourceInvocationName, $1.renderedName)
                }.map { ["invocation": $0.sourceInvocationName, "rendered": $0.renderedName] }
            ]
            return SHA256.hex(try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys]))
        }
        let graphChecks = selected.intersection(rendered.invariantNames.union(rendered.reachabilityNames))
        if scenario.checkingMode == .decisiveCounterexample,
           graphChecks.count != 1 || selected != graphChecks {
            throw Error.checkingMismatch
        }
        if scenario.checkingMode == .decisiveCounterexample,
           rendered.postconditionName != nil { throw Error.checkingMismatch }
        let graph = try inputIdentity(
            bundle: rendered.tlaBundle(checking: graphChecks, checkDeadlock: rendered.checksDeadlock),
            pin: pin, arguments: ["-workers", "1", "-fp", "1"], invocation: .finiteGraph)
        let fullGraph = try inputIdentity(
            bundle: rendered.tlaBundle(checking: [], checkDeadlock: false),
            pin: pin, arguments: ["-workers", "1", "-fp", "1"], invocation: .finiteGraph)
        var checks: [[String: Any]] = []
        for name in selected.sorted() {
            let bundles = try rendered.temporalObligationBundles(checking: name)
                ?? [rendered.tlaBundle(checking: [name], checkDeadlock: false)]
            checks.append(["name": name, "inputs": try bundles.map {
                try inputIdentity(bundle: $0, pin: pin,
                    arguments: ["-workers", "1", "-fp", "1"], invocation: .propertyCheck)
            }])
        }
        let deadlockInput: String? = rendered.checksDeadlock
            ? try inputIdentity(bundle: rendered.tlaBundle(checking: [], checkDeadlock: true),
                pin: pin, arguments: ["-workers", "1", "-fp", "1"], invocation: .propertyCheck)
            : nil
        let postconditionInput: String? = try rendered.postconditionName.map { name in
            try inputIdentity(bundle: rendered.tlaBundle(checking: [], checkDeadlock: false,
                postcondition: name), pin: pin,
                arguments: ["-workers", "1", "-fp", "1"], invocation: .propertyCheck)
        }
        let identity: [String: Any] = [
            "schema": "swifttla.oracle-cache-key-v4",
            "caseID": id,
            "scenario": scenario.name,
            "checkingMode": scenario.checkingMode.rawValue,
            "maximumStates": maximumStates,
            "graph": graph,
            "fullGraph": fullGraph,
            "checks": checks,
            "deadlockInput": deadlockInput ?? NSNull(),
            "postconditionInput": postconditionInput ?? NSNull(),
            "actions": rendered.actions.sorted {
                ($0.sourceInvocationName, $0.renderedName) < ($1.sourceInvocationName, $1.renderedName)
            }.map {
                ["invocation": $0.sourceInvocationName, "rendered": $0.renderedName]
            }
        ]
        return SHA256.hex(try JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys]))
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
                  $0.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
              }),
              selected == rendered.checkNames,
              scenario.checking.properties == Set(scenario.expectations.keys),
              scenario.checking.checkDeadlock == rendered.checksDeadlock,
              scenario.postconditionName == rendered.postconditionName,
              (scenario.postconditionExpectation != nil) == (scenario.postconditionName != nil),
              (scenario.deadlockExpectation != nil) == rendered.checksDeadlock,
              scenario.behavior == rendered.behavior else { throw Error.checkingMismatch }

        if case .simulation(let traces, let maximumDepth) = scenario.checkingMode {
            guard selected.count == 1, let name = selected.first,
                  rendered.invariantNames.contains(name), rendered.postconditionName == nil else {
                throw Error.checkingMismatch
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let bundle = try rendered.tlaBundle(checking: selected,
                checkDeadlock: rendered.checksDeadlock)
            try retainGeneratedInputs(bundle, in: directory.appendingPathComponent("generated"))
            let work = directory.appendingPathComponent("work")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
            let arguments = simulationArguments(traces: traces, maximumDepth: maximumDepth)
            let retained = directory.appendingPathComponent("tlc-graph")
            let outcome = try run(bundle: bundle, id: id, maximumStates: maximumStates,
                timeout: timeout, tools: tools, pin: pin, workRoot: work, retained: retained,
                invocation: .propertyCheck, renderedActions: rendered.actions, process: process,
                arguments: arguments)
            let verdict: ValidationVerdict
            switch outcome {
            case .completed: verdict = .unavailable
            case .safetyViolation:
                let stdout = try String(contentsOf: retained.appendingPathComponent("logs/tlc.stdout.log"),
                    encoding: .utf8)
                guard stdout.split(whereSeparator: \.isNewline).contains(where: {
                    $0 == "Error: Invariant \(name) is violated."
                        || $0 == "Error: Invariant \(name) is violated by the initial state:"
                }) else { throw Error.invalidOutcome("unidentified simulated invariant violation") }
                verdict = try Self.verdict(for: name, outcome: outcome,
                    rendered: rendered, retained: retained)
            default: throw Error.invalidOutcome("simulation pass: \(outcome)")
            }
            let report = GeneratedTLCOracleReport(
                schema: "swifttla.generated-tlc-oracle", caseID: id, scenario: scenario.name,
                maximumStates: maximumStates, graphComplete: false,
                graphInputSHA256: try inputIdentity(bundle: bundle, pin: pin,
                    arguments: arguments, invocation: .propertyCheck),
                properties: [name: verdict], deadlock: rendered.checksDeadlock ? .unavailable : nil,
                deadlockSelected: rendered.checksDeadlock,
                postconditionName: nil, postcondition: nil)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(report).write(to: directory.appendingPathComponent("oracle.json"), options: .atomic)
            return report
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let graphChecks = selected.intersection(rendered.invariantNames.union(rendered.reachabilityNames))
        let decisive = scenario.checkingMode == .decisiveCounterexample
        guard !decisive || (graphChecks.count == 1 && selected == graphChecks) else {
            throw Error.checkingMismatch
        }
        guard !decisive || rendered.postconditionName == nil else { throw Error.checkingMismatch }
        let graphBundle = try rendered.tlaBundle(checking: graphChecks,
                                                 checkDeadlock: rendered.checksDeadlock)
        try retainGeneratedInputs(graphBundle, in: directory.appendingPathComponent("generated"))
        let work = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        let checkedRetained = directory.appendingPathComponent("tlc-check")
        let checkedOutcome = try run(bundle: graphBundle, id: id, maximumStates: maximumStates,
                                   timeout: timeout, tools: tools, pin: pin,
                                   workRoot: work, retained: checkedRetained,
                                   invocation: .finiteGraph, renderedActions: rendered.actions, process: process)
        guard checkedOutcome == .completed || checkedOutcome == .safetyViolation
            || checkedOutcome == .deadlock else {
            throw Error.invalidOutcome("checked graph pass: \(checkedOutcome)")
        }
        let observedViolation: String?
        if checkedOutcome == .safetyViolation {
            let stdout = try String(contentsOf: checkedRetained.appendingPathComponent("logs/tlc.stdout.log"),
                encoding: .utf8)
            let errors = Set(stdout.split(whereSeparator: \.isNewline).map(String.init))
            let matches = graphChecks.filter { name in
                errors.contains("Error: Invariant \(name) is violated.")
                    || errors.contains("Error: Invariant \(name) is violated by the initial state:")
            }
            guard matches.count == 1 else { throw Error.invalidOutcome("unidentified graph violation") }
            observedViolation = matches.first
        } else {
            observedViolation = nil
        }
        if decisive, observedViolation == nil {
            throw Error.invalidOutcome("declared decisive safety witness absent")
        }

        let graphRetained = directory.appendingPathComponent("tlc-graph")
        let graphIdentity: String
        if decisive || checkedOutcome == .completed {
            try FileManager.default.moveItem(at: checkedRetained, to: graphRetained)
            graphIdentity = try inputIdentity(bundle: graphBundle, pin: pin,
                arguments: ["-workers", "1", "-fp", "1"], invocation: .finiteGraph)
        } else {
            let fullBundle = try rendered.tlaBundle(checking: [], checkDeadlock: false)
            try FileManager.default.moveItem(
                at: directory.appendingPathComponent("generated"),
                to: directory.appendingPathComponent("checked-graph-generated"))
            try retainGeneratedInputs(fullBundle, in: directory.appendingPathComponent("generated"))
            graphIdentity = try inputIdentity(bundle: fullBundle, pin: pin,
                arguments: ["-workers", "1", "-fp", "1"], invocation: .finiteGraph)
            let fullOutcome = try run(bundle: fullBundle, id: id, maximumStates: maximumStates,
                timeout: timeout, tools: tools, pin: pin, workRoot: work, retained: graphRetained,
                invocation: .finiteGraph, renderedActions: rendered.actions, process: process)
            guard fullOutcome == .completed else {
                throw Error.invalidOutcome("full graph pass: \(fullOutcome)")
            }
        }

        var properties: [String: ValidationVerdict] = [:]
        for property in scenario.checking.properties.sorted(by: { names[$0]! < names[$1]! }) {
            let name = names[property]!
            let verdict: ValidationVerdict
            if name == observedViolation {
                verdict = try Self.verdict(for: name, outcome: checkedOutcome,
                    rendered: rendered, retained: decisive ? graphRetained : checkedRetained)
            } else if checkedOutcome == .completed && rendered.invariantNames.contains(name) {
                verdict = .satisfied
            } else if checkedOutcome == .completed && rendered.reachabilityNames.contains(name) {
                verdict = .unreachable
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
            properties[name] = verdict
        }

        let deadlock: ValidationVerdict?
        if rendered.checksDeadlock {
            if decisive { deadlock = .unavailable }
            else if checkedOutcome == .completed { deadlock = .satisfied }
            else if checkedOutcome == .deadlock {
                deadlock = try verdict(for: "deadlock", outcome: checkedOutcome,
                    rendered: rendered, retained: checkedRetained)
            } else {
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
        } else {
            deadlock = nil
        }

        let postcondition: ValidationVerdict?
        if let name = rendered.postconditionName {
            guard !decisive else { throw Error.checkingMismatch }
            let bundle = try rendered.tlaBundle(checking: [], checkDeadlock: false,
                postcondition: name)
            let retained = directory.appendingPathComponent("check-postcondition")
            try FileManager.default.createDirectory(at: retained, withIntermediateDirectories: false)
            try retainGeneratedInputs(bundle, in: retained.appendingPathComponent("generated"))
            let outcome = try run(bundle: bundle, id: id, maximumStates: maximumStates,
                timeout: timeout, tools: tools, pin: pin, workRoot: work,
                retained: retained.appendingPathComponent("tlc"), invocation: .propertyCheck,
                renderedActions: rendered.actions, process: process)
            postcondition = try postconditionVerdict(name: name, outcome: outcome,
                retained: retained.appendingPathComponent("tlc"))
        } else {
            postcondition = nil
        }

        let report = GeneratedTLCOracleReport(
            schema: "swifttla.generated-tlc-oracle", caseID: id, scenario: scenario.name,
            maximumStates: maximumStates,
            graphComplete: !decisive, graphInputSHA256: graphIdentity,
            properties: properties, deadlock: deadlock,
            deadlockSelected: rendered.checksDeadlock,
            postconditionName: rendered.postconditionName, postcondition: postcondition)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(report).write(to: directory.appendingPathComponent("oracle.json"), options: .atomic)
        return report
    }

    package static func run(
        bundle: TLAModuleBundle, id: String, maximumStates: Int, timeout: TimeInterval,
        tools: ResolvedTLCToolchain, pin: TLCReferencePin, workRoot: URL,
        retained: URL, invocation: TLCInvocationKind, renderedActions: [RenderedAction],
        process: TLCProcessAdapter, captureEvaluations: Bool = false,
        supplementalJar: PinnedTLCModuleJar? = nil,
        arguments: [String] = ["-workers", "1", "-fp", "1"]
    ) throws -> TLCExecutionOutcome {
        let work = workRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        let launch = try FiniteGraphCase(
            id: id, exploration: .init(maximumStateLimit: maximumStates, symmetryReduction: .disabled),
            moduleSHA256: SHA256.hex(Data(bundle.tla.utf8)),
            cfgSHA256: SHA256.hex(Data(bundle.cfg.utf8)),
            arguments: arguments, environment: [:], pin: pin,
            renderedActions: renderedActions)
        let request = TLCProcessRequest(
            javaExecutable: tools.java, jar: tools.jar, bridgeJar: tools.bridgeJar,
            supplementalJar: supplementalJar,
            bundle: bundle, graphEvents: work.appendingPathComponent("events.bin.gz"),
            traceOutput: work.appendingPathComponent("counterexample.json"),
            evaluationOutput: captureEvaluations ? work.appendingPathComponent("evaluations.bin") : nil,
            workingDirectory: work, finiteGraphCase: launch, runID: UUID(),
            timeout: timeout, invocation: invocation, referenceArtifacts: tools.artifacts)
        return try process.run(request, retainingIn: retained)
    }

    package static func simulationArguments(traces: Int, maximumDepth: Int) -> [String] {
        ["-simulate", "num=\(traces)", "-depth", "\(maximumDepth)", "-seed", "1"]
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

    package static func postconditionVerdict(name: String, outcome: TLCExecutionOutcome,
        retained: URL) throws -> ValidationVerdict {
        if outcome == .completed { return .satisfied }
        guard outcome == .assumptionViolation else {
            throw Error.invalidOutcome("postcondition: \(outcome)")
        }
        let stdout = try String(contentsOf: retained.appendingPathComponent("logs/tlc.stdout.log"),
            encoding: .utf8)
        let errors = stdout.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("Error:") }
        guard errors.count == 1,
              errors[0].hasPrefix("Error: Postcondition \(name) at "),
              errors[0].hasSuffix(" is false.") else {
            throw Error.invalidOutcome("unidentified postcondition violation")
        }
        return .violated
    }

    package static func retainGeneratedInputs(_ bundle: TLAModuleBundle, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        for file in bundle.files {
            guard file.name.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw Error.unsafeModuleName(file.name)
            }
            try Data(file.tla.utf8).write(to: directory.appendingPathComponent("\(file.name).tla"), options: .atomic)
        }
        try Data(bundle.cfg.utf8).write(to: directory.appendingPathComponent("\(bundle.root.name).cfg"), options: .atomic)
    }

    package static func inputIdentity(bundle: TLAModuleBundle, pin: TLCReferencePin,
        arguments: [String], invocation: TLCInvocationKind = .finiteGraph,
        captureEvaluations: Bool = false,
        supplementalJar: PinnedTLCModuleJar? = nil) throws -> String {
        let sources = bundle.files.sorted { $0.name < $1.name }.map {
            ["name": $0.name, "sha256": SHA256.hex(Data($0.tla.utf8))]
        }
        var input: [String: Any] = [
            "schema": "swifttla.tlc-oracle-input", "version": 1,
            "sources": sources, "cfgSHA256": SHA256.hex(Data(bundle.cfg.utf8)),
            "jarSHA256": pin.jarSHA256, "javaArchiveSHA256": pin.javaArchiveSHA256,
            "tlcTag": pin.tag, "tlcCommit": pin.commit,
            "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion,
            "bridgeClass": pin.bridgeClass, "bridgeBinarySHA256": pin.bridgeBinarySHA256,
            "bridgeSourceHashes": pin.bridgeSourceHashes, "arguments": arguments,
            "invocation": invocation == .finiteGraph ? "finite-graph" : "property-check"
        ]
        if captureEvaluations { input["captureEvaluations"] = true }
        if let supplementalJar { input["supplementalJarSHA256"] = supplementalJar.sha256 }
        let canonical = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        return SHA256.hex(canonical)
    }
}
