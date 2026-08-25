import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAMacros
import Testing

private func parseClosure(_ source: String) throws -> ClosureExprSyntax {
  try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
}

public struct MacroDevice: Identifiable, Sendable {
  public let id: Int

  public init(id: Int) {
    self.id = id
  }
}

public struct StringMacroDevice: Identifiable, Sendable {
  public let id: String

  public init(id: String) {
    self.id = id
  }
}

@TLAModel
public struct GeneratedSymmetricRuntime: Sendable {
  public static var spec: TLASpec {
    TLASpec("GeneratedSymmetricRuntime") {
      let devices = SymmetricCollectionVar<MacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("begin", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
    }
  }
}

@TLAModel
public struct GeneratedExpressionSymmetricRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedExpressionSymmetricRuntime") {
      let devices = SymmetricCollectionVar<MacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] < 5 && devices.update(member, to: devices[member] + 1)
      }
    }
  }
}

@TLAModel
public struct GeneratedScopedSymmetricRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedScopedSymmetricRuntime") {
      let devices = SymmetricCollectionVar<StringMacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("begin", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: devices[member] + 1)
      }
    }
  }
}

@TLAModel
public struct GeneratedSharedGuardSymmetricRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedSharedGuardSymmetricRuntime") {
      let phase = Var<Int>("phase")
      let devices = SymmetricCollectionVar<StringMacroDevice, Int>("devices")
      Variable(phase, 4)
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("begin", on: devices) { member in
        phase == 5 && devices[member] == 0 && devices.update(member, to: 1)
      }
    }
  }
}

@TLAModel
public struct GeneratedMultiStatementSymmetricRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedMultiStatementSymmetricRuntime") {
      let devices = SymmetricCollectionVar<StringMacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] == 0 || devices[member] == 1
        devices[member] == 1
        devices.update(member, to: devices[member] + 10)
      }
    }
  }
}

@TLAModel
public struct GeneratedDisjunctiveSymmetricRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedDisjunctiveSymmetricRuntime") {
      let devices = SymmetricCollectionVar<StringMacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("advance", on: devices) { member in
        (devices[member] == 0 && devices.update(member, to: devices[member] + 1))
          || (devices[member] == 2 && devices.update(member, to: devices[member] + 20))
      }
    }
  }
}

@TLAModel
public struct GeneratedAllSatisfyPredicateRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedAllSatisfyPredicateRuntime") {
      let phase = Var<Int>("phase")
      let devices = SymmetricCollectionVar<StringMacroDevice, Int>("devices")
      Variable(phase, 0)
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      SwiftTLA.Action("advance") {
        devices.allSatisfy { $0 == 0 } && phase.becomes(1)
      }
    }
  }
}

@TLAModel
public struct GeneratedContainsPredicateRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedContainsPredicateRuntime") {
      let phase = Var<Int>("phase")
      let devices = SymmetricCollectionVar<StringMacroDevice, Int>("devices")
      Variable(phase, 0)
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      SwiftTLA.Action("advance") {
        devices.contains(where: { $0 == 1 }) && phase.becomes(1)
      }
    }
  }
}

@Suite(.serialized)
struct SymmetricCollectionMacroRuntimeTests {
  private func compiledSuccessors(
    of spec: TLASpec,
    from projection: TLAStateProjection
  ) throws -> [TLAStateProjection] {
    let compilation = try spec.compile()
    let state = try CompiledState(
      projection: projection,
      compilation: compilation
    )
    return try CompiledRuntime(compilation: compilation)
      .successors(from: state)
      .map { try $0.state.projection(using: compilation.layout) }
  }

  private struct Device: Identifiable {
    let id: Int
  }

