import Foundation

/// A stable digest-backed summary of one finite canonical graph.
struct CanonicalGraphReceipt: Hashable, Sendable {
  /// The completion state of a finite graph exploration.
  enum ExplorationStatus: String, Hashable, Sendable {
    case complete
    case bounded
    case failed
  }

  static let format = "canonical-graph-receipt/v1"

  let formatVersion: String
  let compiledModelIdentity: String
  let configurationIdentity: String
  let symmetrySchemaIdentity: String
  let observableNameMappingIdentity: String?
  let explorationStatus: ExplorationStatus
  let maximumStateLimit: Int
  let initialStateCount: Int
  let stateCount: Int
  let edgeCount: Int
  let initialStatesDigest: String
  let statesDigest: String
  let edgesDigest: String
  let graphDigest: String

  init(
    graph: CanonicalGraph,
    compiledModelIdentity: String,
    configurationIdentity: String,
    symmetrySchemaIdentity: String,
    observableNameMappingIdentity: String? = nil,
    explorationStatus: ExplorationStatus,
    maximumStateLimit: Int,
    outcome: CanonicalOutcome,
    diagnostics: [CanonicalDiagnostic] = []
  ) {
    self.formatVersion = Self.format
    self.compiledModelIdentity = compiledModelIdentity
    self.configurationIdentity = configurationIdentity
    self.symmetrySchemaIdentity = symmetrySchemaIdentity
    self.observableNameMappingIdentity = observableNameMappingIdentity
    self.explorationStatus = explorationStatus
    self.maximumStateLimit = maximumStateLimit
    self.initialStateCount = graph.initialStateKeys.count
    self.stateCount = graph.states.count
    self.edgeCount = graph.edgeOccurrences.values.reduce(0, +)

    let initialRecords = graph.initialStateKeys.sorted().map { "initial:\($0.canonicalEncoding)" }
    let stateRecords = graph.states.keys.sorted().map { "state:\($0.canonicalEncoding)" }
    let edgeRecords = graph.edgeOccurrences.keys.sorted().map { edge in
      "edge:\(edge.canonicalEncoding);occurrences:\(graph.edgeOccurrences[edge, default: 0])"
    }
    let outcomeRecords = Self.outcomeRecords(outcome, diagnostics: diagnostics)

    self.initialStatesDigest = Self.digest(initialRecords)
    self.statesDigest = Self.digest(stateRecords)
    self.edgesDigest = Self.digest(edgeRecords)
    self.graphDigest = Self.digest(
      [
        "header:formatVersion:\(self.formatVersion)",
        "header:compiledModelIdentity:\(encodedBytes(self.compiledModelIdentity))",
        "header:configurationIdentity:\(encodedBytes(self.configurationIdentity))",
        "header:symmetrySchemaIdentity:\(encodedBytes(self.symmetrySchemaIdentity))",
        self.observableNameMappingIdentity.map {
          "header:observableNameMappingIdentity:\(encodedBytes($0))"
        },
        "header:explorationStatus:\(self.explorationStatus.rawValue)",
        "header:maximumStateLimit:\(self.maximumStateLimit)",
        "header:initialStateCount:\(self.initialStateCount)",
        "header:stateCount:\(self.stateCount)",
        "header:edgeCount:\(self.edgeCount)"
      ].compactMap { $0 } + initialRecords + stateRecords + edgeRecords + outcomeRecords
    )
  }

  init(
    run: CanonicalRun,
    compiledModelIdentity: String,
    configurationIdentity: String,
    symmetrySchemaIdentity: String,
    observableNameMappingIdentity: String? = nil,
    maximumStateLimit: Int
  ) {
    self.init(
      graph: run.graph,
      compiledModelIdentity: compiledModelIdentity,
      configurationIdentity: configurationIdentity,
      symmetrySchemaIdentity: symmetrySchemaIdentity,
      observableNameMappingIdentity: observableNameMappingIdentity,
      explorationStatus: Self.explorationStatus(for: run),
      maximumStateLimit: maximumStateLimit,
      outcome: run.outcome,
      diagnostics: run.errors
    )
  }

  var supportsExactConformance: Bool {
    explorationStatus == .complete
  }

  private static func outcomeRecords(
    _ outcome: CanonicalOutcome,
    diagnostics: [CanonicalDiagnostic]
  ) -> [String] {
    let outcomeRecord: String
    switch outcome {
    case .exhaustiveSuccess:
      outcomeRecord = "outcome:exhaustiveSuccess"
    case .invariantViolation(let name):
      outcomeRecord = "outcome:invariantViolation:\(encodedBytes(name))"
    case .deadlock(let state):
      outcomeRecord = "outcome:deadlock:\(state.canonicalEncoding)"
    case .incomplete(let reason):
      outcomeRecord = "outcome:incomplete:\(encodedBytes(reason))"
    case .executionError(let message):
      outcomeRecord = "outcome:executionError:\(encodedBytes(message))"
    }
    let diagnosticRecords = diagnostics
      .map { "diagnostic:\(encodedBytes($0.code)):\(encodedBytes($0.message))" }
      .sorted(by: canonicalBytes)
    return [outcomeRecord] + diagnosticRecords
  }

  private static func explorationStatus(for run: CanonicalRun) -> ExplorationStatus {
    if !run.errors.isEmpty { return .failed }
    if case .incomplete = run.outcome { return .bounded }
    if case .executionError = run.outcome { return .failed }
    return .complete
  }

  private static func digest(_ records: [String]) -> String {
    SHA256.hex(Data(records.joined(separator: "\n").utf8))
  }
}
