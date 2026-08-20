import Foundation
import Testing
import UpstreamParity

@Suite(.serialized)
struct PublicWorkflowParserBuilderTests {
  @Test("source-controlled portable fixture produces pinned canonical observations")
  func portableManifestProducesComparison() throws {
    if let relativeOutput = ProcessInfo.processInfo.environment["PUBLIC_WORKFLOW_PARSER_BUILDER_OUTPUT"] {
      let root = try throwingPackageRoot()
      let output = root.appendingPathComponent(relativeOutput)
      let run = try PublicWorkflowParserBuilderAdapter().run(
        manifestURL: root.appendingPathComponent("Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/manifest.json"),
        projectRoot: root, outputDirectory: output,
        correlation: try PublicWorkflowCaseRunCorrelation(caseID: "parser-builder-bounded-counter", gateRunID: UUID(), fixtureRunID: UUID(), comparisonRunID: UUID()))
      #expect(run.comparison.outcome == .exact)
      return
    }
    let fixture = try Fixture()
    defer { fixture.remove() }

    let run = try fixture.run()
    #expect(run.comparison.outcome == .exact)
    #expect(run.comparison.diagnosticCode == .exactAgreement)
    #expect(run.comparison.left == run.comparison.right)
    #expect(run.manifest.path == "Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/manifest.json")
    #expect(run.parserObservation.path == ".build/parser-builder-output/parser-observation.json")
    #expect(run.builderObservation.path == ".build/parser-builder-output/builder-observation.json")
  }

  @Test("source-controlled mismatch fixture retains a difference")
  func portableManifestRetainsMismatch() throws {
    if let relativeOutput = ProcessInfo.processInfo.environment["PUBLIC_WORKFLOW_PARSER_BUILDER_MISMATCH_OUTPUT"] {
      let root = try throwingPackageRoot()
      let run = try PublicWorkflowParserBuilderAdapter().run(
        manifestURL: root.appendingPathComponent("Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/Mismatch/manifest.json"),
        projectRoot: root, outputDirectory: root.appendingPathComponent(relativeOutput),
        correlation: try PublicWorkflowCaseRunCorrelation(caseID: "parser-builder-bounded-counter-mismatch", gateRunID: UUID(), fixtureRunID: UUID(), comparisonRunID: UUID()))
      #expect(run.comparison.outcome == .difference)
      #expect(run.comparison.diagnosticCode == .observationDifference)
      return
    }
    let fixture = try Fixture(relativeManifest: "Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/Mismatch/manifest.json")
    defer { fixture.remove() }
    let run = try fixture.run(caseID: "parser-builder-bounded-counter-mismatch")
    #expect(run.comparison.outcome == .difference)
    #expect(run.comparison.diagnosticCode == .observationDifference)
  }

  @Test("substituted declared inputs and observations are rejected")
  func rejectsSubstitutedInputsAndObservations() throws {
    for attack in Attack.allCases {
      let fixture = try Fixture()
      defer { fixture.remove() }
      try fixture.apply(attack)
      #expect(throws: PublicWorkflowGovernanceError.self) { try fixture.run() }
    }
  }

