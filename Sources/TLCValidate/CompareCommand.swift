import Foundation
import SwiftTLA
import UpstreamParity

private enum CompareCommandError: Error, CustomStringConvertible {
    case usage
    case unknownScenario(String)
    case outputExists(String)

    var description: String {
        switch self {
        case .usage:
            "Usage: tlc-validate compare run --case <id-or-all> --native <directory> --oracle <directory> --output <directory>"
        case .unknownScenario(let id): "unknown scenario: \(id)"
        case .outputExists(let path): "output already exists: \(path)"
        }
    }
}

func runCompare(arguments: [String]) -> Never {
    do {
        guard arguments.count == 9, arguments[0] == "run", arguments[1] == "--case",
              arguments[3] == "--native", arguments[5] == "--oracle",
              arguments[7] == "--output" else { throw CompareCommandError.usage }
        let scenarios = try modelValidationScenarios()
        let selected = scenarios.filter { arguments[2] == "all" || $0.id == arguments[2] }
        guard !selected.isEmpty else { throw CompareCommandError.unknownScenario(arguments[2]) }
        let native = URL(fileURLWithPath: arguments[4]).standardizedFileURL
        let oracle = URL(fileURLWithPath: arguments[6]).standardizedFileURL
        let output = URL(fileURLWithPath: arguments[8]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CompareCommandError.outputExists(output.path)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var failures = 0
        for (id, scenario) in selected {
            do {
                let result = try compareScenario(scenario, id: id,
                    native: native.appendingPathComponent(id),
                    oracle: oracle.appendingPathComponent(id),
                    output: output.appendingPathComponent(id))
                print("compare \(id): \(result.result)")
                if result.result != "exact" { failures += 1 }
            } catch {
                failures += 1
                fputs("compare \(id): \(error)\n", stderr)
            }
        }
        exit(failures == 0 ? 0 : 2)
    } catch {
        fputs("compare: \(error)\n", stderr)
        exit(2)
    }
}

private func compareScenario<Scenario: ModelValidationScenario>(
    _ scenario: Scenario, id: String, native: URL, oracle: URL, output: URL
) throws -> ValidationEvidenceComparisonReport {
    let rendered = try scenario.render()
    return try ValidationEvidenceComparison.compare(
        caseID: id, native: native, oracle: oracle, actions: rendered.actions, to: output)
}
