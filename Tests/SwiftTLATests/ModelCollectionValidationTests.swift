@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct ModelCollectionValidationTests {
  private struct Device: Identifiable {
    let id: Int
  }

  @Test("A symmetric declaration records a scoped opaque member domain")
  func declarationRecordsScopedMetadata() {
    let devices = CollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      ModelCollection(devices, verificationScope: 3, initial: 0)
    }

    let metadata = spec.collections[0].metadata
    #expect(metadata.name == "devices")
    #expect(metadata.verificationScope == 3)
    #expect(metadata.initial == .int(0))
    #expect(metadata.members.count == 3)
    #expect(Set(metadata.members).count == 3)
  }

  @Test("Invalid symmetric scopes fail compilation")
  func invalidScopeFailsCompilation() {
    let devices = CollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      ModelCollection(devices, verificationScope: 0, initial: 0)
    }

    assertInvalidCollection(spec, .invalidScope(collection: "devices", scope: 0))
  }

  @Test("Negative symmetric scopes fail compilation")
  func negativeScopeFailsCompilation() {
    let devices = CollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      ModelCollection(devices, verificationScope: -1, initial: 0)
    }

    assertInvalidCollection(spec, .invalidScope(collection: "devices", scope: -1))
  }

  @Test("A symmetric declaration requires a collection name at compilation")
  func missingCollectionNameFailsCompilation() {
    let unnamed = CollectionVar<Device, Int>("")
    let spec = TLASpec("Devices") {
      ModelCollection(unnamed, verificationScope: 1, initial: 0)
    }

    assertInvalidCollection(spec, .missingCollectionName)
  }

  @Test("Duplicate collection names fail compilation")
  func duplicateDeclarationsAreRejected() {
    let devices = CollectionVar<Device, Int>("devices")
    let duplicate = TLASpec("Duplicate") {
      ModelCollection(devices, verificationScope: 1, initial: 0)
      ModelCollection(devices, verificationScope: 1, initial: 0)
    }

    assertDuplicateVariable(duplicate, name: "devices")
  }

  @Test("generated symbols reserve the direct export namespace")
  func generatedSymbolsReserveDirectExportNamespace() {
    let variable = Var<Int>("DevicePhasesKeys")
    let variableCollision = TLASpec("VariableCollision") {
      Variable(variable, 0)
      ModelCollection(CollectionVar<Device, Int>("devicePhases"), verificationScope: 1, initial: 0)
    }
    let constantCollision = TLASpec("ConstantCollision") {
      Constant("DevicePhasesMember0", 0)
      ModelCollection(CollectionVar<Device, Int>("devicePhases"), verificationScope: 1, initial: 0)
    }
    let definitionCollision = TLASpec("DefinitionCollision") {
      FormalDefinition("DevicePhasesKeys", parameters: [], body: .value(.bool(true)))
      ModelCollection(CollectionVar<Device, Int>("devicePhases"), verificationScope: 1, initial: 0)
    }
    assertInvalidCollection(
      variableCollision,
      .symbolCollision(collection: "devicePhases", symbol: "DevicePhasesKeys")
    )
    assertInvalidCollection(
      constantCollision,
      .symbolCollision(collection: "devicePhases", symbol: "DevicePhasesMember0")
    )
    assertInvalidCollection(
      definitionCollision,
      .symbolCollision(collection: "devicePhases", symbol: "DevicePhasesKeys")
    )
  }

  @Test("invalid collection names fail compilation before generated symbols are allocated")
  func invalidCollectionNamesFailCompilation() {
    let invalidName = TLASpec("InvalidCollectionName") {
      ModelCollection(CollectionVar<Device, Int>("device-phases"), verificationScope: 1, initial: 0)
    }

    assertInvalidCollection(invalidName, .invalidCollectionName("device-phases"))
  }

  @Test("Ordinary specifications do not opt into collection symmetry export")
  func ordinarySpecificationsDoNotEmitCollectionSymmetry() throws {
    let counter = Var<Int>("counter")
    let spec = TLASpec("Ordinary") {
      Variable(counter, 0)
    }

    #expect(try spec.compile().render().tlaBundle.tla.contains("TLC") == false)
    #expect(try spec.compile().render().tlaBundle.tla.contains("Permutations(") == false)
    #expect(try spec.compile().render().tlaBundle.cfg.contains("SYMMETRY") == false)
    #expect(try spec.compile().render().tlaBundle.cfg.contains("Member0") == false)
  }

  @Test("A collection variable must retain its declared uniform member domain")
  func nonUniformInitialDomainIsRejected() {
    let devices = CollectionVar<Device, Int>("devices")
    let declared = TLASpec("Declared") {
      ModelCollection(devices, verificationScope: 1, initial: 0)
    }
    let member = declared.collections[0].metadata.members[0]
    let malformed = TLASpec(
      name: "Malformed",
      variables: [NamedVar(name: "devices", initial: .function([member: .int(1)]))],
      actions: [],
      invariants: [],
      collections: declared.collections
    )

    assertInvalidCollection(malformed, .invalidDomain(collection: "devices"))
  }

  @Test("A symmetric declaration must own exactly one model variable")
  func invalidOwnershipIsRejected() {
    let devices = CollectionVar<Device, Int>("devices")
    let declared = TLASpec("Declared") {
      ModelCollection(devices, verificationScope: 1, initial: 0)
    }
    let malformed = TLASpec(
      name: "Malformed",
      variables: [],
      actions: [],
      invariants: [],
      collections: declared.collections
    )

    assertInvalidCollection(malformed, .invalidOwnership(collection: "devices"))
  }

  @Test("Authored actions cannot name a compiler-owned symmetric member")
  func asymmetricActionFailsCompilation() {
    let devices = CollectionVar<Device, Int>("devices")
    let collection = ModelCollection(devices, verificationScope: 2, initial: 0)
    let member = collection.metadata.members[0]
    let spec = TLASpec("AsymmetricAction") {
      collection
      Action("biased") { .guard_(.equal(.value(member), .value(member))) }
    }

    assertMemberReferenceRejected(spec, path: "actions.biased.body.left.guard.left")
  }

  @Test("Authored invariants cannot name a compiler-owned symmetric member")
  func asymmetricInvariantFailsCompilation() {
    let devices = CollectionVar<Device, Int>("devices")
    let collection = ModelCollection(devices, verificationScope: 2, initial: 0)
    let member = collection.metadata.members[0]
    let spec = TLASpec("AsymmetricInvariant") {
      collection
      Invariant("Biased") { .equal(.value(member), .value(member)) }
    }

    assertMemberReferenceRejected(spec, path: "invariants.Biased.body.left")
  }

  @Test("Reduced exploration requires a sufficient permutation limit")
  func reducedExplorationRequiresSufficientPermutationLimit() throws {
    let left = CollectionVar<Device, Int>("left")
    let right = CollectionVar<Device, Int>("right")
    let spec = TLASpec("Budget") {
      ModelCollection(left, verificationScope: 3, initial: 0)
      Symmetry(left)
      ModelCollection(right, verificationScope: 3, initial: 0)
      Symmetry(right)
    }
    let compilation = try spec.compile()
    let unreducedConfiguration = try FiniteExplorationConfiguration(maximumStateLimit: 100_000, symmetryReduction: .disabled)

    let unreduced = try ModelChecker(
      compilation: compilation,
      configuration: unreducedConfiguration
    ).check()
    guard case .ok = unreduced else {
      Issue.record("Expected unreduced exploration to ignore the permutation limit, got \(unreduced)")
      return
    }

    let reducedConfiguration = try FiniteExplorationConfiguration(
      maximumStateLimit: 100_000,
      symmetryReduction: .enabled(maximumPermutationCount: 35))
    #expect(throws: FiniteExplorationConfigurationError.permutationLimitExceeded(
      required: 36,
      limit: 35
    )) {
      try ModelChecker(
        compilation: compilation,
        configuration: reducedConfiguration
      ).check()
    }
  }

  private func assertInvalidCollection(
    _ spec: TLASpec,
    _ expectedError: ModelCollectionValidationError
  ) {
    do {
      _ = try spec.compile()
      Issue.record("Expected symmetric collection compilation to fail")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .invalidModelCollection)
      #expect(diagnostic.stage == .validation)
      #expect(diagnostic.path == "collections")
      #expect(diagnostic.expected == "a valid model collection declaration")
      #expect(diagnostic.actual == expectedError.description)
    } catch {
      Issue.record("Expected CompilationDiagnostic, got \(error)")
    }
  }

  private func assertDuplicateVariable(_ spec: TLASpec, name: String) {
    do {
      _ = try spec.compile()
      Issue.record("Expected duplicate variable compilation to fail")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .duplicateVariable)
      #expect(diagnostic.stage == .validation)
      #expect(diagnostic.path == "variables.\(name)")
      #expect(diagnostic.expected == "one declaration named '\(name)'")
      #expect(diagnostic.actual == "multiple declarations named '\(name)'")
    } catch {
      Issue.record("Expected CompilationDiagnostic, got \(error)")
    }
  }

  private func assertMemberReferenceRejected(_ spec: TLASpec, path: String) {
    do {
      _ = try spec.compile()
      Issue.record("Expected compiler-owned symmetric member reference to fail")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .invalidModelCollection)
      #expect(diagnostic.stage == .binding)
      #expect(diagnostic.path == path)
      #expect(diagnostic.expected == "logic invariant under exchangeable member renaming")
    } catch {
      Issue.record("Expected CompilationDiagnostic, got \(error)")
    }
  }
}
