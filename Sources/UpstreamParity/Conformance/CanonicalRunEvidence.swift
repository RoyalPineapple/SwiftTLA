import Foundation

enum CanonicalRunEvidenceError: Error {
  case invalidRecord
}

struct CanonicalRunEvidence: Codable, Sendable {
  struct Correlation: Codable, Equatable, Sendable {
    let caseID: String
    let runID: UUID
    let engine: CoreConformanceEngine

    init(_ correlation: CoreConformanceCorrelation) {
      caseID = correlation.caseID
      runID = correlation.runID
      engine = correlation.engine
    }

    func matches(caseID: String, runID: UUID, engine: CoreConformanceEngine) -> Bool {
      self.caseID == caseID && self.runID == runID && self.engine == engine
    }
  }

  struct ReceiptContext: Codable, Equatable, Sendable {
    let compiledModelIdentity: String
    let configurationIdentity: String
    let symmetrySchemaIdentity: String
    let observableNameMappingIdentity: String?
    let maximumStateLimit: Int
  }

  struct Graph: Codable, Sendable {
    struct Chunk: Codable, Sendable {
      let file: String
      let digest: String
      let recordCount: Int
    }

    let digest: String
    let chunks: [Chunk]
  }

  struct Outcome: Codable, Sendable {
    let kind: String
    let message: String?
    let state: String?

    init(_ outcome: CanonicalOutcome) {
      switch outcome {
      case .exhaustiveSuccess:
        kind = "exhaustiveSuccess"
        message = nil
        state = nil
      case .invariantViolation(let message):
        kind = "invariantViolation"
        self.message = message
        state = nil
      case .deadlock(let state):
        kind = "deadlock"
        message = nil
        self.state = state.canonicalEncoding
      case .incomplete(let message):
        kind = "incomplete"
        self.message = message
        state = nil
      case .executionError(let message):
        kind = "executionError"
        self.message = message
        state = nil
      }
    }

    func canonicalOutcome() throws -> CanonicalOutcome {
      switch (kind, message, state) {
      case ("exhaustiveSuccess", nil, nil): .exhaustiveSuccess
      case ("invariantViolation", let message?, nil) where !message.isEmpty: .invariantViolation(message)
      case ("deadlock", nil, let state?): .deadlock(.init(canonicalEncoding: state))
      case ("incomplete", let message?, nil) where !message.isEmpty: .incomplete(reason: message)
      case ("executionError", let message?, nil) where !message.isEmpty: .executionError(message)
      default: throw CanonicalRunEvidenceError.invalidRecord
      }
    }
  }

  struct Trace: Codable, Sendable {
    struct Step: Codable, Sendable {
      let state: String
      let action: String
    }

    let id: String
    let steps: [Step]
  }

  static let format = "canonical-run-evidence"

  let format: String
  let correlation: Correlation
  let receiptContext: ReceiptContext
  let schema: String
  let graph: Graph
  let observableActions: [String]
  let outcome: Outcome
  let errors: [CanonicalDiagnosticRecord]
  let traces: [Trace]

  private init(
    run: CanonicalRun,
    correlation: CoreConformanceCorrelation,
    receiptContext: ReceiptContext,
    graph: Graph
  ) {
    format = Self.format
    self.correlation = .init(correlation)
    self.receiptContext = receiptContext
    schema = run.schema.rawValue
    self.graph = graph
    observableActions = run.observableActions.sorted()
    outcome = .init(run.outcome)
    errors = run.errors.map { .init(code: $0.code, message: $0.message) }
    traces = run.traces.map { trace in
      .init(
        id: trace.id,
        steps: trace.steps.map { .init(state: $0.state.canonicalEncoding, action: $0.action) }
      )
    }
  }

