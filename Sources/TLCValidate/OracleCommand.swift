import Foundation
import SwiftTLA
import UpstreamParity

private enum OracleCommandError: Error, CustomStringConvertible {
    case usage
    case unknownScenario(String)
    case invalidToolchain
    case outputExists(String)

    var description: String {
        switch self {
        case .usage:
            return "Usage: tlc-validate oracle run --case <id-or-all> --output <directory> --maximum-states <positive-integer>"
        case .unknownScenario(let id): return "unknown scenario: \(id)"
        case .invalidToolchain: return "invalid pinned TLC toolchain"
        case .outputExists(let path): return "output already exists: \(path)"
        }
    }
}

func runOracle(arguments: [String]) -> Never {
    do {
        guard arguments.count == 7, arguments[0] == "run", arguments[1] == "--case",
              arguments[3] == "--output", arguments[5] == "--maximum-states",
              let maximumStates = Int(arguments[6]), maximumStates > 0 else {
            throw OracleCommandError.usage
        }
        let scenarios = try modelValidationScenarios()
        let selected = scenarios.filter { arguments[2] == "all" || $0.id == arguments[2] }
        guard !selected.isEmpty else { throw OracleCommandError.unknownScenario(arguments[2]) }
        let output = URL(fileURLWithPath: arguments[4]).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw OracleCommandError.outputExists(output.path)
        }
        let root = try RetainedFiles.projectRoot(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let toolRoot = URL(fileURLWithPath: try requiredEnvironment("FINITE_GRAPH_TOOL_ROOT", ProcessInfo.processInfo.environment))
        let lock = try decode(PinnedTLCToolchain.self,
                              at: root.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
        guard lock.schema == "TLCReferencePin",
              let archive = lock.java.archives[try normalizedArchitecture()] else {
            throw OracleCommandError.invalidToolchain
        }
        let pin = try referencePin(from: lock, javaArchive: archive, toolRoot: toolRoot)
        let tools = try ResolvedTLCToolchain(toolRoot: toolRoot, projectRoot: root, pin: pin)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let timeout = TimeInterval(ProcessInfo.processInfo.environment["SWIFTTLA_ORACLE_TIMEOUT_SECONDS"] ?? "1800") ?? 0
        guard timeout.isFinite, timeout > 0 else { throw OracleCommandError.usage }
        var failures = 0
        for (id, scenario) in selected {
            do {
                let outcome = try captureOracle(scenario: scenario, id: id, maximumStates: maximumStates,
                                                timeout: timeout, tools: tools, pin: pin,
                                                to: output.appendingPathComponent(id))
                print("oracle \(id): \(outcome.graphComplete ? "complete graph" : "decisive result")")
            } catch {
                failures += 1
                fputs("oracle \(id): \(error)\n", stderr)
            }
        }
        exit(failures == 0 ? 0 : 2)
    } catch {
        fputs("oracle: \(error)\n", stderr)
        exit(2)
    }
}

private func captureOracle<Scenario: ModelValidationScenario>(
    scenario: Scenario, id: String, maximumStates: Int, timeout: TimeInterval,
    tools: ResolvedTLCToolchain, pin: TLCReferencePin, to output: URL
) throws -> GeneratedTLCOracleReport {
    try GeneratedTLCOracle.capture(scenario: scenario, id: id, maximumStates: maximumStates,
                                   timeout: timeout, tools: tools, pin: pin, to: output)
}
