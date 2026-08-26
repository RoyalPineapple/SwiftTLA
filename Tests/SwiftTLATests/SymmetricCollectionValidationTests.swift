@testable import SwiftTLA
import Testing

@Suite(.serialized)
struct SymmetricCollectionValidationTests {
  private struct Device: Identifiable {
    let id: Int
  }

  @Test("A symmetric declaration records a scoped opaque member domain")
  func declarationRecordsScopedMetadata() {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 3, initial: 0)
    }

    let metadata = spec.symmetricCollections[0].metadata
    #expect(metadata.name == "devices")
    #expect(metadata.verificationScope == 3)
    #expect(metadata.initial == .int(0))
    #expect(metadata.members.count == 3)
    #expect(Set(metadata.members).count == 3)
  }

  @Test("Invalid symmetric scopes fail compilation")
  func invalidScopeFailsCompilation() {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 0, initial: 0)
    }

    assertInvalidCollection(spec, .invalidScope(collection: "devices", scope: 0))
  }

  @Test("Negative symmetric scopes fail compilation")
  func negativeScopeFailsCompilation() {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: -1, initial: 0)
    }

    assertInvalidCollection(spec, .invalidScope(collection: "devices", scope: -1))
  }

  @Test("A symmetric declaration requires a collection name at compilation")
  func missingCollectionNameFailsCompilation() {
    let unnamed = SymmetricCollectionVar<Device, Int>("")
    let spec = TLASpec("Devices") {
      SymmetricCollection(unnamed, verificationScope: 1, initial: 0)
    }

    assertInvalidCollection(spec, .missingCollectionName)
  }

  @Test("Duplicate names and generated symbol collisions identify the affected collection")
  func duplicateAndCollisionDeclarationsAreRejected() {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let duplicate = TLASpec("Duplicate") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
    }
    let collision = TLASpec("Collision") {
      Constant("__symmetric_devices_member_1", 0)
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
    }

    assertDuplicateVariable(duplicate, name: "devices")
    assertInvalidCollection(
      collision,
      .symbolCollision(collection: "devices", symbol: "__symmetric_devices_member_1")
    )
  }

  @Test("generated symbols reserve the direct export namespace")
  func generatedSymbolsReserveDirectExportNamespace() {
    let variable = Var<Int>("DevicePhasesKeys")
    let variableCollision = TLASpec("VariableCollision") {
      Variable(variable, 0)
      SymmetricCollection(SymmetricCollectionVar<Device, Int>("devicePhases"), verificationScope: 1, initial: 0)
    }
    let constantCollision = TLASpec("ConstantCollision") {
      Constant("DevicePhasesMember0", 0)
      SymmetricCollection(SymmetricCollectionVar<Device, Int>("devicePhases"), verificationScope: 1, initial: 0)
    }
    let definitionCollision = TLASpec("DefinitionCollision") {
      FormalDefinition("SymmDevicePhases", parameters: [], body: .value(.bool(true)))
      SymmetricCollection(SymmetricCollectionVar<Device, Int>("devicePhases"), verificationScope: 1, initial: 0)
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
      .symbolCollision(collection: "devicePhases", symbol: "SymmDevicePhases")
    )
  }

  @Test("invalid collection names fail compilation before generated symbols are allocated")
  func invalidCollectionNamesFailCompilation() {
    let invalidName = TLASpec("InvalidCollectionName") {
      SymmetricCollection(SymmetricCollectionVar<Device, Int>("device-phases"), verificationScope: 1, initial: 0)
    }

    assertInvalidCollection(invalidName, .invalidCollectionName("device-phases"))
  }

  @Test("Ordinary specifications do not opt into collection symmetry export")
  func ordinarySpecificationsDoNotEmitCollectionSymmetry() throws {
    let counter = Var<Int>("counter")
    let spec = TLASpec("Ordinary") {
      Variable(counter, 0)
    }

    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("TLC") == false)
    #expect(try spec.compile().renderedTLAModuleBundle().tla.contains("Permutations(") == false)
    #expect(try spec.compile().renderedTLAModuleBundle().cfg.contains("SYMMETRY") == false)
    #expect(try spec.compile().renderedTLAModuleBundle().cfg.contains("Member0") == false)
  }

  @Test("A collection variable must retain its declared uniform member domain")
  func nonUniformInitialDomainIsRejected() {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let declared = TLASpec("Declared") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
    }
    let member = declared.symmetricCollections[0].metadata.members[0]
    let malformed = TLASpec(
      name: "Malformed",
      variables: [NamedVar(name: "devices", initial: .function([member: .int(1)]))],
      actions: [],
      invariants: [],
      symmetricCollections: declared.symmetricCollections
    )

    assertInvalidCollection(malformed, .invalidDomain(collection: "devices"))
  }

  @Test("A symmetric declaration must own exactly one model variable")
  func invalidOwnershipIsRejected() {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let declared = TLASpec("Declared") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
    }
    let malformed = TLASpec(
      name: "Malformed",
      variables: [],
      actions: [],
      invariants: [],
      symmetricCollections: declared.symmetricCollections
    )

    assertInvalidCollection(malformed, .invalidOwnership(collection: "devices"))
  }

  @Test("Authored actions cannot name a compiler-owned symmetric member")
  func asymmetricActionFailsCompilation() {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let collection = SymmetricCollection(devices, verificationScope: 2, initial: 0)
    let member = collection.metadata.members[0]
    let spec = TLASpec("AsymmetricAction") {
      collection
      Action("biased") { .guard_(.equal(.value(member), .value(member))) }
    }

    assertMemberReferenceRejected(spec, path: "actions.biased.body.left.guard.left")
  }

  @Test("Authored invariants cannot name a compiler-owned symmetric member")
  func asymmetricInvariantFailsCompilation() {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let collection = SymmetricCollection(devices, verificationScope: 2, initial: 0)
    let member = collection.metadata.members[0]
    let spec = TLASpec("AsymmetricInvariant") {
      collection
      Invariant("Biased") { .equal(.value(member), .value(member)) }
    }

    assertMemberReferenceRejected(spec, path: "invariants.Biased.body.left")
  }

  @Test("The permutation budget applies only to reduced exploration")
  func permutationBudgetAppliesOnlyToReduction() throws {
    let left = SymmetricCollectionVar<Device, Int>("left")
    let right = SymmetricCollectionVar<Device, Int>("right")
    let spec = TLASpec("Budget") {
      SymmetricCollection(left, verificationScope: 3, initial: 0)
      SymmetricCollection(right, verificationScope: 3, initial: 0)
    }
    let compilation = try spec.compile()
    let configuration = try FiniteExplorationConfiguration(maximumStateLimit: 100_000)

    let unreduced = try ModelChecker(
      compilation: compilation,
      configuration: configuration,
      permutationProductBudget: 35,
      usesSymmetryReduction: false
    ).check()
    guard case .bounded(_, let unreducedOutcome) = unreduced,
          case .ok = unreducedOutcome else {
      Issue.record("Expected unreduced exploration to ignore the permutation budget, got \(unreduced)")
      return
    }

    let reduced = try ModelChecker(
      compilation: compilation,
      configuration: configuration,
      permutationProductBudget: 35,
      usesSymmetryReduction: true
    ).check()
    guard case .bounded(_, let outcome) = reduced,
          case .error(let message) = outcome else {
      Issue.record("Expected reduced exploration to report the permutation budget, got \(reduced)")
      return
    }
    #expect(message.contains("budget"))
    #expect(message.contains("36"))
  }

  private func assertInvalidCollection(
    _ spec: TLASpec,
    _ expectedError: SymmetricCollectionValidationError
  ) {
    do {
      _ = try spec.compile()
      Issue.record("Expected symmetric collection compilation to fail")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .invalidSymmetricCollection)
      #expect(diagnostic.stage == .validation)
      #expect(diagnostic.path == "symmetricCollections")
      #expect(diagnostic.expected == "a valid symmetric collection declaration")
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
      #expect(diagnostic.code == .invalidSymmetricCollection)
      #expect(diagnostic.stage == .binding)
      #expect(diagnostic.path == path)
      #expect(diagnostic.expected == "logic invariant under exchangeable member renaming")
    } catch {
      Issue.record("Expected CompilationDiagnostic, got \(error)")
    }
  }
}