  static func write(
    _ run: CanonicalRun,
    correlation: CoreConformanceCorrelation,
    receiptContext: ReceiptContext,
    to url: URL
  ) throws {
    let receipt = CanonicalGraphReceipt(
      run: run,
      compiledModelIdentity: receiptContext.compiledModelIdentity,
      configurationIdentity: receiptContext.configurationIdentity,
      symmetrySchemaIdentity: receiptContext.symmetrySchemaIdentity,
      observableNameMappingIdentity: receiptContext.observableNameMappingIdentity,
      maximumStateLimit: receiptContext.maximumStateLimit
    )
    let directoryName = url.deletingPathExtension().lastPathComponent + ".graph"
    let directory = url.deletingLastPathComponent().appendingPathComponent(directoryName, isDirectory: true)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let chunks = CanonicalGraphReceipt.graphRecordChunks(for: run.graph)
    guard chunks.count == receipt.graphChunkDigests.count else {
      throw CanonicalRunEvidenceError.invalidRecord
    }
    let manifest = try zip(chunks, receipt.graphChunkDigests).enumerated().map { index, pair in
      let file = String(format: "%06d.jsonl", index)
      let data = Data(pair.0.joined(separator: "\n").utf8)
      guard SHA256.hex(data) == pair.1 else { throw CanonicalRunEvidenceError.invalidRecord }
      try data.write(to: directory.appendingPathComponent(file), options: .atomic)
      return Graph.Chunk(file: file, digest: pair.1, recordCount: pair.0.count)
    }
    let evidence = Self(
      run: run,
      correlation: correlation,
      receiptContext: receiptContext,
      graph: .init(digest: receipt.graphDigest, chunks: manifest)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(evidence).write(to: url, options: .atomic)
  }

  static func read(from url: URL) throws -> (evidence: CanonicalRunEvidence, run: CanonicalRun) {
    let evidence = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    return (evidence, try evidence.canonicalRun(readingChunksBeside: url))
  }

  func canonicalRun(readingChunksBeside url: URL) throws -> CanonicalRun {
    guard format == Self.format,
          !correlation.caseID.isEmpty,
          strictlySortedUnique(observableActions),
          !graph.chunks.isEmpty
    else { throw CanonicalRunEvidenceError.invalidRecord }

    let directory = url.deletingLastPathComponent().appendingPathComponent(
      url.deletingPathExtension().lastPathComponent + ".graph", isDirectory: true)
    let expectedFiles = Set(graph.chunks.map(\.file))
    guard Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)) == expectedFiles else {
      throw CanonicalRunEvidenceError.invalidRecord
    }
    let chunkRecords = try graph.chunks.enumerated().map { index, chunk -> [String] in
      let expectedFile = String(format: "%06d.jsonl", index)
      guard chunk.file == expectedFile, chunk.recordCount > 0 else {
        throw CanonicalRunEvidenceError.invalidRecord
      }
      let data = try Data(contentsOf: directory.appendingPathComponent(chunk.file))
      guard SHA256.hex(data) == chunk.digest,
            let source = String(data: data, encoding: .utf8),
            !source.isEmpty,
            !source.hasSuffix("\n")
      else { throw CanonicalRunEvidenceError.invalidRecord }
      let records = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      guard records.count == chunk.recordCount else { throw CanonicalRunEvidenceError.invalidRecord }
      return records
    }
    let run = try canonicalRun(records: chunkRecords.flatMap { $0 })
    let receipt = CanonicalGraphReceipt(
      run: run,
      compiledModelIdentity: receiptContext.compiledModelIdentity,
      configurationIdentity: receiptContext.configurationIdentity,
      symmetrySchemaIdentity: receiptContext.symmetrySchemaIdentity,
      observableNameMappingIdentity: receiptContext.observableNameMappingIdentity,
      maximumStateLimit: receiptContext.maximumStateLimit
    )
    guard receipt.graphDigest == graph.digest,
          receipt.graphChunkDigests == graph.chunks.map(\.digest),
          CanonicalGraphReceipt.graphRecordChunks(for: run.graph) == chunkRecords
    else { throw CanonicalRunEvidenceError.invalidRecord }
    return run
  }

  private func canonicalRun(records: [String]) throws -> CanonicalRun {
    var initialStates: [CanonicalState] = []
    var states: [CanonicalState] = []
    var edges: [CanonicalEdge] = []
    for record in records {
      if record.hasPrefix("initial:") {
        initialStates.append(try CanonicalWireDecoder.state(String(record.dropFirst("initial:".count))))
      } else if record.hasPrefix("state:") {
        states.append(try CanonicalWireDecoder.state(String(record.dropFirst("state:".count))))
      } else if record.hasPrefix("edge:") {
        guard let delimiter = record.range(of: ";occurrences:", options: .backwards),
              let count = Int(record[delimiter.upperBound...]), count > 0
        else { throw CanonicalRunEvidenceError.invalidRecord }
        let edge = try CanonicalWireDecoder.edge(String(record[..<delimiter.lowerBound]))
        edges.append(contentsOf: repeatElement(edge, count: count))
      } else {
        throw CanonicalRunEvidenceError.invalidRecord
      }
    }
    guard !states.isEmpty,
          strictlySortedUnique(states.map(\.canonicalEncoding)),
          strictlySortedUnique(initialStates.map(\.canonicalEncoding)),
          Set(initialStates.map(\.key)).isSubset(of: Set(states.map(\.key)))
    else { throw CanonicalRunEvidenceError.invalidRecord }
    let canonicalGraph = try CanonicalGraph(initialStates: initialStates, states: states, edges: edges)
    return try CanonicalRun(
      schema: try CanonicalSchema(validating: schema),
      graph: canonicalGraph,
      observableActions: Set(observableActions),
      outcome: try outcome.canonicalOutcome(),
      errors: errors.map { .init(code: $0.code, message: $0.message) },
      traces: traces.map { trace in
        .init(
          id: trace.id,
          steps: trace.steps.map { .init(state: .init(canonicalEncoding: $0.state), action: $0.action) }
        )
      }
    )
  }

  private func strictlySortedUnique(_ values: [String]) -> Bool {
    zip(values, values.dropFirst()).allSatisfy { canonicalBytes($0, $1) }
  }
}

