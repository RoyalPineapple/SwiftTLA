import Foundation

package enum CanonicalConformanceEvidenceError: Error {
  case invalidRecord
}

package struct CanonicalConformanceEvidence: Codable, Sendable {
  package struct RunReference: Codable, Equatable, Sendable {
    let run: CoreEvidenceReference
    let chunks: [CoreEvidenceReference]
  }

  package struct Comparison: Codable, Sendable {
    let conformant: Bool
    let differencesSHA256: String
    let differenceCategories: [ConformanceDifferenceCategory]
    let expectedReceipt: CanonicalGraphReceipt
    let actualReceipt: CanonicalGraphReceipt
  }

  package struct Loaded: Sendable {
    let evidence: CanonicalConformanceEvidence
    let swiftRun: CanonicalRun
    let tlcRun: CanonicalRun
    let comparison: ExactFiniteTLCComparison
  }

  static let format = "canonical-conformance-evidence"

  let format: String
  let correlation: CanonicalRunEvidence.Correlation
  let swift: RunReference
  let tlc: RunReference
  let comparison: Comparison

  static func writeSwiftRun(
    _ run: CanonicalRun,
    correlation: CoreConformanceCorrelation,
    receiptContext: CanonicalRunEvidence.ReceiptContext,
    to directory: URL
  ) throws {
    try CanonicalRunEvidence.write(
      run,
      correlation: correlation,
      receiptContext: receiptContext,
      to: directory.appendingPathComponent("swift-run.json")
    )
  }

  static func write(
    swift swiftRun: CanonicalRun,
    tlc tlcRun: CanonicalRun,
    correlations: Correlations,
    receiptContext: CanonicalRunEvidence.ReceiptContext,
    to directory: URL
  ) throws -> ExactFiniteTLCComparison {
    let swiftURL = directory.appendingPathComponent("swift-run.json")
    let tlcURL = directory.appendingPathComponent("tlc-run.json")
    try writeSwiftRun(
      swiftRun,
      correlation: correlations.swift,
      receiptContext: receiptContext,
      to: directory
    )
    try CanonicalRunEvidence.write(
      tlcRun,
      correlation: correlations.tlc,
      receiptContext: receiptContext,
      to: tlcURL
    )

    let exact = exactFiniteTLCGraph(
      expected: tlcRun,
      actual: swiftRun,
      compiledModelIdentity: receiptContext.compiledModelIdentity,
      configurationIdentity: receiptContext.configurationIdentity,
      symmetrySchemaIdentity: receiptContext.symmetrySchemaIdentity,
      maximumStateLimit: receiptContext.maximumStateLimit,
      observableNameMappingIdentity: receiptContext.observableNameMappingIdentity
    )
    guard let expectedReceipt = exact.expectedReceipt,
          let actualReceipt = exact.actualReceipt else {
      throw CanonicalConformanceEvidenceError.invalidRecord
    }

    let evidence = Self(
      format: Self.format,
      correlation: .init(correlations.runner),
      swift: try runReference(for: swiftURL, beneath: directory),
      tlc: try runReference(for: tlcURL, beneath: directory),
      comparison: try Comparison(
        exact,
        expectedReceipt: expectedReceipt,
        actualReceipt: actualReceipt
      )
    )
    try ConformanceEvidence.writePrettyCanonical(
      evidence,
      to: directory.appendingPathComponent("core-decision.json")
    )
    return exact
  }

  static func read(from directory: URL) throws -> Loaded {
    let evidenceURL = directory.appendingPathComponent("core-decision.json")
    let evidence = try JSONDecoder().decode(Self.self, from: Data(contentsOf: evidenceURL))
    guard evidence.format == Self.format,
          evidence.correlation.engine == .runner,
          evidence.correlation.caseID.isEmpty == false else {
      throw CanonicalConformanceEvidenceError.invalidRecord
    }

    let swiftURL = try verifiedURL(for: evidence.swift.run, beneath: directory)
    let tlcURL = try verifiedURL(for: evidence.tlc.run, beneath: directory)
    try verifyChunks(evidence.swift.chunks, beneath: directory)
    try verifyChunks(evidence.tlc.chunks, beneath: directory)
    guard try runReference(for: swiftURL, beneath: directory) == evidence.swift,
          try runReference(for: tlcURL, beneath: directory) == evidence.tlc else {
      throw CanonicalConformanceEvidenceError.invalidRecord
    }
    let swift = try CanonicalRunEvidence.read(from: swiftURL)
    let tlc = try CanonicalRunEvidence.read(from: tlcURL)
    guard swift.evidence.correlation.engine == .swift,
          tlc.evidence.correlation.engine == .tlc,
          swift.evidence.correlation.caseID == evidence.correlation.caseID,
          tlc.evidence.correlation.caseID == evidence.correlation.caseID,
          swift.evidence.correlation.runID == evidence.correlation.runID,
          tlc.evidence.correlation.runID == evidence.correlation.runID,
          swift.evidence.receiptContext == tlc.evidence.receiptContext else {
      throw CanonicalConformanceEvidenceError.invalidRecord
    }

    let context = swift.evidence.receiptContext
    let exact = exactFiniteTLCGraph(
      expected: tlc.run,
      actual: swift.run,
      compiledModelIdentity: context.compiledModelIdentity,
      configurationIdentity: context.configurationIdentity,
      symmetrySchemaIdentity: context.symmetrySchemaIdentity,
      maximumStateLimit: context.maximumStateLimit,
      observableNameMappingIdentity: context.observableNameMappingIdentity
    )
    guard let expectedReceipt = exact.expectedReceipt,
          let actualReceipt = exact.actualReceipt else {
      throw CanonicalConformanceEvidenceError.invalidRecord
    }
    let verifiedComparison = try Comparison(
      exact,
      expectedReceipt: expectedReceipt,
      actualReceipt: actualReceipt
    )
    guard verifiedComparison == evidence.comparison else {
      throw CanonicalConformanceEvidenceError.invalidRecord
    }
    return Loaded(evidence: evidence, swiftRun: swift.run, tlcRun: tlc.run, comparison: exact)
  }

  private static func runReference(for runURL: URL, beneath directory: URL) throws -> RunReference {
    let graphDirectory = runURL.deletingPathExtension().appendingPathExtension("graph")
    let chunks = try FileManager.default.contentsOfDirectory(
      at: graphDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard chunks.isEmpty == false else { throw CanonicalConformanceEvidenceError.invalidRecord }
    return RunReference(
      run: try ConformanceEvidence.reference(for: runURL, beneath: directory),
      chunks: try chunks.map { try ConformanceEvidence.reference(for: $0, beneath: directory) }
    )
  }

  private static func verifiedURL(for reference: CoreEvidenceReference, beneath directory: URL) throws -> URL {
    _ = try ConformanceEvidence.data(for: reference, beneath: directory)
    return try ConformanceEvidence.resolve(
      directory.appendingPathComponent(reference.path),
      beneath: directory
    )
  }

  private static func verifyChunks(_ references: [CoreEvidenceReference], beneath directory: URL) throws {
    guard references.isEmpty == false,
          Set(references.map(\.path)).count == references.count else {
      throw CanonicalConformanceEvidenceError.invalidRecord
    }
    for reference in references {
      _ = try ConformanceEvidence.data(for: reference, beneath: directory)
    }
  }

}

extension CanonicalConformanceEvidence.Comparison: Equatable {
  fileprivate init(
    _ comparison: ExactFiniteTLCComparison,
    expectedReceipt: CanonicalGraphReceipt,
    actualReceipt: CanonicalGraphReceipt
  ) throws {
    let data = try JSONSerialization.data(
      withJSONObject: comparisonDifferencesJSON(comparison),
      options: [.sortedKeys]
    )
    conformant = comparison.isConformant
    differencesSHA256 = SHA256.hex(data)
    differenceCategories = comparison.differences.map(\.category)
    self.expectedReceipt = expectedReceipt
    self.actualReceipt = actualReceipt
  }
}

func correlationJSON(_ correlation: CoreConformanceCorrelation) -> [String: String] {
  [
    "caseID": correlation.caseID,
    "runID": correlation.runID.uuidString.lowercased(),
    "engine": correlation.engine.rawValue
  ]
}

func failureReportJSON(_ report: ConformanceFailureReport) -> [String: Any] {
  [
    "whatFailed": report.whatFailed,
    "whereItFailed": report.whereItFailed,
    "expected": report.expected,
    "actual": report.actual,
    "nextSafeAction": report.nextSafeAction,
    "evidence": report.evidence.map { ["role": $0.role, "location": $0.location] },
    "toolOutput": report.toolOutput.map { ["stream": $0.stream, "content": $0.content] }
  ]
}
