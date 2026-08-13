import Foundation
import Testing
import UpstreamParity

@Suite(.serialized)
struct PublicWorkflowGeneratedBehaviorTests {
  @Test("compiled registry writes and verifies exact generated observations")
  func exactFixtureMatchesRetainedObservations() throws {
    let fixture = try Fixture()
    let (run, output) = try fixture.run(id: "p4-generated-counter")
    defer { try? FileManager.default.removeItem(at: output) }

    #expect(run.comparison.outcome == .exact)
    #expect(run.comparison.left == run.comparison.right)
    #expect(run.mismatchFingerprint == nil)
    #expect(try fixture.observation(run.generatedObservation) == run.comparison.left)
    #expect(try fixture.observation(run.builderObservation) == run.comparison.right)
  }

  @Test("compiled mismatch fixture retains a stable observed difference")
  func mismatchFixtureMatchesRetainedDifference() throws {
    let fixture = try Fixture()
    let (first, firstOutput) = try fixture.run(id: "p4-generated-counter-intentional-mismatch")
    let (second, secondOutput) = try fixture.run(id: "p4-generated-counter-intentional-mismatch")
    defer {
      try? FileManager.default.removeItem(at: firstOutput)
      try? FileManager.default.removeItem(at: secondOutput)
    }

    #expect(first.comparison.outcome == .difference)
    #expect(first.comparison.left.failures.contains { $0.contains("propertyViolation") && $0.contains("withinBounds") })
    #expect(first.comparison.left.trace?.contains { $0.contains("advance") } == true)
    #expect(first.mismatchFingerprint != nil)
    #expect(first.mismatchFingerprint == second.mismatchFingerprint)
    #expect(try fixture.observation(first.generatedObservation) == first.comparison.left)
    #expect(try fixture.observation(first.builderObservation) == first.comparison.right)
  }

  @Test("compiled generated action failures and unavailability retain evidence")
  func generatedActionFailureAndUnavailableAreObserved() throws {
    let fixture = try Fixture()
    for (id, marker) in [
      ("p4-generated-counter-evaluation-failed", "evaluationFailed"),
      ("p4-generated-counter-evaluation-unavailable", "evaluationUnavailable")
    ] {
      let (run, output) = try fixture.run(id: id)
      defer { try? FileManager.default.removeItem(at: output) }

      #expect(run.comparison.outcome == .difference)
      #expect(run.comparison.left.failures.contains { $0.contains(marker) })
      #expect(run.comparison.left.diagnostics.contains { $0.contains("generated:evaluation") })
      #expect(run.comparison.left.trace?.isEmpty == false)
      #expect(run.mismatchFingerprint != nil)
      #expect(try fixture.observation(run.generatedObservation) == run.comparison.left)
    }
  }

  @Test("changed source pin rejects the generated fixture before comparison")
  func changedSourcePinIsRejected() throws {
    let fixture = try Fixture()
    let manifestURL = try fixture.mutatedManifest { manifest in
      var fixtures = try #require(manifest["fixtures"] as? [[String: Any]])
      var source = try #require(fixtures[0]["sourceInput"] as? [String: Any])
      source["sha256"] = String(repeating: "0", count: 64)
      fixtures[0]["sourceInput"] = source
      manifest["fixtures"] = fixtures
    }
    defer { try? FileManager.default.removeItem(at: manifestURL) }

    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      _ = try PublicWorkflowGeneratedBehaviorAdapterV1().run(
        manifestURL: manifestURL,
        projectRoot: fixture.repository,
        outputDirectory: fixture.outputDirectory(),
        correlation: try fixture.correlation(for: "p4-generated-counter"))
    }
  }

  private struct Fixture {
    let repository: URL
    let manifestURL: URL

    init() throws {
      repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      manifestURL = repository.appending(path: "Verification/PublicWorkflowConformance/generated-behavior.json")
      _ = try PublicWorkflowGeneratedBehaviorManifestV1.load(Data(contentsOf: manifestURL))
    }

    func run(id: String) throws -> (PublicWorkflowGeneratedBehaviorRunV1, URL) {
      let output = outputDirectory()
      let run = try PublicWorkflowGeneratedBehaviorAdapterV1().run(
        manifestURL: manifestURL,
        projectRoot: repository,
        outputDirectory: output,
        correlation: try correlation(for: id))
      return (run, output)
    }

    func correlation(for id: String) throws -> PublicWorkflowCaseRunCorrelationV1 {
      try PublicWorkflowCaseRunCorrelationV1(
        caseID: id,
        gateRunID: UUID(),
        fixtureRunID: UUID(),
        comparisonRunID: UUID())
    }

    func observation(_ reference: CoreEvidenceReferenceV1) throws -> PublicWorkflowCanonicalObservationV1 {
      try JSONDecoder().decode(
        PublicWorkflowCanonicalObservationV1.self,
        from: Data(contentsOf: repository.appending(path: reference.path)))
    }

    func outputDirectory() -> URL {
      repository.appending(path: "Tests/Fixtures/PublicWorkflowConformance/Generated/.test-output-\(UUID().uuidString)")
    }

    func mutatedManifest(_ change: (inout [String: Any]) throws -> Void) throws -> URL {
      var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
      try change(&manifest)
      let url = repository.appending(path: "Tests/Fixtures/PublicWorkflowConformance/Generated/.test-manifest-\(UUID().uuidString).json")
      try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: url)
      return url
    }
  }
}
