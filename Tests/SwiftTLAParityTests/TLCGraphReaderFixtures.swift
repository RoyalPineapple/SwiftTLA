import Darwin
import Foundation
import os
import Testing
import SwiftTLA
import UpstreamParity

func testReferencePin() throws -> TLCReferencePin {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let data = try Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/toolchain.json"))
  let toolchain = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  let tlc = try #require(toolchain["tlc"] as? [String: Any])
  let jar = try #require(tlc["jar"] as? [String: Any])
  let java = try #require(toolchain["java"] as? [String: Any])
  let archives = try #require(java["archives"] as? [String: Any])
  let arm64 = try #require(archives["arm64"] as? [String: Any])
  let bridge = try #require(toolchain["bridge"] as? [String: Any])
  return try TLCReferencePin(
    tag: try #require(tlc["tag"] as? String),
    commit: try #require(tlc["commit"] as? String),
    jarSHA256: try #require(jar["sha256"] as? String),
    javaDistribution: try #require(java["distribution"] as? String),
    javaVersion: try #require(java["version"] as? String),
    javaArchiveSHA256: try #require(arm64["sha256"] as? String),
    bridgeClass: try #require(bridge["class"] as? String),
    bridgeSourceSHA256: try #require(bridge["sourceSha256"] as? String),
    bridgeBinarySHA256: try #require(bridge["binarySha256"] as? String)
  )
}

