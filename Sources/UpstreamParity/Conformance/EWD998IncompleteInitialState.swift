import Foundation

package enum EWD998IncompleteInitialState {
    package static func requireUninitializedPasses(
        outcome: TLCExecutionOutcome, retainedIn directory: URL, caseID: String
    ) throws {
        let stdout = try String(contentsOf: directory.appendingPathComponent("logs/tlc.stdout.log"),
            encoding: .utf8)
        guard outcome == .failed(exitStatus: 255),
              stdout.contains("Error: State is not completely specified by the initial predicate:"),
              stdout.contains("/\\ passes = null"),
              !FileManager.default.fileExists(atPath: directory.appendingPathComponent("counterexample.json").path)
        else { throw UpstreamTLCParityError.invalidOutcome("\(caseID): \(outcome)") }
    }
}
