import Foundation
import Testing
import UpstreamParity

struct CoreConformanceFixtureContractTests {
  @Test("bounded elevator wrapper provenance is ordered and declares its only value normalization")
  func declaresOrderedElevatorInvocationMappings() throws {
    let manifest = try JSONDecoder().decode(
      CoreConformanceCasesManifest.self,
      from: fixtureData("cases.json"))
    let elevator = try #require(manifest.cases.first { $0.id == "multicar-elevator" })

    #expect(elevator.invocationMappings.count == 80)
    #expect(elevator.invocationMappings.first?.wrapper == "request__0_0_0")
    #expect(elevator.invocationMappings.first?.action == "request")
    #expect(elevator.invocationMappings.first?.arguments == ["\"alice\"", "0", "\"up\""])
    #expect(elevator.invocationMappings.last?.wrapper == "completeRide__1_1_2")
    #expect(Set(elevator.invocationMappings.map(\.wrapper)).count == 80)
    #expect(Set(elevator.invocationMappings.map(\.runtimeValue.swiftLabel)).count == 80)
    #expect(elevator.valueNormalizations.count == 1)
    #expect(elevator.valueNormalizations.first?.binding == "cars")
    #expect(elevator.valueNormalizations.first?.functionKeys == ["\"carA\"": "carA", "\"carB\"": "carB"])

  }

  @Test("retained adversarial fixture preserves the complete labeled graph relation")
  func preservesAdversarialGraphContract() throws {
    let expectedCase = adversarialFixtureCase()
    let data = try fixtureData("spike/run-1/events.jsonl")
    let parser = TLCGraphEventParser(expectedCase: expectedCase)
    let stream = try parser.parse(data)
    let run = try parser.parseCanonicalRun(
      data,
      result: TLCProcessResult(
        status: 0,
        stdout: "Model checking completed. No error has been found.",
        stderr: ""
      )
    )

    #expect(stream.initialStates.map(xValue) == ["0", "1"])
    #expect(stream.transitions.count == 9)
    #expect(stream.transitions.filter { $0.action == "ToMidA" }.count == 2)
    #expect(stream.transitions.filter { $0.action == "ToMidB" }.count == 2)
    let repeatedEdges = stream.transitions.filter { $0.action == "Repeat" }
    #expect(repeatedEdges.count == 2)
    #expect(repeatedEdges.contains { !$0.seen })
    #expect(repeatedEdges.contains { $0.seen })
    #expect(
      stream.transitions.contains {
        $0.action == "SelfLoop" && xValue($0.source) == "3" && xValue($0.target) == "3"
          && $0.seen
      })

    let terminal = try #require(run.graph.states.values.first { $0.bindings["x"] == .integer(5) })
    #expect(run.graph.observations[terminal.key]?.isTerminal == true)
    #expect(run.graph.edgeOccurrences.values.reduce(0, +) == 9)

    let expectedEdges = run.graph.edgeOccurrences.flatMap { edge, count in
      Array(repeating: edge, count: count)
    }
    var changedEdges = expectedEdges
    let changedIndex = try #require(changedEdges.firstIndex { $0.action == "SelfLoop" })
    let original = changedEdges[changedIndex]
    changedEdges[changedIndex] = CanonicalEdge(
      source: original.source,
      action: "WrongSelfLoop",
      target: original.target
    )
    let states = Array(run.graph.states.values)
    let initialStates = run.graph.initialStateKeys.compactMap { run.graph.states[$0] }
    let changedGraph = try CanonicalGraph(
      initialStates: initialStates,
      states: states,
      edges: changedEdges
    )
    let changedRun = try CanonicalRun(
      graph: changedGraph,
      observableActions: Set(changedEdges.map(\.action)),
      outcome: .exhaustiveSuccess
    )

    let comparison = exactFiniteTLCGraph(expected: run, actual: changedRun)
    #expect(!comparison.isConformant)
    #expect(comparison.differences.contains { $0.category == .edges })
  }

  @Test("retained corrupt graph fixtures fail closed")
  func rejectsRetainedCorruptFixtures() throws {
    let parser = TLCGraphEventParser(expectedCase: adversarialFixtureCase())
    let corruptFixtures = [
      "altered-payload",
      "altered-provenance",
      "bad-sequence",
      "duplicate-key",
      "invalid-utf8",
      "missing-footer",
      "truncated",
      "unknown-field",
      "unknown-type",
      "unsupported"
    ]

    for name in corruptFixtures {
      #expect(throws: TLCGraphEventError.self) {
        try parser.parse(fixtureData("spike/corrupt/\(name).jsonl"))
      }
    }

    let invalidUTF8 = try fixtureData("spike/corrupt/invalid-utf8.jsonl")
    let separator = try #require(invalidUTF8.dropLast().lastIndex(of: 10))
    let body = Data(invalidUTF8[..<invalidUTF8.index(after: separator)])
    let footer = try #require(
      String(data: invalidUTF8[invalidUTF8.index(after: separator)...], encoding: .utf8)
    )
    let footerDigest = try #require(
      footer.split(separator: "\"bodySha256\":\"").dropFirst().first?.split(separator: "\"").first
    )
    #expect(SHA256.hex(body) == footerDigest)
  }

  @Test("DOT, traces, and graph streams cannot substitute for each other")
  func rejectsCrossFormatEvidence() throws {
    let graphParser = TLCGraphEventParser(expectedCase: adversarialFixtureCase())
    let traceParser = TLCTraceParser()
    let graph = try fixtureData("spike/run-1/events.jsonl")
    let dot = try fixtureData("spike/run-1/graph.dot")
    let trace = try fixtureData("spike/violation/counterexample.json")

    #expect(throws: TLCGraphEventError.self) { try graphParser.parse(dot) }
    #expect(throws: TLCGraphEventError.self) { try graphParser.parse(trace) }
    #expect(throws: TLCTraceError.self) { try traceParser.parseCounterexample(graph) }
    #expect(throws: TLCTraceError.self) { try traceParser.parseCounterexample(dot) }
  }

  private func xValue(_ state: TLCGraphState) -> String? {
    state.bindings.first { $0.name == "x" }?.tla
  }

  private func adversarialFixtureCase() -> CoreConformanceCase {
    let module = fixtureURL("Tools/TLCGraphBridge/spike/BridgeGraph.tla")
    let configuration = fixtureURL("Tools/TLCGraphBridge/spike/BridgeGraph.cfg")
    let arguments = ["-workers", "1", "-fp", "1", "-seed", "1", "-deadlock"]
    return try! CoreConformanceCase(
      id: "adversarial-core-graph-v1",
      moduleSHA256: SHA256.hex(try! Data(contentsOf: module)),
      cfgSHA256: SHA256.hex(try! Data(contentsOf: configuration)),
      arguments: arguments,
      argumentsSHA256: CoreConformanceCase.argumentsDigest(arguments),
      workers: 1,
      fingerprintPolynomial: 1,
      deadlock: false,
      operatingSystem: "macos",
      architecture: "arm64",
      environment: [:],
      pin: .fixture
    )
  }

  private func fixtureData(_ path: String) throws -> Data {
    try Data(contentsOf: fixtureURL("Verification/CoreConformance/\(path)"))
  }

  private func fixtureURL(_ path: String) -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(path)
      .standardizedFileURL
  }
}