struct CanonicalDiagnosticRecord: Codable, Sendable {
  let code: String
  let message: String
}

private enum CanonicalWireDecoder {
  static func edge(_ encoding: String) throws -> CanonicalEdge {
    guard encoding.hasPrefix("edge:"),
          let sourceEnd = encoding.range(of: "--"),
          let targetStart = encoding.range(of: "-->", options: .backwards)
    else { throw CanonicalRunEvidenceError.invalidRecord }
    let source = String(encoding.dropFirst("edge:".count)[..<sourceEnd.lowerBound])
    let action = try decodeHex(String(encoding[sourceEnd.upperBound..<targetStart.lowerBound]))
    let target = String(encoding[targetStart.upperBound...])
    guard !action.isEmpty else { throw CanonicalRunEvidenceError.invalidRecord }
    let edge = CanonicalEdge(
      source: .init(canonicalEncoding: source), action: action,
      target: .init(canonicalEncoding: target)
    )
    guard edge.canonicalEncoding == encoding else { throw CanonicalRunEvidenceError.invalidRecord }
    return edge
  }

  static func decodeHex(_ hex: String) throws -> String {
    guard hex.count.isMultiple(of: 2),
          let value = String(bytes: stride(from: 0, to: hex.count, by: 2).compactMap {
            UInt8(hex.dropFirst($0).prefix(2), radix: 16)
          }, encoding: .utf8), value.utf8.count * 2 == hex.count
    else { throw CanonicalRunEvidenceError.invalidRecord }
    return value
  }

  static func state(_ encoding: String) throws -> CanonicalState {
    var parser = Parser(encoding)
    try parser.consume("state:[")
    var bindings: [String: CanonicalValue] = [:]
    if !parser.consumeIf("]") {
      while true {
        let name = try parser.hexString(until: "=")
        try parser.consume("=")
        let value = try parser.value()
        guard bindings[name] == nil else { throw CanonicalRunEvidenceError.invalidRecord }
        bindings[name] = value
        if parser.consumeIf("]") { break }
        try parser.consume(",")
      }
    }
    guard parser.isAtEnd else { throw CanonicalRunEvidenceError.invalidRecord }
    let state = CanonicalState(bindings: bindings)
    guard state.key.canonicalEncoding == encoding else { throw CanonicalRunEvidenceError.invalidRecord }
    return state
  }

