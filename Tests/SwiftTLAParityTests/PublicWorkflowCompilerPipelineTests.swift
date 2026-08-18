import Foundation
import Testing
import UpstreamParity

@Suite(.serialized)
struct PublicWorkflowCompilerPipelineTests {
  @Test("compiler-pipeline fixture uses its declared formal module name")
  func compilerPipelineFixtureUsesDeclaredFormalModuleName() throws {
    let compilation = try PublicWorkflowCompilerPipelineCounterV1.compiledSpecification()

    #expect(compilation.spec.name == "CompilerPipelineCounter")
    #expect(compilation.identity == try PublicWorkflowCompilerPipelineCounterV1.spec.compile().identity)
  }

  @Test("declared compiler-pipeline evidence retains exact bounded bundle and contract artifacts")
  func exactEvidenceIsDiagnosticOnly() throws {
    let fixture = try Fixture(control: .exact)
    defer { fixture.remove() }
    let run = try fixture.run()

    #expect(run.evidence.authority == .diagnosticOnly)
    #expect(run.evidence.outcome == .exact)
    #expect(run.evidence.status == .matched)
    #expect(!run.evidence.bundle.isEmpty)
    #expect(!run.evidence.artifacts.isEmpty)
  }

  @Test("the source-controlled manifest retains a portable exact case")
  func sourceControlledManifestRuns() throws {
    let root = try compilerPipelinePackageRoot()
    let output = root.appending(path: ".build/PublicWorkflowCompilerPipelineManifest-\(UUID())")
    defer { try? FileManager.default.removeItem(at: output) }
    let run = try CompilerPipelineDiagnosticEvidenceAdapterV1().run(
      manifestURL: root.appending(path: "Verification/PublicWorkflowConformance/compiler-pipeline.json"), projectRoot: root,
      outputDirectory: output,
      correlation: try PublicWorkflowCaseRunCorrelationV1(caseID: "compiler-pipeline-counter", gateRunID: UUID(), fixtureRunID: UUID(), comparisonRunID: UUID()))
    #expect(run.evidence.outcome == .exact)
  }

  @Test("stale, foreign, and swapped inputs never become compiler-pipeline success")
  func untrustedInputsAreUnavailable() throws {
    for attack in [Attack.stale, .foreign, .swapped] {
      let fixture = try Fixture(control: .exact)
      defer { fixture.remove() }
      try fixture.apply(attack)
      let run = try fixture.run()
      #expect(run.evidence.outcome == .unavailable, Comment(rawValue: "\(attack) must fail closed"))
      #expect(run.evidence.status == .unavailable)
    }
  }

  @Test("structural-invalid and metadata-mismatch controls retain differences")
  func invalidStructureAndMetadataAreDifferences() throws {
    for control in [Control.structuralInvalid, .metadataMismatch] {
      let fixture = try Fixture(control: control)
      defer { fixture.remove() }
      let run = try fixture.run()
      #expect(run.evidence.outcome == .difference)
      #expect(run.evidence.status == .matched)
      if control == .structuralInvalid {
        #expect(run.evidence.compilationDiagnosticCode == CompilationDiagnostic.Code.duplicateVariable.rawValue)
        #expect(run.evidence.compilationDiagnosticStage == CompilationDiagnostic.Stage.validation.rawValue)
      }
    }
  }

  @Test("declared unavailable tools remain unavailable")
  func unavailableToolDoesNotPass() throws {
    let fixture = try Fixture(control: .unavailable)
    defer { fixture.remove() }
    let run = try fixture.run()
    #expect(run.evidence.outcome == .unavailable)
    #expect(run.evidence.status == .matched)
  }

