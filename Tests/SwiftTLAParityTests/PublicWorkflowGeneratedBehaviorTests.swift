import Foundation
import PublicWorkflowGeneratedFixtures
import SwiftTLA
import Testing
import UpstreamParity

@Suite(.serialized)
struct PublicWorkflowGeneratedBehaviorTests {
  @Test("generated fixture retains one compilation identity from its #spec source")
  func generatedFixtureUsesCanonicalCompilation() throws {
    let compilation = try P4GeneratedCounter.compiledSpecification()
    #expect(compilation.identity == try P4GeneratedCounter.spec.compile().identity)
    #expect(P4GeneratedCounter.generatedMachineMetadata.compilationIdentity == compilation.identity)
  }

  @Test("public workflow fixture executes through nested generated adapters")
  @MainActor
  func nestedFixtureAdaptersMatchTheCanonicalCounter() async throws {
    let invocation = TLAActionInvocation(name: "advance")
    var model = try P4GeneratedCounter.makeMachine()
    let observable = P4GeneratedCounter.Observable()
    let actor = P4GeneratedCounter.Actor()

    let modelEvidence = try await model.execute(invocation)
    let observableEvidence = try await observable.execute(invocation)
    let actorEvidence = try await actor.execute(invocation)

    #expect(modelEvidence.action == .advance)
    #expect(observableEvidence.action == .advance)
    #expect(actorEvidence.action == .advance)
    #expect(modelEvidence.before.value == 0)
    #expect(modelEvidence.after.value == 1)
    #expect(observableEvidence.before == modelEvidence.before)
    #expect(observableEvidence.after == modelEvidence.after)
    #expect(actorEvidence.before == modelEvidence.before)
    #expect(actorEvidence.after == modelEvidence.after)
  }

  @Test("generated registry keeps macro and builder compilation identities aligned")
  func generatedRegistryKeepsCompilationIdentityAligned() throws {
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

    #expect(throws: PublicWorkflowGovernanceError.self) {
      _ = try PublicWorkflowGeneratedBehaviorAdapter().run(
        manifestURL: manifestURL,
        projectRoot: fixture.repository,
        outputDirectory: fixture.outputDirectory(),
        correlation: try fixture.correlation(for: "p4-generated-counter"))
    }
  }

  @Test("canonical project roots accept an equivalent symlinked output spelling")
  func acceptsEquivalentSymlinkedOutputDirectory() throws {
    let fixture = try Fixture()
    guard let equivalentRoot = Self.privateTmpSpelling(of: fixture.repository) else {
      return
    }
    let output = equivalentRoot.appending(path: "Tests/Fixtures/PublicWorkflowConformance/Generated/.test-output-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: output) }

    let run = try PublicWorkflowGeneratedBehaviorAdapter().run(
      manifestURL: fixture.manifestURL,
      projectRoot: fixture.repository,
      outputDirectory: output,
      correlation: try fixture.correlation(for: "p4-generated-counter"))

    #expect(run.comparison.outcome == .exact)
  }

  private static func privateTmpSpelling(of root: URL) -> URL? {
    guard root.path.hasPrefix("/tmp/"),
          URL(fileURLWithPath: "/private" + root.path).resolvingSymlinksInPath().standardizedFileURL == root else {
      return nil
    }
    return URL(fileURLWithPath: "/private" + root.path)
  }

  private struct Fixture {
    let repository: URL
    let manifestURL: URL

    init() throws {
      repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .resolvingSymlinksInPath()
        .standardizedFileURL
      manifestURL = repository.appending(path: "Verification/PublicWorkflowConformance/generated-behavior.json")
      _ = try PublicWorkflowGeneratedBehaviorManifest.load(Data(contentsOf: manifestURL))
    }

    func run(id: String) throws -> (PublicWorkflowGeneratedBehaviorRun, URL) {
      let output = outputDirectory()
      let run = try PublicWorkflowGeneratedBehaviorAdapter().run(
        manifestURL: manifestURL,
        projectRoot: repository,
        outputDirectory: output,
        correlation: try correlation(for: id))
      return (run, output)
    }

    func correlation(for id: String) throws -> PublicWorkflowCaseRunCorrelation {
      try PublicWorkflowCaseRunCorrelation(
        caseID: id,
        gateRunID: UUID(),
        fixtureRunID: UUID(),
        comparisonRunID: UUID())
    }

    func observation(_ reference: CoreEvidenceReference) throws -> PublicWorkflowCanonicalObservation {
      try JSONDecoder().decode(
        PublicWorkflowCanonicalObservation.self,
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
