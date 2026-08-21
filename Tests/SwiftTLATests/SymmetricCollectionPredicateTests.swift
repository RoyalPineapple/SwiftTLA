import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLAMacros
import Testing

public struct PredicateMacroDevice: Identifiable, Sendable {
  public let id: Int

  public init(id: Int) {
    self.id = id
  }
}

@TLAModel
public struct GeneratedPredicateRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedPredicateRuntime") {
      let devices = SymmetricCollectionVar<PredicateMacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
      Invariant("validPhase") {
        devices.allSatisfy { phase in phase >= 0 && phase <= 1 }
      }
      Invariant("hasModeledPhase") {
        devices.contains(where: { phase in phase >= 0 })
      }
    }
  }
}

@TLAModel
public struct GeneratedShorthandPredicateRuntime {
  public static var spec: TLASpec {
    TLASpec("GeneratedShorthandPredicateRuntime") {
      let phase = Var<Int>("phase")
      let devices = SymmetricCollectionVar<PredicateMacroDevice, Int>("devices")
      Variable(phase, 0)
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      Action("advance") {
        devices.allSatisfy { $0 == 0 } && phase.becomes(1)
      }
      Action("reset") {
        devices.contains(where: { $0 == 0 }) && phase.becomes(0)
      }
      Invariant("validPhase") {
        devices.allSatisfy { $0 >= 0 && $0 <= 1 }
      }
      Invariant("hasModeledPhase") {
        devices.contains(where: { $0 >= 0 })
      }
    }
  }
}

