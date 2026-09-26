import Foundation
import SwiftTLA

package struct TLCScenarioCheck: Sendable {
    private let properties: TLCPropertyCheck
    private let processAdapter: TLCProcessAdapter

    package init(processAdapter: TLCProcessAdapter = TLCProcessAdapter()) {
        properties = TLCPropertyCheck(processAdapter: processAdapter)
        self.processAdapter = processAdapter
    }

    package func runReference(_ scenario: NativeScenarioRun, request: TLCProcessRequest,
        configuration: TLCReferenceConfiguration, in directory: URL) throws {
        try RetainedFiles.outputDirectory(directory, beneath: directory.deletingLastPathComponent())
        do {
            guard case .counterexample(let native) = scenario.native,
                  request.invocation == .propertyCheck,
                  request.finiteGraphCase.arguments == ["-workers", "1", "-fp", "1"] else {
                throw TLCPropertyCheckError.requestMismatch
            }
            try configuration.validateDecisiveCoverage(native.rendered)
            try request.validateDeclaredBundle()
            guard SHA256.hex(Data(request.bundle.tla.utf8)) == request.finiteGraphCase.moduleSHA256,
                  SHA256.hex(Data(request.bundle.cfg.utf8)) == request.finiteGraphCase.cfgSHA256 else {
                throw TLCPropertyCheckError.requestMismatch
            }
            try RetainedFiles.writeText(request.bundle.cfg, to: directory.appendingPathComponent("reference-original.cfg"))
            let reference = directory.appendingPathComponent("reference")
            let outcome = try processAdapter.run(request, retainingIn: reference)
            let comparison = try native.compare(
                data: Data(contentsOf: reference.appendingPathComponent("counterexample.json")), outcome: outcome,
                stdout: String(contentsOf: reference.appendingPathComponent("logs/tlc.stdout.log"), encoding: .utf8))
            try RetainedFiles.writeCanonical(comparison, to: reference.appendingPathComponent("property-comparison.json"))
            try scenario.validateCounterexample(comparison)
            let work = request.workingDirectory.appendingPathComponent(UUID().uuidString)
            try RetainedFiles.createDirectory(work, beneath: request.workingDirectory)
            defer { try? FileManager.default.removeItem(at: work) }
            let generated = try request.selecting(bundle: native.rendered.tlaBundle,
                work: work, runID: UUID(), invocation: .propertyCheck)
            try run(scenario, request: generated, in: directory.appendingPathComponent("generated"))
            struct Comparison: Encodable {
                let schema = "DecisiveConfigurationComparison"
                let completion = "decisive-counterexample"
                let graphCompared = false
                let result = "exact"
                let caseID: String
                let configurationSHA256: String
                let reference: PropertyComparison
            }
            try RetainedFiles.writeCanonical(Comparison(caseID: request.caseID,
                configurationSHA256: request.finiteGraphCase.cfgSHA256, reference: comparison),
                to: directory.appendingPathComponent("comparison.json"))
        } catch {
            try RetainedFiles.writeText(redactingSecrets(in: String(describing: error)),
                to: directory.appendingPathComponent("error.txt"))
            throw error
        }
    }

    package func run(_ scenario: NativeScenarioRun, request: TLCProcessRequest, in directory: URL) throws {
        try RetainedFiles.outputDirectory(directory, beneath: directory.deletingLastPathComponent())
        do {
            try RetainedFiles.writeCanonical(scenario.native.checks, to: directory.appendingPathComponent("native-checks.json"))
            try RetainedFiles.writeCanonical(scenario.expectations, to: directory.appendingPathComponent("expectations.json"))
            try RetainedFiles.writeCanonical(scenario.deadlockExpectation, to: directory.appendingPathComponent("deadlock-expectation.json"))
            try RetainedFiles.writeCanonical(scenario.coverage, to: directory.appendingPathComponent("check-coverage.json"))
            switch scenario.native {
            case .counterexample(let native):
                guard request.bundle == native.rendered.tlaBundle, request.invocation == .propertyCheck,
                      request.finiteGraphCase.arguments == ["-workers", "1", "-fp", "1"] else {
                    throw TLCPropertyCheckError.requestMismatch
                }
                var request = request
                var remaining = native.rendered.checkNames
                var established = native.checks.properties
                var queries: [PropertyComparison] = []
                while true {
                    let output = directory.appendingPathComponent(queries.isEmpty
                        ? "decisive-check" : "decisive-check-\(queries.count)")
                    let outcome = try processAdapter.run(request, retainingIn: output)
                    let comparison = try native.compare(
                        data: Data(contentsOf: output.appendingPathComponent("counterexample.json")),
                        outcome: outcome,
                        stdout: String(contentsOf: output.appendingPathComponent("logs/tlc.stdout.log"), encoding: .utf8))
                    if case .reached = comparison.swiftResult {
                        try scenario.validateReachability(comparison)
                        guard case .property(let name) = comparison.check, remaining.remove(name) != nil else {
                            throw TLCPropertyCheckError.requestMismatch
                        }
                        queries.append(comparison)
                        established[name] = comparison.swiftResult
                        try RetainedFiles.writeCanonical(queries,
                            to: directory.appendingPathComponent("reachability-comparisons.json"))
                        try RetainedFiles.writeCanonical(ModelCheckResults(properties: established, deadlock: native.checks.deadlock),
                            to: directory.appendingPathComponent("native-checks.json"))
                        request = try request.selecting(bundle: native.rendered.tlaBundle(
                            checking: remaining, checkDeadlock: native.rendered.checksDeadlock),
                            work: request.workingDirectory, runID: UUID(), invocation: .propertyCheck)
                        continue
                    }
                    try RetainedFiles.writeCanonical(comparison, to: directory.appendingPathComponent("counterexample-comparison.json"))
                    try scenario.validateCounterexample(comparison)
                    break
                }
                try RetainedFiles.writeText("decisive-counterexample\n", to: directory.appendingPathComponent("completion.txt"))
            case .exhausted(let native):
                try GraphRunRecords.write(native.graph, to: directory.appendingPathComponent("swift-graph.jsonl"))
                let capture = try properties.captureGraph(native, request: request, source: .generated,
                    in: directory.appendingPathComponent("complete-graph"))
                guard capture.outcome == .completed, capture.graph.isComparable else {
                    throw TLCPropertyCheckError.incompleteGraph
                }
                try GraphRunRecords.write(capture.graph, to: directory.appendingPathComponent("tlc-graph.jsonl"))
                let results = try properties.captureAll(native, completeGraph: .success(capture),
                    source: .generated, in: directory)
                guard let graph = results.graphComparison else { throw TLCPropertyCheckError.incompleteGraph }
                try RetainedFiles.writeJSON(graphDifferencesJSON(graph), to: directory.appendingPathComponent("graph-differences.json"))
                try scenario.validateComparison(graph, checks: results.checks.map { try $0.result.get() })
                try RetainedFiles.writeText("exhaustive\n", to: directory.appendingPathComponent("completion.txt"))
            }
            try RetainedFiles.writeText("exact\n", to: directory.appendingPathComponent("result.txt"))
        } catch {
            try RetainedFiles.writeText(redactingSecrets(in: String(describing: error)),
                to: directory.appendingPathComponent("error.txt"))
            throw error
        }
    }
}
