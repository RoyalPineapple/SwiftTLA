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
}

public struct StringMacroDevice: Identifiable, Sendable {
  public let id: String
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
    in compilation: CompiledSpecification,
    from values: [TLAValue]
  ) throws -> [CompiledState] {
    let state = try CompiledState(formalValues: values, compilation: compilation)
    return try CompiledRuntime(compilation: compilation)
      .successors(from: state)
      .map(\.state)
  }

  private func collectionValue(_ values: [Int], in spec: TLASpec) throws -> TLAValue {
    let members = try #require(spec.symmetricCollections.first?.metadata.members)
    try #require(members.count == values.count)
    return .function(Dictionary(uniqueKeysWithValues: zip(members, values.map(TLAValue.int))))
  }

  private struct Device: Identifiable {
    let id: Int
  }

  @Test("Parsed symmetric declarations retain type, scope, and action ownership")
  func parserRetainsCollectionStructure() throws {
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
    #expect(parsed.symmetricCollections[0].generatedElementType == "Device")
    #expect(parsed.symmetricCollections[0].generatedValueType == "Int")
    #expect(parsed.symmetricCollections[0].verificationScope == 2)
    let action = try #require(parsed.actions.first)
    guard case .existsAction(_, .domain(.variable(let collection)), _) = action.body else {
      Issue.record("Expected a collection-member existential")
      return
    }
    #expect(collection == "devices")
    #expect(parsed.diagnostics.isEmpty)
  }

  @Test("The declared collection name is independent of its Swift local name")
  func parserAndBuilderShareTheDeclaredCollectionName() throws {
    let source = """
    {
      let devices = SymmetricCollectionVar<Device, Int>("phases")
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("begin", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
      Invariant("valid") {
        devices.allSatisfy { phase in phase >= 0 && phase <= 1 }
      }
    }
    """
    let parsed = SpecParser.parseSpecClosure(try parseClosure(source))
    let devices = SymmetricCollectionVar<Device, Int>("phases")
    let built = TLASpec("DeclaredCollectionName") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("begin", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
      Invariant("valid") {
        devices.allSatisfy { phase in phase >= 0 && phase <= 1 }
      }
    }

    let parsedCompilation = try parsed.compile(specificationName: "DeclaredCollectionName")
    let builtCompilation = try built.compile()

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.symmetricCollections.map(\.name) == ["phases"])
    let action = try #require(parsed.actions.first)
    guard case .existsAction(_, .domain(.variable(let collection)), _) = action.body else {
      Issue.record("Expected a collection-member existential")
      return
    }
    #expect(collection == "phases")
    #expect(parsedCompilation.identity == builtCompilation.identity)
    #expect(parsedCompilation.semantics.actions.first?.bindings.first?.values
      == builtCompilation.semantics.actions.first?.bindings.first?.values)
    #expect(parsedCompilation.renderedTLAModuleBundle().root.tla
      == builtCompilation.renderedTLAModuleBundle().root.tla)
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

    #expect(parsed.symmetricCollections.map(\.generatedElementType) == ["Model.Device"])
    #expect(parsed.symmetricCollections.map(\.generatedValueType) == ["Swift.Int"])
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
    let initial = try #require(parsed.variables.first?.initial)
    let devices = SymmetricCollectionVar<Device, Int>("devices")
    let runtimeBuilt = TLASpec("CollectionActionBehavior") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("begin", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: devices[member] + 1)
      }
    }

    let parsedCompilation = try parsed.compile(specificationName: "CollectionActionBehavior")
    let runtimeCompilation = try runtimeBuilt.compile()
    let advanced = try collectionValue([1], in: runtimeBuilt)

    #expect(parsed.diagnostics.isEmpty)
    #expect(try compiledSuccessors(in: parsedCompilation, from: [initial])
      == compiledSuccessors(in: runtimeCompilation, from: [initial]))
    #expect(try compiledSuccessors(in: parsedCompilation, from: [advanced]).isEmpty)
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
    #expect(parsed.actions.map { alphaKey($0.body) } == authored.actions.map { alphaKey($0.body) })
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

      #expect(SpecParser.parseSpecClosure(closure).diagnostics.isEmpty == false)
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

    #expect(SpecParser.parseSpecClosure(closure).diagnostics.isEmpty == false)
  }

  @Test("Generated state binds the exact collection population to application IDs")
  func macroBindsExactApplicationIDs() throws {
    let deviceID = 42
    var model = try GeneratedSymmetricRuntime.makeMachine(
      .init(devices: [deviceID: 0]),
      devices: [deviceID]
    )

    #expect(model.state.devices == [deviceID: 0])
    let result = try model.send(.begin(member: deviceID))

    #expect(model.state.devices == [deviceID: 1])
    #expect(result.before.devices == [deviceID: 0])
    #expect(result.after.devices == [deviceID: 1])
    #expect(result.action == .begin(member: deviceID))
    #expect(throws: GeneratedMachineStateDiagnostic.self) {
      try model.send(.begin(member: 99))
    }
  }

  @Test("Generated actors wrap the same exact collection population")
  func actorBindsExactApplicationIDs() async throws {
    let deviceID = 42
    let actor = try GeneratedSymmetricRuntime.Actor(devices: [deviceID])

    let transition = try await actor.send(.begin(member: deviceID))

    #expect(transition.before.devices == [deviceID: 0])
    #expect(transition.after.devices == [deviceID: 1])
    #expect(await actor.state.devices == [deviceID: 1])
  }

  @Test("Generated machines require one unique application ID per compiled member")
  func macroRequiresTheExactPopulation() {
    #expect(throws: GeneratedMachineStateDiagnostic.self) {
      _ = try GeneratedScopedSymmetricRuntime.makeMachine(devices: ["only-one"])
    }
    #expect(throws: GeneratedMachineStateDiagnostic.self) {
      _ = try GeneratedScopedSymmetricRuntime.makeMachine(devices: ["same", "same"])
    }
  }

  @Test("Generated collection actions evaluate expression-backed updates")
  func macroEvaluatesExpressionBackedUpdates() throws {
    let deviceID = 42
    var model = try GeneratedExpressionSymmetricRuntime.makeMachine(devices: [deviceID])

    for expected in 1...5 {
      _ = try model.send(.advance(member: deviceID))
      #expect(model.state.devices == [deviceID: expected])
    }

    #expect(throws: GeneratedMachineError.self) {
      try model.send(.advance(member: deviceID))
    }
  }

  @Test("Generated routing rejects a wrong-phase selected entry and preserves peers")
  func macroRoutesGuardToTheSelectedEntry() throws {
    let eligible = "eligible"
    let wrongPhase = "wrong-phase"
    let ids = [eligible, wrongPhase]
    var model = try GeneratedScopedSymmetricRuntime.makeMachine(devices: ids)

    _ = try model.send(.begin(member: wrongPhase))

    #expect(throws: GeneratedMachineError.self) {
      try model.send(.begin(member: wrongPhase))
    }
    #expect(model.state.devices == [eligible: 0, wrongPhase: 1])

    _ = try model.send(.begin(member: eligible))
    #expect(model.state.devices == [eligible: 1, wrongPhase: 1])
  }

  @Test("Generated routing evaluates shared authored guards before its update")
  func macroEvaluatesTheCompleteAuthoredGuard() throws {
    let deviceID = "shared-guard"
    var model = try GeneratedSharedGuardSymmetricRuntime.makeMachine(devices: [deviceID])

    #expect(throws: GeneratedMachineError.self) {
      try model.send(.begin(member: deviceID))
    }
    #expect(model.state.phase == 4)
    #expect(model.state.devices == [deviceID: 0])
  }

  @Test("Compiled collection actions preserve ActionBuilder statement precedence")
  func compiledActionPreservesMultiStatementPrecedence() throws {
    let boundedState = try collectionValue([0, 1], in: GeneratedMultiStatementSymmetricRuntime.spec)
    let compilation = try GeneratedMultiStatementSymmetricRuntime.spec.compile()
    let boundedSuccessors = try compiledSuccessors(
      in: compilation,
      from: [boundedState]
    )
    let expected = try collectionValue([0, 11], in: GeneratedMultiStatementSymmetricRuntime.spec)
    #expect(try boundedSuccessors.map {
      try renderedValue(named: "devices", in: $0, compilation: compilation)
    } == [expected])
  }

  @Test("Compiled and generated actions apply the update from the enabled disjunct")
  func actionsPreserveBranchSpecificCollectionUpdates() throws {
    let boundedState = try collectionValue([2, 1], in: GeneratedDisjunctiveSymmetricRuntime.spec)
    let compilation = try GeneratedDisjunctiveSymmetricRuntime.spec.compile()
    let boundedSuccessors = try compiledSuccessors(
      in: compilation,
      from: [boundedState]
    )
    let expected = try collectionValue([22, 1], in: GeneratedDisjunctiveSymmetricRuntime.spec)
    #expect(try boundedSuccessors.map {
      try renderedValue(named: "devices", in: $0, compilation: compilation)
    } == [expected])

    let selected = "selected"
    let rejected = "rejected"
    var model = try GeneratedDisjunctiveSymmetricRuntime.makeMachine(
      devices: [selected, rejected]
    )

    _ = try model.send(.advance(member: selected))
    #expect(model.state.devices == [selected: 1, rejected: 0])

    #expect(throws: GeneratedMachineError.self) {
      try model.send(.advance(member: selected))
    }
    #expect(model.state.devices == [selected: 1, rejected: 0])
  }

  @Test("Ordinary allSatisfy actions use every declared collection value")
  func macroEvaluatesAllSatisfyAcrossTheDeclaredPopulation() throws {
    let ids = ["one", "two"]
    var allowed = try GeneratedAllSatisfyPredicateRuntime.makeMachine(devices: ids)

    let allowedEvidence = try allowed.send(.advance)
    #expect(allowed.state.phase == 1)
    #expect(allowedEvidence.before.phase == 0)
    #expect(allowedEvidence.after.phase == 1)

    let compilation = try GeneratedAllSatisfyPredicateRuntime.spec.compile()
    let formalDevices = try collectionValue([0, 1], in: GeneratedAllSatisfyPredicateRuntime.spec)
    #expect(try compiledSuccessors(in: compilation, from: [.int(0), formalDevices]).isEmpty)
  }

  @Test("Ordinary contains actions use every declared collection value")
  func macroEvaluatesContainsAcrossTheDeclaredPopulation() throws {
    let ids = ["one", "two"]
    var rejected = try GeneratedContainsPredicateRuntime.makeMachine(devices: ids)

    let rejectedSnapshot = rejected.state
    #expect(throws: GeneratedMachineError.self) {
      try rejected.send(.advance)
    }
    #expect(rejected.state == rejectedSnapshot)

    let compilation = try GeneratedContainsPredicateRuntime.spec.compile()
    let formalDevices = try collectionValue([0, 1], in: GeneratedContainsPredicateRuntime.spec)
    let successors = try compiledSuccessors(
      in: compilation,
      from: [.int(0), formalDevices]
    )
    #expect(successors.count == 1)
    #expect(try successors.map {
      try renderedValue(named: "phase", in: $0, compilation: compilation)
    } == [.int(1)])
  }
}
