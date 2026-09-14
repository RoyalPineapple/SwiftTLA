import Foundation
import SwiftTLA

/// Parsed once by the pinned TLC parser; check selection never reparses the model.
package struct TLCReferenceConfiguration: Decodable, Sendable {
  let declarations: String
  let invariants: [String]
  let properties: [String]
  package let checksDeadlock: Bool

  package static func parse(_ request: TLCProcessRequest) throws -> Self {
    guard let artifacts = request.referenceArtifacts else {
      throw FiniteGraphCaseError.missingArtifact("TLC reference artifacts")
    }
    try request.validateDeclaredBundle()
    try request.validateReferenceBinding(artifacts: artifacts)
    try request.finiteGraphCase.pin.validate(artifacts)
    let directory = request.workingDirectory.appendingPathComponent(UUID().uuidString)
    try RetainedFiles.createDirectory(directory, beneath: request.workingDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("original.cfg")
    let output = directory.appendingPathComponent("configuration.json")
    try Data(request.bundle.cfg.utf8).write(to: input)
    let result = try executeProcess(executable: request.javaExecutable,
      arguments: ["-cp", request.bridgeJar.path + ":" + request.jar.path,
        "org.swifttla.conformance.ConfigurationParser", input.path, output.path],
      directory: directory, timeout: request.timeout, environment: request.effectiveEnvironment)
    guard result.status == 0 else {
      throw TLCProcessError.failedToStart("TLC configuration parsing failed: " + result.stderr + result.stdout)
    }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: output))
  }

  func validateCoverage(_ native: NativeModelRun) throws {
    let declared = Set(invariants + properties)
    guard declared.count == invariants.count + properties.count,
          declared.isSubset(of: Set(native.checks.properties.keys)),
          Set(invariants).isSubset(of: native.rendered.invariantNames),
          Set(properties).isSubset(of: native.rendered.checkNames.subtracting(native.rendered.invariantNames)),
          !checksDeadlock || native.checks.deadlock != nil else {
      throw TLCPropertyCheckError.uncoveredReferenceChecks
    }
  }

  func bundle(from original: TLAModuleBundle, native: NativeModelRun,
    checking names: Set<String>, checkDeadlock: Bool) throws -> TLAModuleBundle {
    // Preserve the model definition. Remove symmetry for complete graph comparison.
    return try native.rendered.referenceBundle(checking: names, checkDeadlock: checkDeadlock,
      declarations: declarations, in: original)
  }
}

extension TLCReferenceConfiguration {
  private enum CodingKeys: String, CodingKey, CaseIterable {
    case declarations, invariants, properties, checksDeadlock
  }

  package init(from decoder: Decoder) throws {
    let fields = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
    declarations = try fields.decode(String.self, forKey: .declarations)
    invariants = try fields.decode([String].self, forKey: .invariants)
    properties = try fields.decode([String].self, forKey: .properties)
    checksDeadlock = try fields.decode(Bool.self, forKey: .checksDeadlock)
  }
}
