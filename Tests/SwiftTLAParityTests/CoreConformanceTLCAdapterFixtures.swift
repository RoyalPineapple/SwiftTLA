import Darwin
import Foundation
import os
import Testing
import UpstreamParity

func completeGraphStream(_ expectedCase: CoreConformanceCase) -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let state0: [String: Any] = ["fingerprint": "1", "level": 1, "bindings": [binding(0, "x", "0")]]
  let state1: [String: Any] = ["fingerprint": "2", "level": 2, "bindings": [binding(0, "x", "1")]]
  let headerData = Data(header(expectedCase).utf8)
  let initial: [String: Any] = record(
    "initial", 1, runID, expectedCase.id, ["callback": "writeState.initial", "state": state0])
  let transition: [String: Any] = record(
    "transition", 2, runID, expectedCase.id,
    [
      "callback": "writeState.action", "source": state0, "target": state1,
      "action": ["name": "Next", "location": "", "named": true],
      "stateFlags": ["raw": 0, "seen": false, "notInModel": false],
      "visualization": "none", "predicateLocation": NSNull(), "reachable": "reachable"
    ])
  let body = [headerData, jsonLine(initial), jsonLine(transition)].reduce(into: Data()) {
    $0.append($1)
    $0.append(10)
  }
  let footer: [String: Any] = record(
    "footer", 3, runID, expectedCase.id,
    [
      "callback": "writer.close", "status": "closed",
      "counts": ["header": 1, "initial": 1, "transition": 1],
      "lastBodySeq": 2, "bodySha256": SHA256.hex(body)
    ])
  return body + jsonLine(footer) + Data([10])
}
func completeGraphStreamWithStutteringObservation(_ expectedCase: CoreConformanceCase) -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let lines = String(decoding: completeGraphStream(expectedCase), as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  let header = Data((lines[0] + "\n").utf8)
  let initial = Data((lines[1] + "\n").utf8)
  let transition = Data((lines[2] + "\n").utf8)
  let stutter = jsonLine(record(
    "unsupported", 3, runID, expectedCase.id,
    ["callback": "writeState.visualization", "reason": "callback has no Action identity: STUTTERING"]
  )) + Data([10])
  let body = header + initial + transition + stutter
  let footer = jsonLine(record(
    "footer", 4, runID, expectedCase.id,
    [
      "callback": "writer.close", "status": "closed",
      "counts": ["header": 1, "initial": 1, "transition": 1, "unsupported": 1],
      "lastBodySeq": 3, "bodySha256": SHA256.hex(body)
    ]
  )) + Data([10])
  return body + footer
}
func completeGraphStreamWithExcludedPredicateObservation(_ expectedCase: CoreConformanceCase) -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let lines = String(decoding: completeGraphStream(expectedCase), as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  let header = Data((lines[0] + "\n").utf8)
  let initial = Data((lines[1] + "\n").utf8)
  let transition = Data((lines[2] + "\n").utf8)
  let state: [String: Any] = ["fingerprint": "3", "level": 2, "bindings": [binding(0, "x", "2")]]
  let excluded = jsonLine(record(
    "transition", 3, runID, expectedCase.id,
    [
      "callback": "writeState.actionPredicate", "source": state, "target": state,
      "action": ["name": "Next", "location": "<Next(2) line 1, col 1 to line 1, col 2 of module Fixture>", "named": true],
      "stateFlags": ["raw": 2, "seen": false, "notInModel": true],
      "visualization": "none", "predicateLocation": "line 1, col 1 to line 1, col 2 of module Fixture", "reachable": "excluded"
    ])) + Data([10])
  let body = header + initial + transition + excluded
  let footer = jsonLine(record(
    "footer", 4, runID, expectedCase.id,
    [
      "callback": "writer.close", "status": "closed",
      "counts": ["header": 1, "initial": 1, "transition": 2],
      "lastBodySeq": 3, "bodySha256": SHA256.hex(body)
    ]
  )) + Data([10])
  return body + footer
}
func fingerprintAliasGraphStream(
  _ expectedCase: CoreConformanceCase, aliasSeen: Bool, aliasFingerprint: String = "2"
) -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let state0: [String: Any] = ["fingerprint": "1", "level": 1, "bindings": [binding(0, "x", "0")]]
  let representative: [String: Any] = ["fingerprint": "2", "level": 2, "bindings": [binding(0, "x", "1")]]
  let alias: [String: Any] = ["fingerprint": aliasFingerprint, "level": 2, "bindings": [binding(0, "x", "2")]]
  let headerData = Data(header(expectedCase).utf8)
  let initial = record(
    "initial", 1, runID, expectedCase.id, ["callback": "writeState.initial", "state": state0])
  let first = record(
    "transition", 2, runID, expectedCase.id,
    [
      "callback": "writeState.action", "source": state0, "target": representative,
      "action": ["name": "Next", "location": "", "named": true],
      "stateFlags": ["raw": 0, "seen": false, "notInModel": false],
      "visualization": "none", "predicateLocation": NSNull(), "reachable": "reachable"
    ])
  let second = record(
    "transition", 3, runID, expectedCase.id,
    [
      "callback": "writeState.action", "source": state0, "target": alias,
      "action": ["name": "Next", "location": "", "named": true],
      "stateFlags": ["raw": 1, "seen": aliasSeen, "notInModel": false],
      "visualization": "none", "predicateLocation": NSNull(), "reachable": "reachable"
    ])
  let body = [headerData, jsonLine(initial), jsonLine(first), jsonLine(second)].reduce(into: Data()) {
    $0.append($1)
    $0.append(10)
  }
  let footer = jsonLine(record(
    "footer", 4, runID, expectedCase.id,
    [
      "callback": "writer.close", "status": "closed",
      "counts": ["header": 1, "initial": 1, "transition": 2],
      "lastBodySeq": 3, "bodySha256": SHA256.hex(body)
    ]
  )) + Data([10])
  return body + footer
}
func binding(_ ordinal: Int, _ name: String, _ tla: String) -> [String: Any] {
  ["ordinal": ordinal, "name": name, "tla": tla, "tlaSha256": SHA256.hex(Data(tla.utf8))]
}
func record(
  _ type: String, _ sequence: Int, _ runID: String, _ caseID: String, _ fields: [String: Any]
) -> [String: Any] {
  fields.merging([
    "schema": "swifttla.tlc.graph-events", "version": 1, "type": type, "seq": sequence,
    "runId": runID, "caseId": caseID
  ]) { _, new in new }
}
func jsonLine(_ object: [String: Any]) -> Data {
  try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
func fixtureCase(
  _ pin: TLCReferencePin,
  arguments: [String] = [],
  invocationMappings: [CoreConformanceInvocationMapping] = [],
  valueNormalizations: [CoreConformanceValueNormalization] = []
)
  -> CoreConformanceCase {
  try! CoreConformanceCase(
    id: "fixture", moduleSHA256: String(repeating: "c", count: 64),
    cfgSHA256: String(repeating: "d", count: 64),
    arguments: arguments, argumentsSHA256: CoreConformanceCase.argumentsDigest(arguments),
    workers: 1,
    fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: "arm64",
    environment: [:], pin: pin, invocationMappings: invocationMappings,
    valueNormalizations: valueNormalizations
  )
}
func functionRecordNormalizationStream(
  _ expectedCase: CoreConformanceCase,
  actionLocation: String
) -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let state0: [String: Any] = [
    "fingerprint": "1", "level": 1,
    "bindings": [binding(0, "cars", "[carA |-> 0, carB |-> 1]")]
  ]
  let state1: [String: Any] = [
    "fingerprint": "2", "level": 2,
    "bindings": [binding(0, "cars", "[carA |-> 1, carB |-> 1]")]
  ]
  let headerData = Data(header(expectedCase).utf8)
  let initial = record(
    "initial", 1, runID, expectedCase.id, ["callback": "writeState.initial", "state": state0])
  let transition = record(
    "transition", 2, runID, expectedCase.id,
    [
      "callback": "writeState.action", "source": state0, "target": state1,
      "action": ["name": "Step", "location": actionLocation, "named": true],
      "stateFlags": ["raw": 0, "seen": false, "notInModel": false],
      "visualization": "none", "predicateLocation": NSNull(), "reachable": "reachable"
    ])
  let body = [headerData, jsonLine(initial), jsonLine(transition)].reduce(into: Data()) {
    $0.append($1)
    $0.append(10)
  }
  let footer = record(
    "footer", 3, runID, expectedCase.id,
    [
      "callback": "writer.close", "status": "closed",
      "counts": ["header": 1, "initial": 1, "transition": 1],
      "lastBodySeq": 2, "bodySha256": SHA256.hex(body)
    ])
  return body + jsonLine(footer) + Data([10])
}
func replacingFunctionKey(in stream: Data, from: String, to: String) -> Data {
  let lines = String(decoding: stream, as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  var records = lines.dropLast().map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
  for index in [1, 2] {
    var state = records[index][index == 1 ? "state" : "source"] as! [String: Any]
    var bindings = state["bindings"] as! [[String: Any]]
    var binding = bindings[0]
    let value = (binding["tla"] as! String).replacingOccurrences(of: from, with: to)
    binding["tla"] = value
    binding["tlaSha256"] = SHA256.hex(Data(value.utf8))
    bindings[0] = binding
    state["bindings"] = bindings
    records[index][index == 1 ? "state" : "source"] = state
  }
  var target = records[2]["target"] as! [String: Any]
  var targetBindings = target["bindings"] as! [[String: Any]]
  var targetBinding = targetBindings[0]
  let targetValue = (targetBinding["tla"] as! String).replacingOccurrences(of: from, with: to)
  targetBinding["tla"] = targetValue
  targetBinding["tlaSha256"] = SHA256.hex(Data(targetValue.utf8))
  targetBindings[0] = targetBinding
  target["bindings"] = targetBindings
  records[2]["target"] = target
  let body = records.reduce(into: Data()) { result, record in
    result.append(jsonLine(record))
    result.append(10)
  }
  var footer = try! JSONSerialization.jsonObject(with: Data(lines.last!.utf8)) as! [String: Any]
  footer["bodySha256"] = SHA256.hex(body)
  return body + jsonLine(footer) + Data([10])
}
func frozenCase(_ url: URL) throws -> CoreConformanceCase {
  let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  let arguments = try #require(object["arguments"] as? [String])
  let invocationMappings = try #require(object["invocationMappings"] as? [[String: Any]]).map { mapping in
    try CoreConformanceInvocationMapping(
      wrapper: try #require(mapping["wrapper"] as? String),
      action: try #require(mapping["action"] as? String),
      arguments: try #require(mapping["arguments"] as? [String]),
      indices: try #require(mapping["indices"] as? [Int]))
  }
  let valueNormalizations = try #require(object["valueNormalizations"] as? [[String: Any]]).map { normalization in
    try CoreConformanceValueNormalization(
      binding: try #require(normalization["binding"] as? String),
      functionKeys: try #require(normalization["functionKeys"] as? [String: String]))
  }
  return try CoreConformanceCase(
    id: try #require(object["id"] as? String),
    moduleSHA256: try #require(object["moduleSHA256"] as? String),
    cfgSHA256: try #require(object["cfgSHA256"] as? String),
    arguments: arguments,
    argumentsSHA256: try #require(object["argumentsSHA256"] as? String),
    workers: try #require(object["workers"] as? Int),
    fingerprintPolynomial: try #require(object["fingerprintPolynomial"] as? Int),
    deadlock: try #require(object["deadlock"] as? Bool),
    operatingSystem: try #require(object["operatingSystem"] as? String),
    architecture: try #require(object["architecture"] as? String),
    environment: try #require(object["environment"] as? [String: String]), pin: .fixture,
    invocationMappings: invocationMappings, valueNormalizations: valueNormalizations)
}
func mutatedCompleteGraphStream(
  _ expectedCase: CoreConformanceCase, mutation: (String) -> String
) -> Data {
  var lines = String(decoding: completeGraphStream(expectedCase), as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  lines[0] = mutation(lines[0])
  lines[1] = mutation(lines[1])
  lines[2] = mutation(lines[2])
  let body = Data((lines.dropLast().joined(separator: "\n") + "\n").utf8)
  var footer =
    try! JSONSerialization.jsonObject(with: Data(mutation(lines[3]).utf8)) as! [String: Any]
  footer["bodySha256"] = SHA256.hex(body)
  return body + jsonLine(footer) + Data([10])
}
func refreshedFooterDigest(_ stream: Data) -> Data {
  let lines = String(decoding: stream, as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  let body = Data((lines.dropLast().joined(separator: "\n") + "\n").utf8)
  var footer = try! JSONSerialization.jsonObject(with: Data(lines.last!.utf8)) as! [String: Any]
  footer["bodySha256"] = SHA256.hex(body)
  return body + jsonLine(footer) + Data([10])
}
func caseForFiles(
  id: String,
  module: URL,
  configuration: URL,
  arguments: [String],
  environment: [String: String] = [:]
)
  -> CoreConformanceCase {
  try! CoreConformanceCase(
    id: id, moduleSHA256: SHA256.hex(try! Data(contentsOf: module)),
    cfgSHA256: SHA256.hex(try! Data(contentsOf: configuration)),
    arguments: arguments, argumentsSHA256: CoreConformanceCase.argumentsDigest(arguments),
    workers: 1,
    fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: "arm64",
    environment: environment, pin: .fixture
  )
}
func helperProcessDirectory() throws -> URL {
  let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
func helperProcessRequest(
  executable: URL,
  in directory: URL,
  environment: [String: String]
) throws -> TLCProcessRequest {
  let module = directory.appendingPathComponent("Module.tla")
  let configuration = directory.appendingPathComponent("Module.cfg")
  try "---- MODULE Module ----\n====\n".write(to: module, atomically: true, encoding: .utf8)
  try "SPECIFICATION Spec\n".write(to: configuration, atomically: true, encoding: .utf8)
  return TLCProcessRequest(
    javaExecutable: executable,
    jar: URL(fileURLWithPath: "/tmp/jar"),
    bridgeClasses: directory,
    module: module,
    configuration: configuration,
    graphEvents: directory.appendingPathComponent("events.jsonl"),
    traceOutput: directory.appendingPathComponent("trace.json"),
    replayInput: directory.appendingPathComponent("replay.json"),
    workingDirectory: directory,
    arguments: [],
    expectedCase: caseForFiles(
      id: "helper", module: module, configuration: configuration, arguments: [],
      environment: environment
    ),
    runID: UUID()
  )
}
func launchRequest(
  expectedCase: CoreConformanceCase, module: URL, configuration: URL, arguments: [String]
) -> TLCProcessRequest {
  TLCProcessRequest(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
    jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
    bridgeClasses: URL(fileURLWithPath: "/tmp/bridge-classes"), module: module,
    configuration: configuration,
    graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
    traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
    replayInput: URL(fileURLWithPath: "/tmp/replay.json"),
    workingDirectory: module.deletingLastPathComponent(),
    arguments: arguments, expectedCase: expectedCase, runID: UUID()
  )
}
func requestWithReferenceArtifacts(
  jar: URL,
  bridgeClasses: URL,
  artifacts: TLCReferenceArtifacts
) -> TLCProcessRequest {
  TLCProcessRequest(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: jar, bridgeClasses: bridgeClasses,
    module: URL(fileURLWithPath: "/tmp/Fixture.tla"),
    configuration: URL(fileURLWithPath: "/tmp/Fixture.cfg"),
    graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
    traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
    replayInput: URL(fileURLWithPath: "/tmp/replay.json"),
    workingDirectory: URL(fileURLWithPath: "/tmp"),
    arguments: ["-workers", "1", "-fp", "1"],
    expectedCase: fixtureCase(.fixture, arguments: ["-workers", "1", "-fp", "1"]),
    runID: UUID(), referencePin: .fixture, referenceArtifacts: artifacts
  )
}
func retainedBridgeCase() -> CoreConformanceCase {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let module = root.appendingPathComponent("Tools/TLCGraphBridge/spike/BridgeGraph.tla")
  let configuration = root.appendingPathComponent("Tools/TLCGraphBridge/spike/BridgeGraph.cfg")
  let arguments = ["-workers", "1", "-fp", "1", "-seed", "1", "-deadlock"]
  return try! CoreConformanceCase(
    id: "adversarial-core-graph-v1", moduleSHA256: SHA256.hex(try! Data(contentsOf: module)),
    cfgSHA256: SHA256.hex(try! Data(contentsOf: configuration)), arguments: arguments,
    argumentsSHA256: CoreConformanceCase.argumentsDigest(arguments), workers: 1,
    fingerprintPolynomial: 1,
    deadlock: false, operatingSystem: "macos", architecture: "arm64", environment: [:],
    pin: .fixture
  )
}
func header(_ expectedCase: CoreConformanceCase) -> String {
  let pin = expectedCase.pin
  let record: [String: Any] = [
    "schema": "swifttla.tlc.graph-events", "version": 1, "type": "header",
    "callback": "writer.header",
    "seq": 0, "runId": "00000000-0000-4000-8000-000000000001", "caseId": "fixture",
    "provenance": [
      "tlcTag": pin.tag, "tlcCommit": pin.commit, "tlcJarSha256": pin.jarSHA256,
      "javaDistribution": pin.javaDistribution, "javaVersion": pin.javaVersion,
      "javaArchiveSha256": pin.javaArchiveSHA256,
      "bridgeClass": pin.bridgeClass, "bridgeSourceSha256": pin.bridgeSourceSHA256,
      "bridgeBinarySha256": pin.bridgeBinarySHA256,
      "moduleSha256": expectedCase.moduleSHA256, "cfgSha256": expectedCase.cfgSHA256,
      "arguments": expectedCase.arguments, "argumentsSha256": expectedCase.argumentsSHA256,
      "workers": expectedCase.workers,
      "fingerprintPolynomial": expectedCase.fingerprintPolynomial,
      "deadlock": expectedCase.deadlock,
      "os": expectedCase.operatingSystem, "architecture": expectedCase.architecture,
      "environment": expectedCase.environment
    ]
  ]
  return String(data: try! JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
}
final class RecordingTLCExecutor: TLCProcessExecuting, Sendable {
  private let storage: OSAllocatedUnfairLock<(pending: [TLCProcessResult], requests: [TLCProcessRequest])>
  init(results: [TLCProcessResult]) {
    storage = OSAllocatedUnfairLock(initialState: (pending: results, requests: []))
  }
  var requests: [TLCProcessRequest] {
    storage.withLock { $0.requests }
  }
  func execute(_ request: TLCProcessRequest) throws -> TLCProcessResult {
    storage.withLock {
      $0.requests.append(request)
      return $0.pending.removeFirst()
    }
  }
}