func completeGraphStream(_ expectedCase: FiniteGraphCase) throws -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let state0: [String: Any] = ["fingerprint": "1", "level": 1, "bindings": [binding(0, "x", "0")]]
  let state1: [String: Any] = ["fingerprint": "2", "level": 2, "bindings": [binding(0, "x", "1")]]
  let headerData = Data((try header(expectedCase)).utf8)
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
  let records = try [headerData, jsonLine(initial), jsonLine(transition)]
  let body = records.reduce(into: Data()) {
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
  return body + (try jsonLine(footer)) + Data([10])
}
func completeGraphStreamWithStutteringObservation(_ expectedCase: FiniteGraphCase) throws -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let lines = String(decoding: try completeGraphStream(expectedCase), as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  let header = Data((lines[0] + "\n").utf8)
  let initial = Data((lines[1] + "\n").utf8)
  let transition = Data((lines[2] + "\n").utf8)
  let stutter = try jsonLine(record(
    "unsupported", 3, runID, expectedCase.id,
    ["callback": "writeState.visualization", "reason": "callback has no Action identity: STUTTERING"]
  )) + Data([10])
  let body = header + initial + transition + stutter
  let footer = try jsonLine(record(
    "footer", 4, runID, expectedCase.id,
    [
      "callback": "writer.close", "status": "closed",
      "counts": ["header": 1, "initial": 1, "transition": 1, "unsupported": 1],
      "lastBodySeq": 3, "bodySha256": SHA256.hex(body)
    ]
  )) + Data([10])
  return body + footer
}
func completeGraphStreamWithExcludedPredicateObservation(_ expectedCase: FiniteGraphCase) throws -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let lines = String(decoding: try completeGraphStream(expectedCase), as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  let header = Data((lines[0] + "\n").utf8)
  let initial = Data((lines[1] + "\n").utf8)
  let transition = Data((lines[2] + "\n").utf8)
  let state: [String: Any] = ["fingerprint": "3", "level": 2, "bindings": [binding(0, "x", "2")]]
  let excluded = try jsonLine(record(
    "transition", 3, runID, expectedCase.id,
    [
      "callback": "writeState.actionPredicate", "source": state, "target": state,
      "action": ["name": "Next", "location": "<Next(2) line 1, col 1 to line 1, col 2 of module Fixture>", "named": true],
      "stateFlags": ["raw": 2, "seen": false, "notInModel": true],
      "visualization": "none", "predicateLocation": "line 1, col 1 to line 1, col 2 of module Fixture", "reachable": "excluded"
    ])) + Data([10])
  let body = header + initial + transition + excluded
  let footer = try jsonLine(record(
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
  _ expectedCase: FiniteGraphCase, aliasSeen: Bool, aliasFingerprint: String = "2"
) throws -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let state0: [String: Any] = ["fingerprint": "1", "level": 1, "bindings": [binding(0, "x", "0")]]
  let representative: [String: Any] = ["fingerprint": "2", "level": 2, "bindings": [binding(0, "x", "1")]]
  let alias: [String: Any] = ["fingerprint": aliasFingerprint, "level": 2, "bindings": [binding(0, "x", "2")]]
  let headerData = Data((try header(expectedCase)).utf8)
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
  let records = try [headerData, jsonLine(initial), jsonLine(first), jsonLine(second)]
  let body = records.reduce(into: Data()) {
    $0.append($1)
    $0.append(10)
  }
  let footer = try jsonLine(record(
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
func jsonLine(_ object: [String: Any]) throws -> Data {
  try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
func fixtureCase(
  _ pin: TLCReferencePin,
  arguments: [String] = [],
  renderedActions: [RenderedAction] = []
)
  throws -> FiniteGraphCase {
  try FiniteGraphCase(
    id: "fixture", moduleSHA256: String(repeating: "c", count: 64),
    cfgSHA256: String(repeating: "d", count: 64),
    arguments: arguments, argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments),
    workers: 1,
    fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: "arm64",
    environment: [:], pin: pin, renderedActions: renderedActions
  )
}
func functionRecordNormalizationStream(
  _ expectedCase: FiniteGraphCase,
  actionLocation: String
) throws -> Data {
  let runID = "00000000-0000-4000-8000-000000000001"
  let state0: [String: Any] = [
    "fingerprint": "1", "level": 1,
    "bindings": [binding(0, "cars", "[carA |-> 0, carB |-> 1]")]
  ]
  let state1: [String: Any] = [
    "fingerprint": "2", "level": 2,
    "bindings": [binding(0, "cars", "[carA |-> 1, carB |-> 1]")]
  ]
  let headerData = Data((try header(expectedCase)).utf8)
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
  let records = try [headerData, jsonLine(initial), jsonLine(transition)]
  let body = records.reduce(into: Data()) {
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
  return body + (try jsonLine(footer)) + Data([10])
}
func mutatedCompleteGraphStream(
  _ expectedCase: FiniteGraphCase, mutation: (String) -> String
) throws -> Data {
  var lines = String(decoding: try completeGraphStream(expectedCase), as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  lines[0] = mutation(lines[0])
  lines[1] = mutation(lines[1])
  lines[2] = mutation(lines[2])
  let body = Data((lines.dropLast().joined(separator: "\n") + "\n").utf8)
  var footer = try #require(
    JSONSerialization.jsonObject(with: Data(mutation(lines[3]).utf8)) as? [String: Any])
  footer["bodySha256"] = SHA256.hex(body)
  return body + (try jsonLine(footer)) + Data([10])
}
func refreshedFooterDigest(_ stream: Data) throws -> Data {
  let lines = String(decoding: stream, as: UTF8.self)
    .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
  let body = Data((lines.dropLast().joined(separator: "\n") + "\n").utf8)
  let footerLine = try #require(lines.last)
  var footer = try #require(JSONSerialization.jsonObject(with: Data(footerLine.utf8)) as? [String: Any])
  footer["bodySha256"] = SHA256.hex(body)
  return body + (try jsonLine(footer)) + Data([10])
}
func caseForFiles(
  id: String,
  module: URL,
  configuration: URL,
  arguments: [String],
  environment: [String: String] = [:]
)
  throws -> FiniteGraphCase {
  try FiniteGraphCase(
    id: id, moduleSHA256: SHA256.hex(try Data(contentsOf: module)),
    cfgSHA256: SHA256.hex(try Data(contentsOf: configuration)),
    arguments: arguments, argumentsSHA256: try FiniteGraphCase.argumentsDigest(arguments),
    workers: 1,
    fingerprintPolynomial: 1, deadlock: false, operatingSystem: "macos", architecture: "arm64",
    environment: environment, pin: try testReferencePin()
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
    bundle: try TLCProcessRequest.declaredBundle(root: module, configuration: configuration),
    graphEvents: directory.appendingPathComponent("events.jsonl"),
    traceOutput: directory.appendingPathComponent("trace.json"),
    workingDirectory: directory,
    arguments: [],
    expectedCase: try caseForFiles(
      id: "helper", module: module, configuration: configuration, arguments: [],
      environment: environment
    ),
    runID: UUID()
  )
}
func launchRequest(
  expectedCase: FiniteGraphCase, module: URL, configuration: URL, arguments: [String]
) throws -> TLCProcessRequest {
  try TLCProcessRequest(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"),
    jar: URL(fileURLWithPath: "/tmp/tla2tools.jar"),
    bridgeClasses: URL(fileURLWithPath: "/tmp/bridge-classes"),
    bundle: TLCProcessRequest.declaredBundle(root: module, configuration: configuration),
    graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
    traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
    workingDirectory: module.deletingLastPathComponent(),
    arguments: arguments, expectedCase: expectedCase, runID: UUID()
  )
}
func requestWithReferenceArtifacts(
  jar: URL,
  bridgeClasses: URL,
  artifacts: TLCReferenceArtifacts
) throws -> TLCProcessRequest {
  TLCProcessRequest(
    javaExecutable: URL(fileURLWithPath: "/usr/bin/java"), jar: jar, bridgeClasses: bridgeClasses,
    bundle: .external(root: TLAModuleFile(name: "Fixture", tla: "---- MODULE Fixture ----", cfg: "SPECIFICATION Spec")),
    graphEvents: URL(fileURLWithPath: "/tmp/events.jsonl"),
    traceOutput: URL(fileURLWithPath: "/tmp/trace.json"),
    workingDirectory: URL(fileURLWithPath: "/tmp"),
    arguments: ["-workers", "1", "-fp", "1"],
    expectedCase: try fixtureCase(try testReferencePin(), arguments: ["-workers", "1", "-fp", "1"]),
    runID: UUID(), referencePin: try testReferencePin(), referenceArtifacts: artifacts
  )
}
func header(_ expectedCase: FiniteGraphCase) throws -> String {
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
  let data = try JSONSerialization.data(withJSONObject: record)
  return try #require(String(data: data, encoding: .utf8))
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