  @Test("Parsed symmetric declarations retain type, scope, action, and source provenance")
  func parserRetainsCollectionProvenance() throws {
    let source = """
    {
      let devices = SymmetricCollectionVar<Device, Int>(\"devices\")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction(\"begin\", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
    }
    """
    let closure = try parseClosure(source)

    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.symmetricCollections.map(\.name) == ["devices"])
    #expect(parsed.symmetricCollections[0].elementType == "Device")
    #expect(parsed.symmetricCollections[0].valueType == "Int")
    #expect(parsed.symmetricCollections[0].verificationScope == 2)
    #expect(parsed.collectionActions.map(\.name) == ["begin"])
    #expect(parsed.diagnostics.isEmpty)
  }

  @Test("Symmetric collection type arguments retain their syntax until generated Swift is emitted")
  func parserRetainsQualifiedCollectionTypeArguments() throws {
    let source = """
    {
      let devices = SwiftTLA.SymmetricCollectionVar<Model.Device, Swift.Int>("devices")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
    }
    """
    let statements = Parser.parse(source: source).statements
    let closure = try #require(statements.first?.item.as(ClosureExprSyntax.self))

    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.symmetricCollections.map(\.elementType) == ["Model.Device"])
    #expect(parsed.symmetricCollections.map(\.valueType) == ["Swift.Int"])
    #expect(parsed.diagnostics.isEmpty)
  }

  @Test("Parsed collection actions preserve guards and lowering behavior")
  func parserPreservesCollectionActionBody() throws {
    let source = """
    {
      let devices = SymmetricCollectionVar<Device, Int>("devices")
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("begin", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: devices[member] + 1)
      }
    }
    """
    let closure = try parseClosure(source)
    let parsed = SpecParser.parseSpecClosure(closure)
    let initial = parsed.variables.map { ($0.name, $0.initial) }
    let advanced: [(String, TLAValue)] = [
      ("devices", .function([TLAValue.constant("DevicesMember0"): TLAValue.int(1)]))
    ]
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let runtimeBuilt = TLASpec("RuntimeBuiltParity") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("begin", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: devices[member] + 1)
      }
    }

    let parsedSpec = TLASpec(
      name: "ParsedCollectionAction",
      variables: parsed.variables.map { .init(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
      actions: parsed.actions.map { .init(name: $0.name, body: $0.body) },
      invariants: []
    )

    #expect(parsed.diagnostics.isEmpty)
    #expect(try compiledSuccessors(of: parsedSpec, from: projection(initial))
      == compiledSuccessors(of: runtimeBuilt, from: projection(initial)))
    #expect(try compiledSuccessors(of: parsedSpec, from: projection(advanced)).isEmpty)
  }

  @Test("Parser preserves collection action precedence from syntax nodes")
  func parserPreservesCollectionActionPrecedence() throws {
    let source = """
    {
      let devices = SymmetricCollectionVar<Device, Int>("devices")
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("advance", on: devices) { member in
        (devices[member] == 0 && devices.update(member, to: devices[member] + 1))
          || (devices[member] == 2 && devices.update(member, to: devices[member] + 20))
      }
    }
    """
    let closure = try #require(
      Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self)
    )
    let parsed = SpecParser.parseSpecClosure(closure)
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let authored = TLASpec("AuthoredCollectionAction") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("advance", on: devices) { member in
        (devices[member] == 0 && devices.update(member, to: devices[member] + 1))
          || (devices[member] == 2 && devices.update(member, to: devices[member] + 20))
      }
    }

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.actions.map(\.body) == authored.actions.map(\.body))
  }

  @Test("Parser rejects observable, escaping, and cross-collection member identities")
  func parserRejectsIdentityObservations() throws {
    let source = """
    {
      let devices = SymmetricCollectionVar<Device, Int>(\"devices\")
      let other = SymmetricCollectionVar<Device, Int>(\"other\")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      SymmetricCollection(other, verificationScope: 2, initial: 0)
      CollectionAction(\"invalid\", on: devices) { member in
        devices[member] == 0 && other.update(member, to: 1)
      }
    }
    """
    let closure = try parseClosure(source)

    let parsed = SpecParser.parseSpecClosure(closure)

    #expect(parsed.diagnostics.count == 1)
    #expect(parsed.diagnostics[0].message.contains("opaque"))
    #expect(parsed.diagnostics[0].message.contains("other"))
  }

  @Test("Parser rejects every unsupported member-token observation family")
  func parserRejectsOpaqueTokenMisuseMatrix() throws {
    let cases = [
      "member == member",
      "StateExpr.tuple([member])",
      "return member",
      "let escaped = { devices[member] }",
      "devices.domain == StateExpr.set([])"
    ]

    for body in cases {
      let source = """
      {
        let devices = SymmetricCollectionVar<Device, Int>(\"devices\")
        SymmetricCollection(devices, verificationScope: 2, initial: 0)
        CollectionAction(\"invalid\", on: devices) { member in
          \(body)
        }
      }
      """
      let closure = try parseClosure(source)

      #expect(!SpecParser.parseSpecClosure(closure).diagnostics.isEmpty)
    }
  }

  @Test("Token diagnostics use syntax roles rather than trivia-sensitive text")
  func parserRejectsTriviaVariedRawDomainAccess() throws {
    let source = """
    {
      let devices = SymmetricCollectionVar<Device, Int>("devices")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("invalid", on: devices) { member in
        devices /* identity must remain opaque */ . domain == StateExpr.set([])
      }
    }
    """
    let closure = try parseClosure(source)

    #expect(!SpecParser.parseSpecClosure(closure).diagnostics.isEmpty)
  }

  @Test("Identified runtime storage retains concrete IDs beyond verification scope")
  func runtimeStorageUsesConcreteIDsWithoutCappingPopulation() throws {
    var devices = try IdentifiedModelCollection<Device, Int>(
      name: "devices", verificationScope: 1, initial: 0
    )
    let first = Device(id: 1)
    let second = Device(id: 2)

    devices.insert(first)
    devices.insert(second, value: 3)
    try devices.update(id: second.id, to: 4)

    #expect(devices.verificationScope == 1)
    #expect(devices.count == 2)
    #expect(devices[first.id] == 0)
    #expect(devices[second.id] == 4)
    #expect(throws: SymmetricCollectionRuntimeError.self) {
      try devices.update(id: 99, to: 1)
    }
  }

  @Test("Identified runtime storage rejects an invalid verification scope")
  func runtimeStorageRejectsInvalidVerificationScope() {
    #expect(throws: SymmetricCollectionRuntimeError.self) {
      _ = try IdentifiedModelCollection<Device, Int>(
        name: "devices", verificationScope: 0, initial: 0
      )
    }
  }

  @Test("TLAModel generates typed collection actions and checked scopes")
  func macroGeneratesIdentifiedRuntime() throws {
    var model = try GeneratedSymmetricRuntime.makeMachine()
    let device = MacroDevice(id: 42)

    model.devices.insert(device)
    let result = try model.send(.begin(member: device.id))

    #expect(model.devices[device.id] == 1)
    #expect(result.action == .begin(member: device.id))
    #expect(GeneratedSymmetricRuntime.symmetricCollectionScopes == [
      SymmetricCollectionScope(collectionName: "devices", verificationScope: 1)
    ])
    #expect(GeneratedSymmetricRuntime.spec.actions.description.contains("42") == false)
    #expect(throws: GeneratedMachineError.self) {
      try model.send(.begin(member: 99))
    }
  }

  @Test("Generated collection actions evaluate expression-backed updates against live storage")
  func macroUpdatesLiveStorageForExpressionBackedActions() throws {
    var model = try GeneratedExpressionSymmetricRuntime.makeMachine()
    let device = MacroDevice(id: 42)

    model.devices.insert(device, value: 4)
    _ = try model.send(.advance(member: device.id))

    #expect(model.devices[device.id] == 5)
  }

  @Test("Generated routing rejects a wrong-phase selected entry and preserves peers")
  func macroRoutesGuardToTheSelectedLiveEntry() throws {
    var model = try GeneratedScopedSymmetricRuntime.makeMachine()
    let eligible = StringMacroDevice(id: "eligible")
    let wrongPhase = StringMacroDevice(id: "wrong-phase")
    let peer = StringMacroDevice(id: "peer")
    model.devices.insert(eligible, value: 0)
    model.devices.insert(wrongPhase, value: 1)
    model.devices.insert(peer, value: 4)

    #expect(throws: GeneratedMachineError.self) {
      try model.send(.begin(member: wrongPhase.id))
    }
    #expect(model.devices[wrongPhase.id] == 1)
    #expect(model.devices[eligible.id] == 0)
    #expect(model.devices[peer.id] == 4)

    _ = try model.send(.begin(member: eligible.id))
    #expect(model.devices[eligible.id] == 1)
    #expect(model.devices[wrongPhase.id] == 1)
    #expect(model.devices[peer.id] == 4)
  }

  @Test("Generated routing supports live populations beyond the verification scope")
  func macroDoesNotConsumeBoundedVerifierMembersForLiveRouting() throws {
    var model = try GeneratedScopedSymmetricRuntime.makeMachine()
    let devices = ["first", "second", "third"].map(StringMacroDevice.init)

    for device in devices {
      model.devices.insert(device)
      _ = try model.send(.begin(member: device.id))
    }

    #expect(model.devices.verificationScope == 2)
    #expect(model.devices.count == 3)
    for device in devices {
      #expect(model.devices[device.id] == 1)
    }
    #expect(GeneratedScopedSymmetricRuntime.spec.actions.description.contains("first") == false)
    #expect(GeneratedScopedSymmetricRuntime.spec.actions.description.contains("second") == false)
    #expect(GeneratedScopedSymmetricRuntime.spec.actions.description.contains("third") == false)
  }

  @Test("Generated routing evaluates shared authored guards before its update")
  func macroEvaluatesTheCompleteAuthoredGuard() throws {
    var model = try GeneratedSharedGuardSymmetricRuntime.makeMachine()
    let device = StringMacroDevice(id: "shared-guard")
    model.devices.insert(device)

    #expect(throws: GeneratedMachineError.self) {
      try model.send(.begin(member: device.id))
    }
    #expect(model.devices[device.id] == 0)
  }

  @Test("Generated routing preserves ActionBuilder statement precedence")
  func macroPreservesMultiStatementActionPrecedence() throws {
    let boundedState: [(String, TLAValue)] = [
      ("devices", .function([
        .constant("DevicesMember0"): .int(0),
        .constant("DevicesMember1"): .int(1)
      ]))
    ]
    let boundedSuccessors = try compiledSuccessors(
      of: GeneratedMultiStatementSymmetricRuntime.spec,
      from: projection(boundedState)
    )
    let devices = try #require(TLAStateProjection.Token(validating: "devices"))
    #expect(boundedSuccessors.map { $0.value(for: devices) } == [
      .function([
        .constant("DevicesMember0"): .int(0),
        .constant("DevicesMember1"): .int(11)
      ])
    ])

    var model = try GeneratedMultiStatementSymmetricRuntime.makeMachine()
    let rejected = StringMacroDevice(id: "rejected")
    let selected = StringMacroDevice(id: "selected")
    let peer = StringMacroDevice(id: "peer")
    model.devices.insert(rejected, value: 0)
    model.devices.insert(selected, value: 1)
    model.devices.insert(peer, value: 4)

    #expect(throws: GeneratedMachineError.self) {
      try model.send(.advance(member: rejected.id))
    }
    #expect(model.devices[rejected.id] == 0)
    #expect(model.devices[peer.id] == 4)

    _ = try model.send(.advance(member: selected.id))
    #expect(model.devices[selected.id] == 11)
    #expect(model.devices[peer.id] == 4)
  }

  @Test("Generated routing applies the update from the enabled disjunct only")
  func macroPreservesBranchSpecificCollectionUpdates() throws {
    let boundedState: [(String, TLAValue)] = [
      ("devices", .function([
        .constant("DevicesMember0"): .int(2),
        .constant("DevicesMember1"): .int(1)
      ]))
    ]
    let boundedSuccessors = try compiledSuccessors(
      of: GeneratedDisjunctiveSymmetricRuntime.spec,
      from: projection(boundedState)
    )
    let devices = try #require(TLAStateProjection.Token(validating: "devices"))
    #expect(boundedSuccessors.map { $0.value(for: devices) } == [
      .function([
        .constant("DevicesMember0"): .int(22),
        .constant("DevicesMember1"): .int(1)
      ])
    ])

    var model = try GeneratedDisjunctiveSymmetricRuntime.makeMachine()
    let selected = StringMacroDevice(id: "selected")
    let rejected = StringMacroDevice(id: "rejected")
    let peer = StringMacroDevice(id: "peer")
    model.devices.insert(selected, value: 2)
    model.devices.insert(rejected, value: 1)
    model.devices.insert(peer, value: 0)

    #expect(throws: GeneratedMachineError.self) {
      try model.send(.advance(member: rejected.id))
    }
    #expect(model.devices[rejected.id] == 1)
    #expect(model.devices[peer.id] == 0)

    _ = try model.send(.advance(member: selected.id))
    #expect(model.devices[selected.id] == 22)
    #expect(model.devices[peer.id] == 0)
  }

  @Test("Ordinary allSatisfy actions use every live collection value")
  func macroProjectsLiveCollectionsForAllSatisfyGuards() throws {
    var allowed = try GeneratedAllSatisfyPredicateRuntime.makeMachine()
    let allowedDevices = ["one", "two", "three"].map(StringMacroDevice.init)
    for device in allowedDevices {
      allowed.devices.insert(device)
    }

    let allowedEvidence = try allowed.send(.advance)
    #expect(allowed.phase == 1)
    #expect(allowedEvidence.before.phase == 0)
    #expect(allowedEvidence.after.phase == 1)

    var rejected = try GeneratedAllSatisfyPredicateRuntime.makeMachine()
    let peers = ["one", "two", "three"].map(StringMacroDevice.init)
    let violating = StringMacroDevice(id: "violating")
    for device in peers {
      rejected.devices.insert(device)
    }
    rejected.devices.insert(violating, value: 1)

    let rejectedSnapshot = rejected.state
    #expect(throws: GeneratedMachineError.self) {
      try rejected.send(.advance)
    }
    #expect(rejected.state == rejectedSnapshot)
    #expect(rejected.phase == 0)
    #expect(rejected.devices.count == 4)
    #expect(rejected.devices[violating.id] == 1)
    for device in peers {
      #expect(rejected.devices[device.id] == 0)
    }
  }

  @Test("Ordinary contains actions use live values above verification scope")
  func macroProjectsLiveCollectionsForContainsGuards() throws {
    var model = try GeneratedContainsPredicateRuntime.makeMachine()
    let devices = ["one", "two", "three"].map(StringMacroDevice.init)
    for device in devices {
      model.devices.insert(device)
    }

    let rejectedSnapshot = model.state
    #expect(throws: GeneratedMachineError.self) {
      try model.send(.advance)
    }
    #expect(model.state == rejectedSnapshot)
    #expect(model.phase == 0)

    let matching = StringMacroDevice(id: "matching")
    model.devices.insert(matching, value: 1)
    let evidence = try model.send(.advance)

    #expect(model.phase == 1)
    #expect(evidence.after.phase == 1)
    #expect(model.devices.count == 4)
    #expect(model.devices[matching.id] == 1)
    for device in devices {
      #expect(model.devices[device.id] == 0)
    }
  }
}
