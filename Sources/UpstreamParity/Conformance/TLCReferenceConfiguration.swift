import Foundation
import SwiftTLA

/// Parsed once by the pinned TLC parser; check selection never reparses the model.
package struct TLCReferenceConfiguration: Decodable, Sendable {
  let declarations: String
  let invariants: [String]
  let properties: [String]
  let postconditions: [String]
  package let checksDeadlock: Bool

  package static func parse(_ request: TLCProcessRequest, checking nativeChecks: Set<String>) throws -> Self {
    guard let artifacts = request.referenceArtifacts else {
      throw FiniteGraphCaseError.missingArtifact("TLC reference artifacts")
    }
    try request.validateReferenceBinding(artifacts: artifacts)
    try request.finiteGraphCase.pin.validate(artifacts)
    let directory = request.workingDirectory.appendingPathComponent(UUID().uuidString)
    try RetainedFiles.createDirectory(directory, beneath: request.workingDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try request.stageDeclaredBundle()
    defer { try? FileManager.default.removeItem(at: input.module.deletingLastPathComponent()) }
    let output = directory.appendingPathComponent("configuration.json")
    let result = try executeProcess(executable: request.javaExecutable,
      arguments: ["-cp", ([request.bridgeJar, request.jar]
        + (request.supplementalJar.map { [$0.url] } ?? [])).map(\.path).joined(separator: ":"),
        "org.swifttla.conformance.ConfigurationParser", input.module.path, input.configuration.path, output.path]
        + nativeChecks.sorted(),
      directory: input.module.deletingLastPathComponent(), timeout: request.timeout, environment: request.effectiveEnvironment)
    guard result.status == 0 else {
      throw TLCProcessError.failedToStart("TLC configuration parsing failed: " + result.stderr + result.stdout)
    }
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: output))
  }

  func validateCoverage(_ native: NativeModelRun) throws {
    let declared = invariants + properties
    let repeated = Dictionary(grouping: declared, by: { $0 }).filter { $0.value.count > 1 }.keys
    let missingResults = Set(declared).subtracting(native.checks.properties.keys)
    let unsupportedInvariants = Set(invariants).subtracting(native.rendered.invariantNames)
    let temporalNames = native.rendered.checkNames.subtracting(native.rendered.invariantNames)
      .subtracting(native.rendered.reachabilityNames)
    let unsupportedProperties = Set(properties).subtracting(temporalNames)
    var problems = repeated.sorted().map { "Repeated reference check: \($0)" }
    problems += missingResults.sorted().map { "Missing native result: \($0)" }
    problems += unsupportedInvariants.sorted().map { "No matching native invariant: \($0)" }
    problems += unsupportedProperties.sorted().map { "No matching native temporal property: \($0)" }
    if checksDeadlock && native.checks.deadlock == nil {
      problems.append("Missing native deadlock result")
    }
    if !problems.isEmpty {
      throw TLCPropertyCheckError.uncoveredReferenceChecks(problems)
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
    case declarations, invariants, properties, postconditions, checksDeadlock
  }

  package init(from decoder: Decoder) throws {
    let fields = try decoder.container(validatingKeys: CodingKeys.self)
    declarations = try fields.decode(String.self, forKey: .declarations)
    invariants = try fields.decode([String].self, forKey: .invariants)
    properties = try fields.decode([String].self, forKey: .properties)
    postconditions = try fields.decode([String].self, forKey: .postconditions)
    checksDeadlock = try fields.decode(Bool.self, forKey: .checksDeadlock)
  }
}

extension RenderedSpecification {
  /// Keep the upstream model's own source and declarations; only the selected
  /// check directives come from the independently rendered SwiftTLA model.
  package func referenceBundle(checking names: Set<String>, checkDeadlock: Bool,
    declarations: String, postcondition: String? = nil,
    in reference: TLAModuleBundle) throws -> TLAModuleBundle {
    let selected = try checkSelection(checking: names, checkDeadlock: checkDeadlock)
    let directives = selected.tlcInvariantNames.map { "INVARIANT \($0)" }
      + selected.tlcPropertyNames.map { "PROPERTY \($0)" }
      + [selected.checkDeadlock ? "CHECK_DEADLOCK TRUE" : "CHECK_DEADLOCK FALSE"]
      + (postcondition.map { ["POSTCONDITION \($0)"] } ?? [])
    return reference.replacingConfiguration(declarations + "\n" + directives.joined(separator: "\n") + "\n")
  }
}
