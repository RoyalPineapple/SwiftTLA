import Foundation
import SwiftTLA

package struct TLCScenarioCheck: Sendable {
    private let properties: TLCPropertyCheck

    package init(processAdapter: TLCProcessAdapter = TLCProcessAdapter()) {
        properties = TLCPropertyCheck(processAdapter: processAdapter)
    }

    package func run(_ scenario: NativeScenarioRun, request: TLCProcessRequest, in directory: URL) throws {
        try RetainedFiles.outputDirectory(directory, beneath: directory.deletingLastPathComponent())
        do {
            try GraphRunRecords.write(scenario.native.graph, to: directory.appendingPathComponent("swift-graph.jsonl"))
            try RetainedFiles.writeCanonical(scenario.native.checks, to: directory.appendingPathComponent("native-checks.json"))
            try RetainedFiles.writeCanonical(scenario.expectations, to: directory.appendingPathComponent("expectations.json"))
            try RetainedFiles.writeCanonical(scenario.deadlockExpectation, to: directory.appendingPathComponent("deadlock-expectation.json"))
            try RetainedFiles.writeCanonical(scenario.coverage, to: directory.appendingPathComponent("check-coverage.json"))
            let capture = try properties.captureGraph(scenario.native, request: request, source: .generated,
                in: directory.appendingPathComponent("complete-graph"))
            guard capture.outcome == .completed, capture.graph.isComparable else {
                throw TLCPropertyCheckError.incompleteGraph
            }
            try GraphRunRecords.write(capture.graph, to: directory.appendingPathComponent("tlc-graph.jsonl"))
            let results = try properties.captureAll(scenario.native, completeGraph: .success(capture),
                source: .generated, in: directory)
            guard let graph = results.graphComparison else { throw TLCPropertyCheckError.incompleteGraph }
            try RetainedFiles.writeJSON(graphDifferencesJSON(graph), to: directory.appendingPathComponent("graph-differences.json"))
            try scenario.validateComparison(graph, checks: results.checks.map { try $0.result.get() })
            try RetainedFiles.writeText("exact\n", to: directory.appendingPathComponent("result.txt"))
        } catch {
            try RetainedFiles.writeText(redactingSecrets(in: String(describing: error)),
                to: directory.appendingPathComponent("error.txt"))
            throw error
        }
    }
}