@Suite(.serialized)
struct SymmetricCollectionPredicateTests {
  @Test("Parser lowers collection predicates to the direct invariant AST")
  func parserMatchesDirectCollectionPredicateInvariants() throws {
    let parsed = SpecParser.parseSpecClosure(try predicateClosure())
    let direct = directPredicateSpec()
    let parsedSpec = spec(from: parsed)

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.symmetricCollections.map(\.declaration.metadata)
      == direct.symmetricCollections.map(\.metadata))
    #expect(try parsedSpec.compile().identity == direct.compile().identity)
    #expect(try parsedSpec.compile().initialStateProjections() == direct.compile().initialStateProjections())
    #expect(try ModelChecker(spec: parsedSpec).check().description
      == ModelChecker(spec: direct).check().description)
  }

  @Test("macro and source-model compilation share collection binder identity")
  func macroAndSourceModelCompilationShareCollectionBinderIdentity() throws {
    let macroCompilation = try GeneratedPredicateRuntime.compiledSpecification()
    let sourceCompilation = try GeneratedPredicateRuntime.spec.compile()

    #expect(macroCompilation.identity == sourceCompilation.identity)
    #expect(try macroCompilation.renderedTLAModuleBundle().root.tla
      == sourceCompilation.renderedTLAModuleBundle().root.tla)
  }

  @Test("Macro expansion retains collection predicate invariants and runtime parity")
  func macroRuntimeMatchesDirectCollectionPredicateBehavior() throws {
    let direct = directPredicateSpec()
    let generated = GeneratedPredicateRuntime.spec

    #expect(generated.symmetricCollections.map(\.metadata) == direct.symmetricCollections.map(\.metadata))
    #expect(normalized(generated.invariants.map(\.description)) == normalized(direct.invariants.map(\.description)))
    #expect(try generated.compile().initialStateProjections() == direct.compile().initialStateProjections())
    #expect(try ModelChecker(spec: generated).check().description
      == ModelChecker(spec: direct).check().description)
    #expect(!generated.invariants.description.contains("PredicateMacroDevice"))
  }

  @Test("Parser lowers shorthand collection predicates in ordinary action guards")
  func parserLowersShorthandCollectionPredicateActionGuards() throws {
    let parsed = SpecParser.parseSpecClosure(try shorthandPredicateClosure())

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.actions.count == 2)
    guard case .and(
      .guard_(.forAll(.domain(.variable("devices")), let member, let body)),
      .assign("phase", .value(.int(1)))
    ) = parsed.actions[0].body else {
      Issue.record("Expected an allSatisfy guard followed by phase assignment, got: \(parsed.actions[0].body)")
      return
    }
    #expect(body == .equal(
      .functionApply(.variable("devices"), .variable(member)),
      .value(.int(0))
    ))
    guard case .and(
      .guard_(.exists(.domain(.variable("devices")), let selected, let selectedBody)),
      .assign("phase", .value(.int(0)))
    ) = parsed.actions[1].body else {
      Issue.record("Expected a contains(where:) guard followed by phase assignment, got: \(parsed.actions[1].body)")
      return
    }
    #expect(selectedBody == .equal(
      .functionApply(.variable("devices"), .variable(selected)),
      .value(.int(0))
    ))
  }

  @Test("Direct and builder parsing share collection predicate bindings")
  func directAndBuilderParsingShareCollectionPredicateBindings() throws {
    let source = "devices.allSatisfy { phase in phase >= 0 && phase <= 1 }"
    let expression = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
    let direct = try #require(SpecParser.decodeStateExpr(expression))
    let parsed = SpecParser.parseSpecClosure(try predicateClosure())
    let builder = try #require(parsed.invariants.first(where: { $0.name == "validPhase" })?.body)

    #expect(direct == builder)
  }

  @Test("Macro expansion accepts shorthand collection predicates")
  func macroExpansionAcceptsShorthandCollectionPredicates() throws {
    let generated = GeneratedShorthandPredicateRuntime.spec

    #expect(generated.actions.count == 2)
    #expect(generated.invariants.count == 2)
    #expect(try ModelChecker(spec: generated).check().description.contains("OK"))
  }

  @Test("Parsed collection predicates preserve invariant violations")
  func parserPreservesCollectionPredicateInvariantViolations() throws {
    let parsed = SpecParser.parseSpecClosure(try violatingPredicateClosure())
    let parsedSpec = spec(from: parsed)
    let devices = SymmetricCollectionVar<PredicateMacroDevice, Int>("devices")
    let direct = TLASpec("ViolatingPredicate") {
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("break", on: devices) { member in
        devices.update(member, to: 2)
      }
      Invariant("validPhase") {
        devices.allSatisfy { phase in phase <= 1 }
      }
    }

    #expect(parsed.diagnostics.isEmpty)
    let parsedResult = try ModelChecker(spec: parsedSpec).check()
    let directResult = try ModelChecker(spec: direct).check()
    #expect(parsedResult.description == directResult.description)
    guard case .bounded(_, .invariantViolated(let name, _, _)) = parsedResult else {
      Issue.record("Expected a bounded invariant violation, got: \(parsedResult)")
      return
    }
    #expect(name == "validPhase")
  }

  @Test("Unsupported invariant syntax becomes a source-aware diagnostic")
  func parserRejectsUnsupportedCollectionPredicateInvariant() throws {
    let parsed = SpecParser.parseSpecClosure(try unsupportedPredicateClosure())

    #expect(parsed.invariants.isEmpty)
    #expect(parsed.diagnostics.isEmpty)
  }

  @Test("Macro diagnostics anchor unsupported predicates at the authored expression")
  func macroDiagnosticAnchorsUnsupportedPredicate() throws {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixture = repository.appendingPathComponent("Tests/Fixtures/InvalidCollectionPredicateMacro")
    let scratch = FileManager.default.temporaryDirectory
      .appendingPathComponent("SwiftTLA-invalid-predicate-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let outputURL = scratch.appendingPathComponent("build.log")
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "build", "--package-path", fixture.path, "--scratch-path", scratch.path]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    try output.close()

    #expect(process.terminationStatus != 0)
  }

  private func predicateClosure() throws -> ClosureExprSyntax {
    try parseClosure("""
    {
      let devices = SymmetricCollectionVar<PredicateMacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
      Invariant("validPhase") {
        devices.allSatisfy { phase in phase >= 0 && phase <= 1 }
      }
      Invariant("hasModeledPhase") {
        devices.contains(where: { phase in phase >= 0 })
      }
    }
    """)
  }

  private func violatingPredicateClosure() throws -> ClosureExprSyntax {
    try parseClosure("""
    {
      let devices = SymmetricCollectionVar<PredicateMacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("break", on: devices) { member in
        devices.update(member, to: 2)
      }
      Invariant("validPhase") {
        devices.allSatisfy { phase in phase <= 1 }
      }
    }
    """)
  }

  private func shorthandPredicateClosure() throws -> ClosureExprSyntax {
    try parseClosure("""
    {
      let phase = Var<Int>("phase")
      let devices = SymmetricCollectionVar<PredicateMacroDevice, Int>("devices")
      Variable(phase, 0)
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      Action("advance") {
        devices.allSatisfy { $0 == 0 } && phase.becomes(1)
      }
      Action("reset") {
        devices.contains(where: { $0 == 0 }) && phase.becomes(0)
      }
      Invariant("validPhase") {
        devices.allSatisfy { $0 >= 0 && $0 <= 1 }
      }
      Invariant("hasModeledPhase") {
        devices.contains(where: { $0 >= 0 })
      }
    }
    """)
  }

  private func unsupportedPredicateClosure() throws -> ClosureExprSyntax {
    try parseClosure("""
    {
      let devices = SymmetricCollectionVar<PredicateMacroDevice, Int>("devices")
      SymmetricCollection(devices, verificationScope: 1, initial: 0)
      Invariant("unsupported") {
        devices.allSatisfy { phase in unmodeledPredicate(phase) }
      }
    }
    """)
  }

  private func parseClosure(_ source: String) throws -> ClosureExprSyntax {
    try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
  }

  private func directPredicateSpec() -> TLASpec {
    let devices = SymmetricCollectionVar<PredicateMacroDevice, Int>("devices")
    return TLASpec("PredicateParity") {
      SymmetricCollection(devices, verificationScope: 2, initial: 0)
      CollectionAction("advance", on: devices) { member in
        devices[member] == 0 && devices.update(member, to: 1)
      }
      Invariant("validPhase") {
        devices.allSatisfy { phase in phase >= 0 && phase <= 1 }
      }
      Invariant("hasModeledPhase") {
        devices.contains(where: { phase in phase >= 0 })
      }
    }
  }

  private func spec(from parsed: SpecParser.ParsedSpecComponents) -> TLASpec {
    TLASpec(
      name: "ParsedPredicate",
      variables: parsed.variables.map { NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet) },
      actions: parsed.actions.map { NamedAction(name: $0.name, body: $0.body) },
      invariants: parsed.invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
      symmetricCollections: parsed.symmetricCollections.map(\.declaration)
    )
  }

}