  @Test("canonical project roots accept an equivalent symlinked output spelling")
  func acceptsEquivalentSymlinkedOutputDirectory() throws {
    let root = try throwingPackageRoot().resolvingSymlinksInPath().standardizedFileURL
    guard let equivalentRoot = Self.privateTmpSpelling(of: root) else {
      return
    }
    let output = equivalentRoot.appendingPathComponent(".build/PublicWorkflowParserBuilderTests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: output) }

    let run = try PublicWorkflowParserBuilderAdapter().run(
      manifestURL: root.appendingPathComponent("Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/manifest.json"),
      projectRoot: root,
      outputDirectory: output,
      correlation: try PublicWorkflowCaseRunCorrelation(
        caseID: "parser-builder-bounded-counter", gateRunID: UUID(), fixtureRunID: UUID(), comparisonRunID: UUID()))

    #expect(run.comparison.outcome == .exact)
  }

  private static func privateTmpSpelling(of root: URL) -> URL? {
    guard root.path.hasPrefix("/tmp/"),
          URL(fileURLWithPath: "/private" + root.path).resolvingSymlinksInPath().standardizedFileURL == root else {
      return nil
    }
    return URL(fileURLWithPath: "/private" + root.path)
  }

  private enum Attack: CaseIterable {
    case source, configuration, parserObservation, builderObservation, sourcePin, provenanceMismatch
    case swiftSyntaxPin, swiftTLAPackagePin, bridgeSourcePin, adapterSourceEvidencePin, nonApplicablePin, pathEscape
  }

  private final class Fixture {
    let sourceRoot: URL
    let root: URL
    let manifest: URL

    init(relativeManifest: String = "Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/manifest.json") throws {
      sourceRoot = try throwingPackageRoot()
      root = FileManager.default.temporaryDirectory.appendingPathComponent("PublicWorkflowParserBuilderTests-\(UUID())")
      manifest = root.appendingPathComponent(relativeManifest)
      try stage("Tests/Fixtures/PublicWorkflowConformance/ParserBuilder")
      // The mismatch manifest deliberately shares the parent fixture's
      // non-applicable toolchain evidence, so stage that referenced file too.
      if relativeManifest.contains("/Mismatch/") {
        try stageIfAbsent("Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/not-applicable.json")
      }
      try stage("Package.swift")
      try stage("Package.resolved")
      try stage("Sources/UpstreamParity/Conformance/PublicWorkflowParserBuilderAdapter.swift")
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func run(caseID: String = "parser-builder-bounded-counter") throws -> PublicWorkflowParserBuilderRun {
      try PublicWorkflowParserBuilderAdapter().run(
        manifestURL: manifest, projectRoot: root, outputDirectory: root.appendingPathComponent(".build/parser-builder-output"),
        correlation: try PublicWorkflowCaseRunCorrelation(caseID: caseID, gateRunID: UUID(), fixtureRunID: UUID(), comparisonRunID: UUID()))
    }

    func apply(_ attack: Attack) throws {
      let directory = manifest.deletingLastPathComponent()
      switch attack {
      case .source:
        try Data("substituted source".utf8).write(to: directory.appendingPathComponent("fixture.swift"))
      case .configuration:
        try Data("{}".utf8).write(to: directory.appendingPathComponent("configuration.json"))
      case .parserObservation:
        try Data("{}".utf8).write(to: directory.appendingPathComponent("parser-observation.json"))
      case .builderObservation:
        try Data("{}".utf8).write(to: directory.appendingPathComponent("builder-observation.json"))
      case .sourcePin:
        try replaceFirst("\"source\": { \"path\": \"Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/fixture.swift\", \"sha256\": \"903c5ff1b0fd5751795310860054fbf781e311e04a37a6cefc808b2cfe576bb9\" }", with: "\"source\": { \"path\": \"Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/fixture.swift\", \"sha256\": \"\(String(repeating: "0", count: 64))\" }")
      case .provenanceMismatch:
        try replace("\"argumentsSHA256\": \"5619a935660498c6aa59ebe9c6b6889eb28103aad7f383c9c070aa6f7816cffa\"", with: "\"argumentsSHA256\": \"\(String(repeating: "0", count: 64))\"")
      case .swiftSyntaxPin:
        try replaceFirst("\"sha256\": \"cfdc69e87cdcea8681bfa8b117d599eef34e6f986fe23d9ad5eb4a320a1a18d7\"", with: "\"sha256\": \"\(String(repeating: "0", count: 64))\"")
      case .swiftTLAPackagePin:
        try replaceFirst("\"sha256\": \"9dd427098bbacebacb55a8d16d23853352a4af7dc41a78c3f771db6e2a896442\"", with: "\"sha256\": \"\(String(repeating: "0", count: 64))\"")
      case .bridgeSourcePin:
        try replaceFirst("\"bridgeSourceSHA256\": \"0d78df1a490150176110482fd2fa28478b712318ce32caef782030697cbdfce7\"", with: "\"bridgeSourceSHA256\": \"\(String(repeating: "0", count: 64))\"")
      case .adapterSourceEvidencePin:
        try replaceFirst("\"adapterSource\", \"evidence\": { \"path\": \"Sources/UpstreamParity/Conformance/PublicWorkflowParserBuilderAdapter.swift\", \"sha256\": \"0d78df1a490150176110482fd2fa28478b712318ce32caef782030697cbdfce7\"", with: "\"adapterSource\", \"evidence\": { \"path\": \"Sources/UpstreamParity/Conformance/PublicWorkflowParserBuilderAdapter.swift\", \"sha256\": \"\(String(repeating: "0", count: 64))\"")
      case .nonApplicablePin:
        try replaceFirst("\"tlcJarSHA256\": \"c48f50b940bbd4852e3fa720a3db565a7c4231a31c84ceb84a34b38706e6940e\"", with: "\"tlcJarSHA256\": \"\(String(repeating: "0", count: 64))\"")
      case .pathEscape:
        try replace("Tests/Fixtures/PublicWorkflowConformance/ParserBuilder/fixture.swift", with: "../outside.swift")
      }
    }

    private func replace(_ target: String, with replacement: String) throws {
      let body = try String(contentsOf: manifest)
      try body.replacingOccurrences(of: target, with: replacement).write(to: manifest, atomically: true, encoding: .utf8)
    }

    private func replaceFirst(_ target: String, with replacement: String) throws {
      let body = try String(contentsOf: manifest)
      if target.contains("9dd427098bbacebacb55a8d16d23853352a4af7dc41a78c3f771db6e2a896442") {
        let currentPackagePin = "b0b438a2d9202d9dd84ab6b9b4c25411690ae4018753802ea148cd481df4beec"
        guard let range = body.range(of: currentPackagePin) else { throw CocoaError(.fileNoSuchFile) }
        try body.replacingCharacters(in: range, with: String(repeating: "0", count: 64)).write(to: manifest, atomically: true, encoding: .utf8)
        return
      }
      guard let range = body.range(of: target) else { throw CocoaError(.fileNoSuchFile) }
      try body.replacingCharacters(in: range, with: replacement).write(to: manifest, atomically: true, encoding: .utf8)
    }

    private func stage(_ relativePath: String) throws {
      let source = sourceRoot.appendingPathComponent(relativePath)
      let destination = root.appendingPathComponent(relativePath)
      try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: source, to: destination)
    }

    private func stageIfAbsent(_ relativePath: String) throws {
      let destination = root.appendingPathComponent(relativePath)
      guard !FileManager.default.fileExists(atPath: destination.path) else { return }
      try stage(relativePath)
    }
  }
}
