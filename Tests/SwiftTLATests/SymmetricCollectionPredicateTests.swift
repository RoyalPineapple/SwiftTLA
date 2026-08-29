import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import Testing

private struct PredicateDevice: Identifiable, Sendable {
  let id: Int

  init(id: Int) {
    self.id = id
  }
}

@Suite(.serialized)
struct SymmetricCollectionPredicateTests {
  @Test("Parser lowers collection predicates to the direct invariant AST")
  func parserMatchesDirectCollectionPredicateInvariants() throws {
    let parsed = SpecParser.parseSpecClosure(try predicateClosure())
    let direct = directPredicateSpec()
    let parsedCompilation = try parsed.compile(specificationName: "CollectionPredicateSemantics")
    let directCompilation = try direct.compile()

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.symmetricCollections.map(\.metadata)
      == direct.symmetricCollections.map(\.metadata))
    #expect(parsedCompilation.identity == directCompilation.identity)
    #expect(try renderedInitialStates(in: parsedCompilation) == renderedInitialStates(in: directCompilation))
    #expect(try ModelChecker(compilation: parsedCompilation, configuration: symmetricExplorationConfiguration()).check().description
      == ModelChecker(compilation: directCompilation, configuration: symmetricExplorationConfiguration()).check().description)
  }

  @Test("Parser lowers shorthand collection predicates in ordinary action guards")
  func parserLowersShorthandCollectionPredicateActionGuards() throws {
    let parsed = SpecParser.parseSpecClosure(try shorthandPredicateClosure())

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.actions.count == 2)
    guard case .and(
      .guard_(.forAll(.domain(.variable("devices")), let member, let body)),
      .assign(.named("phase"), .value(.int(1)))
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
      .assign(.named("phase"), .value(.int(0)))
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

  @Test("Shorthand collection predicates compile and check")
  func shorthandCollectionPredicatesCompileAndCheck() throws {
    let parsed = SpecParser.parseSpecClosure(try shorthandPredicateClosure())
    let compilation = try parsed.compile(specificationName: "ShorthandCollectionPredicates")

    #expect(parsed.actions.count == 2)
    #expect(parsed.invariants.count == 2)
    #expect(try ModelChecker(
      compilation: compilation,
      configuration: symmetricExplorationConfiguration()
    ).check().description.contains("OK"))
  }

  @Test("Parsed collection predicates preserve invariant violations")
  func parserPreservesCollectionPredicateInvariantViolations() throws {
    let parsed = SpecParser.parseSpecClosure(try violatingPredicateClosure())
    let parsedCompilation = try parsed.compile(specificationName: "ViolatingPredicate")
    let devices = SymmetricCollectionVar<PredicateDevice, Int>("devices")
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
    let parsedResult = try ModelChecker(
      compilation: parsedCompilation,
      configuration: symmetricExplorationConfiguration()
    ).check()
    let directResult = try ModelChecker(
      compilation: try direct.compile(),
      configuration: symmetricExplorationConfiguration()
    ).check()
    #expect(parsedResult.description == directResult.description)
    guard case .invariantViolated(let name, _, _) = parsedResult else {
      Issue.record("Expected an invariant violation, got: \(parsedResult)")
      return
    }
    #expect(name == "validPhase")
  }

  @Test("Unsupported invariant syntax becomes a source-aware diagnostic")
  func parserRejectsUnsupportedCollectionPredicateInvariant() throws {
    let parsed = SpecParser.parseSpecClosure(try unsupportedPredicateClosure())

    #expect(parsed.invariants.isEmpty)
    let diagnostic = try #require(parsed.diagnostics.first)
    #expect(parsed.diagnostics.count == 1)
    #expect(diagnostic.message == "Invariant 'unsupported' contains an unsupported invariant expression.")
    #expect(diagnostic.source == "devices.allSatisfy { phase in unmodeledPredicate(phase) }")
    #expect((diagnostic.sourceSpan.location == .unavailable) == false)
    #expect(diagnostic.sourceSpan.utf8Length == diagnostic.source.utf8.count)
  }

  @Test("Macro diagnostics anchor unsupported predicates at the authored expression")
  func macroDiagnosticAnchorsUnsupportedPredicate() throws {
    let result = try buildExternalConsumer("InvalidCollectionPredicateMacro")

    #expect(result.status != 0)
  }

  private func predicateClosure() throws -> ClosureExprSyntax {
    try parseClosure("""
    {
      let devices = SymmetricCollectionVar<PredicateDevice, Int>("devices")
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
      let devices = SymmetricCollectionVar<PredicateDevice, Int>("devices")
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
      let devices = SymmetricCollectionVar<PredicateDevice, Int>("devices")
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
      let devices = SymmetricCollectionVar<PredicateDevice, Int>("devices")
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

  private func symmetricExplorationConfiguration() throws -> FiniteExplorationConfiguration {
    try FiniteExplorationConfiguration(
      maximumStateLimit: 100_000,
      symmetryReduction: .enabled(maximumPermutationCount: 100_000))
  }

  private func directPredicateSpec() -> TLASpec {
    let devices = SymmetricCollectionVar<PredicateDevice, Int>("devices")
    return TLASpec("CollectionPredicateSemantics") {
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
