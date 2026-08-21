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

  @Test("Invalid symmetric scopes are rejected before initial-state exploration")
  func invalidScopeIsReportedBeforeExploration() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: 0, initial: 0)
    }

    let result = try ModelChecker(compilation: try spec.compile()).check()
    guard case .bounded(let scopes, let outcome) = result else {
      Issue.record("Expected bounded result, got \(result)")
      return
    }
    #expect(scopes == [SymmetricCollectionScope(collectionName: "devices", verificationScope: 0)])
    guard case .error(let message) = outcome else {
      Issue.record("Expected validation error, got \(outcome)")
      return
    }
    #expect(message.contains("devices"))
    #expect(message.contains("positive"))
  }

  @Test("Negative symmetric scopes are rejected before initial-state exploration")
  func negativeScopeIsReportedBeforeExploration() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let spec = TLASpec("Devices") {
      SymmetricCollection(devices, verificationScope: -1, initial: 0)
    }

    let result = try ModelChecker(compilation: try spec.compile()).check().underlyingOutcome
    guard case .error(let message) = result else {
      Issue.record("Expected negative scope validation error, got \(result)")
      return
    }
    #expect(message.contains("devices"))
    #expect(message.contains("-1"))
    #expect(message.contains("positive"))
  }

  @Test("A symmetric declaration requires a collection name")
  func missingCollectionNameIsReportedBeforeExploration() throws {
    let unnamed = SymmetricCollectionVar<Device, Int>("")
    let spec = TLASpec("Devices") {
      SymmetricCollection(unnamed, verificationScope: 1, initial: 0)
    }

    let result = try ModelChecker(compilation: try spec.compile()).check().underlyingOutcome
    guard case .error(let message) = result else {
      Issue.record("Expected missing-name validation error, got \(result)")
      return
    }
    #expect(message.contains("missing a name"))
    #expect(message.contains("unique collection name"))
  }

  @Test("Duplicate names and generated symbol collisions identify the affected collection")
  func duplicateAndCollisionDeclarationsAreRejected() throws {
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let duplicate = TLASpec("Duplicate") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
    }
    let collision = TLASpec("Collision") {
      Constant("__symmetric_devices_member_1", 0)
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
    }

    let duplicateResult = try ModelChecker(compilation: try duplicate.compile()).check().underlyingOutcome
    let collisionResult = try ModelChecker(compilation: try collision.compile()).check().underlyingOutcome
    guard case .error(let duplicateMessage) = duplicateResult,
          case .error(let collisionMessage) = collisionResult else {
      Issue.record("Expected declaration validation errors")
      return
    }
    #expect(duplicateMessage.contains("devices"))
    #expect(collisionMessage.contains("devices"))
    #expect(collisionMessage.contains("__symmetric_devices_member_1"))
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
    #expect(symbolCollision(variableCollision) == "DevicePhasesKeys")
    #expect(symbolCollision(constantCollision) == "DevicePhasesMember0")
    #expect(symbolCollision(definitionCollision) == "SymmDevicePhases")
  }

  @Test("invalid collection names fail compilation before generated symbols are allocated")
  func invalidCollectionNamesFailCompilation() {
    let invalidName = TLASpec("InvalidCollectionName") {
      SymmetricCollection(SymmetricCollectionVar<Device, Int>("device-phases"), verificationScope: 1, initial: 0)
    }

    do {
      _ = try invalidName.compile()
      Issue.record("Expected an invalid symmetric collection diagnostic.")
    } catch let diagnostic as CompilationDiagnostic {
      #expect(diagnostic.code == .invalidSymmetricCollection)
      #expect(diagnostic.actual.contains("not a formal identifier"))
    } catch {
      Issue.record("Expected CompilationDiagnostic, got \(error).")
    }
  }

  @Test("Ordinary specifications do not opt into collection symmetry export")
  func ordinarySpecificationsDoNotEmitCollectionSymmetry() throws {
    let counter = Var<Int>("counter")
    let spec = TLASpec("Ordinary") {
      Variable(counter, 0)
    }

    #expect(!(try spec.compile().renderedTLAModuleBundle().tla.contains("TLC")))
    #expect(!(try spec.compile().renderedTLAModuleBundle().tla.contains("Permutations(")))
    #expect(!(try spec.compile().renderedTLAModuleBundle().cfg.contains("SYMMETRY")))
    #expect(!(try spec.compile().renderedTLAModuleBundle().cfg.contains("Member0")))
  }

  private func symbolCollision(_ spec: TLASpec) -> String? {
    guard case .symbolCollision(_, let symbol)? = spec.symmetricCollectionValidationError() else {
      return nil
    }
    return symbol
  }

  @Test("A collection variable must retain its declared uniform member domain")
  func nonUniformInitialDomainIsRejected() throws {
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

    let result = try ModelChecker(compilation: try malformed.compile()).check().underlyingOutcome
    guard case .error(let message) = result else {
      Issue.record("Expected domain validation error, got \(result)")
      return
    }
    #expect(message.contains("devices"))
    #expect(message.contains("uniform"))
  }

  @Test("A symmetric declaration must own exactly one model variable")
  func invalidOwnershipIsRejected() throws {
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

    let result = try ModelChecker(compilation: try malformed.compile()).check().underlyingOutcome
    guard case .error(let message) = result else {
      Issue.record("Expected ownership validation error, got \(result)")
      return
    }
    #expect(message.contains("devices"))
    #expect(message.contains("own exactly one modeled variable"))
  }

  @Test("The cross-collection permutation product has an explicit budget")
  func permutationBudgetIsReported() throws {
    let left = SymmetricCollectionVar<Device, Int>("left")
    let right = SymmetricCollectionVar<Device, Int>("right")
    let spec = TLASpec("Budget") {
      SymmetricCollection(left, verificationScope: 3, initial: 0)
      SymmetricCollection(right, verificationScope: 3, initial: 0)
    }

    let result = try ModelChecker(compilation: try spec.compile(), permutationProductBudget: 35).check()
    guard case .bounded(_, let outcome) = result,
          case .error(let message) = outcome else {
      Issue.record("Expected bounded budget error, got \(result)")
      return
    }
    #expect(message.contains("budget"))
    #expect(message.contains("36"))
  }
}
