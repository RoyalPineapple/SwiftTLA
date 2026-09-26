import Foundation
import SwiftTLA
import UpstreamParity

private enum NativeCommandError: Error, CustomStringConvertible {
    case usage
    case unknownScenario(String)
    case outputExists(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: tlc-validate native list | native run --case <id-or-all> --output <directory> --maximum-states <positive-integer>"
        case .unknownScenario(let id): return "unknown scenario: \(id)"
        case .outputExists(let path): return "output already exists: \(path)"
        }
    }
}

func runNative(arguments: [String]) -> Never {
    do {
        let scenarios = try modelValidationScenarios()
        if arguments == ["list"] {
            print(String(decoding: try JSONEncoder().encode(scenarios.map(\.id)), as: UTF8.self))
            exit(0)
        }
        guard arguments.count == 7, arguments[0] == "run", arguments[1] == "--case",
              arguments[3] == "--output", arguments[5] == "--maximum-states",
              let maximumStates = Int(arguments[6]), maximumStates > 0 else {
            throw NativeCommandError.usage
        }
        let selected = scenarios.filter { arguments[2] == "all" || $0.id == arguments[2] }
        guard !selected.isEmpty else { throw NativeCommandError.unknownScenario(arguments[2]) }
        let output = URL(fileURLWithPath: arguments[4]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw NativeCommandError.outputExists(output.path)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var failures = 0
        for (id, scenario) in selected {
            do {
                let result = try writeNativeEvidence(scenario: scenario, maximumStates: maximumStates,
                                                     to: output.appendingPathComponent(id))
                print("native \(id): \(result.graphComplete ? "complete graph" : "decisive result")")
            } catch {
                failures += 1
                fputs("native \(id): \(error)\n", stderr)
            }
        }
        exit(failures == 0 ? 0 : 2)
    } catch {
        fputs("native: \(error)\n", stderr)
        exit(2)
    }
}

private func writeNativeEvidence<Scenario: ModelValidationScenario>(
    scenario: Scenario, maximumStates: Int, to output: URL
) throws -> NativeValidationReport {
    try NativeValidationRunner.run(scenario: scenario, maximumStates: maximumStates, to: output)
}