  @Test("a changed rendered bundle and a bound drift cannot pass compiler-pipeline evidence")
  func renderedMismatchAndBoundDriftFailClosed() throws {
    let rendered = try Fixture(control: .renderedMismatch)
    defer { rendered.remove() }
    let renderedRun = try rendered.run()
    #expect(renderedRun.evidence.outcome == .difference)

    let bound = try Fixture(control: .boundDrift)
    defer { bound.remove() }
    let boundRun = try bound.run()
    #expect(boundRun.evidence.outcome == .unavailable)
    #expect(boundRun.evidence.status == .unavailable)

    let generatedBound = try Fixture(control: .generatedBoundDrift)
    defer { generatedBound.remove() }
    let generatedBoundRun = try generatedBound.run()
    #expect(generatedBoundRun.evidence.outcome == .unavailable)
  }

  @Test("stale or swapped retained comparison artifacts fail their recorded pins")
  func retainedComparisonArtifactsFailClosed() throws {
    let fixture = try Fixture(control: .exact)
    defer { fixture.remove() }
    let first = try fixture.run()
    let second = try fixture.run()
    let firstArtifact = try #require(first.evidence.artifacts.first(where: { $0.path.hasSuffix("direct-graph/comparison.json") }))
    let secondArtifact = try #require(second.evidence.artifacts.first(where: { $0.path.hasSuffix("direct-graph/comparison.json") }))
    #expect(first.evidence.correlation.comparisonRunID != second.evidence.correlation.comparisonRunID)
    let firstURL = fixture.root.appendingPathComponent(firstArtifact.path)
    try FileManager.default.removeItem(at: firstURL)
    try FileManager.default.copyItem(at: fixture.root.appendingPathComponent(secondArtifact.path), to: firstURL)
    #expect(throws: PublicWorkflowGovernanceErrorV1.self) {
      try first.validateRetainedArtifacts(beneath: fixture.root)
    }
  }

  private enum Attack: CustomStringConvertible { case stale, foreign, swapped
    var description: String { switch self { case .stale: "stale"; case .foreign: "foreign"; case .swapped: "swapped" } }
  }

  private enum Control: Equatable { case exact, structuralInvalid, metadataMismatch, unavailable, renderedMismatch, boundDrift, generatedBoundDrift }

  private final class Fixture {
    let root: URL
    let manifestURL: URL
    let control: Control
    private let id = "compiler-pipeline-counter"

    init(control: Control) throws {
      self.control = control
      root = FileManager.default.temporaryDirectory.appendingPathComponent("PublicWorkflowCompilerPipelineTests-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let inputs = root.appendingPathComponent("inputs")
      try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
      let source = inputs.appendingPathComponent("source.swift")
      try Data(try sourceText().utf8).write(to: source)
      let config = try CompilerPipelineFixtureConfigurationV1(caseID: id,
        fixtureID: control == .structuralInvalid ? "compiler-pipeline-structural-invalid" : id,
        maxStates: control == .structuralInvalid || control == .unavailable ? 1 : control == .boundDrift ? 3 : control == .generatedBoundDrift ? 5 : 4,
        metadataMode: control == .metadataMismatch ? .mismatch : .exact,
        renderedBundleMode: control == .renderedMismatch ? .semanticMismatch : .exact,
        toolAvailable: control != .unavailable)
      let configURL = inputs.appendingPathComponent("configuration.json")
      try JSONEncoder().encode(config).write(to: configURL)
      let roles = ["adapter", "compiler", "macro", "runtime", "tlcAdapter", "graphParser", "dependencies", "tlcReference"]
      let toolchain = try roles.map { role -> CompilerPipelineDiagnosticManifestV1.ToolchainEntry in
        let evidence = inputs.appendingPathComponent("\(role).txt")
        try Data("\(role)\n".utf8).write(to: evidence)
        return try .init(role: role, evidence: try reference(evidence))
      }
      let manifest = try CompilerPipelineDiagnosticManifestV1(
        toolchain: toolchain,
        cases: [try CompilerPipelineDiagnosticCaseV1(id: id, source: try reference(source), configuration: try reference(configURL),
          finiteBounds: try CoreFiniteBoundsV1(summary: "counter has at most two reachable states", limits: ["maxStates": control == .generatedBoundDrift ? 5 : 4]),
          expectedOutcome: expected(control))])
      manifestURL = root.appendingPathComponent("compiler-pipeline.json")
      try JSONEncoder().encode(manifest).write(to: manifestURL)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func run() throws -> CompilerPipelineDiagnosticRunV1 {
      let package = try compilerPipelinePackageRoot()
      return try CompilerPipelineDiagnosticEvidenceAdapterV1(toolRoot: package.appending(path: ".build/core-conformance-tools"), toolProjectRoot: package).run(manifestURL: manifestURL, projectRoot: root,
        outputDirectory: root.appendingPathComponent("output-\(UUID().uuidString)"),
        correlation: try PublicWorkflowCaseRunCorrelationV1(caseID: id, gateRunID: UUID(), fixtureRunID: UUID(), comparisonRunID: UUID()))
    }

    func apply(_ attack: Attack) throws {
      switch attack {
      case .stale:
        try Data("changed source\n".utf8).write(to: root.appendingPathComponent("inputs/source.swift"))
      case .foreign:
        var manifest = try decodedManifest()
        let case0 = try #require(manifest.cases.first)
        let replacement = try CompilerPipelineDiagnosticCaseV1(id: case0.id,
          source: try CoreEvidenceReferenceV1(path: "../outside.swift", sha256: case0.source.sha256), configuration: case0.configuration,
          finiteBounds: case0.finiteBounds, expectedOutcome: case0.expectedOutcome)
        manifest = try CompilerPipelineDiagnosticManifestV1(toolchain: manifest.toolchain, cases: [replacement])
        try JSONEncoder().encode(manifest).write(to: manifestURL)
      case .swapped:
        let config = try CompilerPipelineFixtureConfigurationV1(caseID: "another-case", fixtureID: id, maxStates: 4)
        let configURL = root.appendingPathComponent("inputs/swapped.json")
        try JSONEncoder().encode(config).write(to: configURL)
        let manifest = try decodedManifest()
        let case0 = try #require(manifest.cases.first)
        let replacement = try CompilerPipelineDiagnosticCaseV1(id: case0.id, source: case0.source, configuration: try reference(configURL), finiteBounds: case0.finiteBounds, expectedOutcome: case0.expectedOutcome)
        try JSONEncoder().encode(try CompilerPipelineDiagnosticManifestV1(toolchain: manifest.toolchain, cases: [replacement])).write(to: manifestURL)
      }
    }

    private func decodedManifest() throws -> CompilerPipelineDiagnosticManifestV1 {
      try JSONDecoder().decode(CompilerPipelineDiagnosticManifestV1.self, from: Data(contentsOf: manifestURL))
    }

    private func reference(_ url: URL) throws -> CoreEvidenceReferenceV1 {
      try .init(path: String(url.path.dropFirst(root.path.count + 1)), sha256: SHA256V1.hex(try Data(contentsOf: url)))
    }

    private func sourceText() throws -> String {
      let root = try compilerPipelinePackageRoot()
      let source = root.appending(path: "Sources/UpstreamParity/Conformance/PublicWorkflowCompilerPipelineFixture.swift")
      return try String(contentsOf: source)
    }

    private func expected(_ control: Control) -> CompilerPipelineEvidenceOutcomeV1 {
      switch control { case .exact: .exact; case .structuralInvalid, .metadataMismatch, .renderedMismatch: .difference; case .unavailable, .boundDrift, .generatedBoundDrift: .unavailable }
    }
  }

}

private func compilerPipelinePackageRoot() throws -> URL {
  var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
    let parent = directory.deletingLastPathComponent()
    guard parent != directory else { throw CocoaError(.fileNoSuchFile) }
    directory = parent
  }
  return directory
}
