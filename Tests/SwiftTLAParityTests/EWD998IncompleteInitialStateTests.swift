import Foundation
import Testing
@testable import UpstreamParity

struct EWD998IncompleteInitialStateTests {
    @Test("an uninitialized passes value is source-invalid, not a safety counterexample")
    func classifiesPinnedFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logs = directory.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdout = logs.appendingPathComponent("tlc.stdout.log")
        try Data("Error: State is not completely specified by the initial predicate:\n/\\ passes = null\n".utf8)
            .write(to: stdout)

        try EWD998IncompleteInitialState.requireUninitializedPasses(
            outcome: .failed(exitStatus: 255), retainedIn: directory, caseID: "fixture")
        #expect(throws: UpstreamTLCParityError.self) {
            try EWD998IncompleteInitialState.requireUninitializedPasses(
                outcome: .safetyViolation, retainedIn: directory, caseID: "fixture")
        }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("counterexample.json"))
        #expect(throws: UpstreamTLCParityError.self) {
            try EWD998IncompleteInitialState.requireUninitializedPasses(
                outcome: .failed(exitStatus: 255), retainedIn: directory, caseID: "fixture")
        }
    }
}