  private struct Parser {
    let characters: [Character]
    var index = 0

    init(_ source: String) { characters = Array(source) }
    var isAtEnd: Bool { index == characters.count }

    mutating func consume(_ literal: String) throws {
      guard Array(characters[index...]).starts(with: Array(literal)) else {
        throw CanonicalRunEvidenceError.invalidRecord
      }
      index += literal.count
    }

    mutating func consumeIf(_ literal: Character) -> Bool {
      guard index < characters.count, characters[index] == literal else { return false }
      index += 1
      return true
    }

    mutating func hexString(until terminator: Character) throws -> String {
      let start = index
      while index < characters.count, characters[index] != terminator { index += 1 }
      guard index > start, index < characters.count else { throw CanonicalRunEvidenceError.invalidRecord }
      let hex = String(characters[start..<index])
      guard hex.allSatisfy({ $0.isHexDigit }) else { throw CanonicalRunEvidenceError.invalidRecord }
      return try CanonicalWireDecoder.decodeHex(hex)
    }

    mutating func value() throws -> CanonicalValue {
      if consumeIfPrefix("integer:") { return .integer(try integer()) }
      if consumeIfPrefix("boolean:true") { return .boolean(true) }
      if consumeIfPrefix("boolean:false") { return .boolean(false) }
      if consumeIfPrefix("string:") { return .string(try hexValue()) }
      if consumeIfPrefix("constant:") { return .constant(try hexValue()) }
      if consumeIfPrefix("set:[") { return .set(try values(closing: "]")) }
      if consumeIfPrefix("tuple:[") { return .tuple(try values(closing: "]")) }
      if consumeIfPrefix("record:[") { return .record(try record()) }
      if consumeIfPrefix("function:[") { return try .function(try function()) }
      throw CanonicalRunEvidenceError.invalidRecord
    }

    mutating func consumeIfPrefix(_ literal: String) -> Bool {
      guard Array(characters[index...]).starts(with: Array(literal)) else { return false }
      index += literal.count
      return true
    }

    mutating func integer() throws -> Int {
      let start = index
      if index < characters.count, characters[index] == "-" { index += 1 }
      while index < characters.count, characters[index].isNumber { index += 1 }
      guard let value = Int(String(characters[start..<index])) else { throw CanonicalRunEvidenceError.invalidRecord }
      return value
    }

    mutating func hexValue() throws -> String {
      let start = index
      while index < characters.count, characters[index].isHexDigit { index += 1 }
      let hex = String(characters[start..<index])
      return try CanonicalWireDecoder.decodeHex(hex)
    }

    mutating func values(closing: Character) throws -> [CanonicalValue] {
      if consumeIf(closing) { return [] }
      var result: [CanonicalValue] = []
      while true {
        result.append(try value())
        if consumeIf(closing) { return result }
        try consume(",")
      }
    }

    mutating func record() throws -> [String: CanonicalValue] {
      if consumeIf("]") { return [:] }
      var result: [String: CanonicalValue] = [:]
      while true {
        let name = try hexString(until: "=")
        try consume("=")
        guard result[name] == nil else { throw CanonicalRunEvidenceError.invalidRecord }
        result[name] = try value()
        if consumeIf("]") { return result }
        try consume(",")
      }
    }

    mutating func function() throws -> [CanonicalFunctionEntry] {
      if consumeIf("]") { return [] }
      var result: [CanonicalFunctionEntry] = []
      while true {
        let key = try value()
        try consume("=>")
        result.append(.init(key: key, value: try value()))
        if consumeIf("]") { return result }
        try consume(",")
      }
    }
  }
}
