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
            return "Usage: tlc-validate native list | native run --case <id-or-all> --output <directory> --maximum-states <positive-integer> | native <prepare-selection|prepare-branchwise-selection> --authored-source <swift-file> --output <directory> | native prepare-compiler-stack-seed --authored-source <swift-file> --native-source <swift-file> --output <directory>"
        case .unknownScenario(let id): return "unknown scenario: \(id)"
        case .outputExists(let path): return "output already exists: \(path)"
        }
    }
}

func runNative(arguments: [String]) -> Never {
    do {
        if arguments.first == "verify-member-tokens" {
            guard arguments.count == 5, arguments[1] == "--compiled-members", arguments[3] == "--attached-members"
            else { throw NativeCommandError.usage }
            try verifyNativeMemberTokens(
                compiled: String(contentsOf: URL(fileURLWithPath: arguments[2]), encoding: .utf8),
                attached: String(contentsOf: URL(fileURLWithPath: arguments[4]), encoding: .utf8))
            exit(0)
        }
        if arguments.first == "prepare-compiler-stack-seed" {
            guard arguments.count == 7, arguments[1] == "--authored-source",
                  arguments[3] == "--native-source", arguments[5] == "--output"
            else { throw NativeCommandError.usage }
            try CompilerStackSeedEvidence.prepare(
                authoredSource: String(contentsOf: URL(fileURLWithPath: arguments[2]), encoding: .utf8),
                nativeSource: String(contentsOf: URL(fileURLWithPath: arguments[4]), encoding: .utf8),
                to: URL(fileURLWithPath: arguments[6]))
            exit(0)
        }
        if let command = arguments.first, ["prepare-selection", "prepare-branchwise-selection"].contains(command) {
            guard arguments.count == 5, arguments[1] == "--authored-source",
                  arguments[3] == "--output" else { throw NativeCommandError.usage }
            try CheckingSelectionEvidence.prepare(
                authoredSource: Data(contentsOf: URL(fileURLWithPath: arguments[2])),
                to: URL(fileURLWithPath: arguments[4]), branchwise: command == "prepare-branchwise-selection")
            exit(0)
        }
        let scenarios = try modelValidationScenarios()
        let assumptions = try assumptionValidationScenarios()
        if arguments == ["list"] {
            print(String(decoding: try JSONEncoder().encode(scenarios.map(\.id) + assumptions.map(\.id)), as: UTF8.self))
            exit(0)
        }
        guard arguments.count == 7, arguments[0] == "run", arguments[1] == "--case",
              arguments[3] == "--output", arguments[5] == "--maximum-states",
              let maximumStates = Int(arguments[6]), maximumStates > 0 else {
            throw NativeCommandError.usage
        }
        let selected = scenarios.filter { arguments[2] == "all" || $0.id == arguments[2] }
        let selectedAssumptions = assumptions.filter { arguments[2] == "all" || $0.id == arguments[2] }
        guard !selected.isEmpty || !selectedAssumptions.isEmpty else {
            throw NativeCommandError.unknownScenario(arguments[2])
        }
        let output = URL(fileURLWithPath: arguments[4]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw NativeCommandError.outputExists(output.path)
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var failures = 0
        for (id, scenario) in selected {
            do {
                let result = try writeNativeEvidence(scenario: scenario, caseID: id, maximumStates: maximumStates,
                                                     to: output.appendingPathComponent(id))
                let summary: String
                switch scenario.checkingMode {
                case .exhaustive: summary = "complete graph"
                case .decisiveCounterexample: summary = "decisive result"
                case .simulation:
                    summary = result.properties.values.contains(.violated)
                        ? "sampled counterexample" : "inconclusive simulation"
                }
                print("native \(id): \(summary)")
            } catch {
                failures += 1
                fputs("native \(id): \(error)\n", stderr)
            }
        }
        for (id, scenario) in selectedAssumptions {
            do {
                let report = try AssumptionValidationEvidence.native(
                    scenario: scenario, id: id, to: output.appendingPathComponent(id))
                print("native \(id): assumption \(report.verdict)")
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
    scenario: Scenario, caseID: String, maximumStates: Int, to output: URL
) throws -> NativeValidationReport {
    try NativeValidationRunner.run(scenario: scenario, caseID: caseID,
        maximumStates: maximumStates, to: output)
}
