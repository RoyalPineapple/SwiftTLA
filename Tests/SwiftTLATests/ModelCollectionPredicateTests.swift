@testable import SwiftTLAPlugin
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
struct ModelCollectionPredicateTests {
  @Test("Collection action binders preserve reads of authored member state")
  func actionBindersDoNotCaptureState() throws {
    let devices = CollectionVar<PredicateDevice, Int>("devices")
    let member = Var<Int>("member", 7)
    let built = TLASpec("ActionBindings") {
      Variable(member)
      ModelCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("advance", on: devices) { selected in
        devices.update(selected, to: member + 1)
      }
    }
    let source = #"""
    {
      let member = Var<Int>("member", 7)
      let devices = CollectionVar<PredicateDevice, Int>("devices")
      ModelCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("advance", on: devices) { selected in
        devices.update(selected, to: member + 1)
      }
    }
    """#
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(named: "ActionBindings", closure)
    try #require(parsed.diagnostics.isEmpty)
    let compilations = try [built, parsed].map { try $0.compile() }
    #expect(compilations[0].identity == compilations[1].identity)
    for compilation in compilations {
      let runtime = CompiledRuntime(compilation: compilation)
      let initial = try #require(runtime.initialStates().first)
      let memberID = try #require(compilation.layout.variables.first { $0.declaration.name == "member" }?.id)
      let devicesID = try #require(compilation.layout.variables.first { $0.declaration.name == "devices" }?.id)
      for value in [7, 9] {
        let state = try initial.updating(memberID, to: .integer(value))
        let successors = try runtime.successors(from: state)
        try #require(successors.count == 1)
        #expect(try successors[0].state.value(for: memberID) == .integer(value))
        guard case .function(let values) = try successors[0].state.value(for: devicesID) else {
          Issue.record("Expected collection state")
          continue
        }
        #expect(Array(values.values) == [.integer(value + 1)])
      }
    }
  }

  @Test("Collection predicate binders do not capture authored member state")
  func predicateBindersDoNotCaptureState() throws {
    let devices = CollectionVar<PredicateDevice, Int>("devices")
    let member = Var<Int>("member", 7)
    let built = TLASpec("PredicateBindings") {
      Variable(member)
      ModelCollection(devices, verificationScope: 2, initial: 7)
      Invariant("allMatch") { devices.allSatisfy { value in value == member } }
      Invariant("anyMatch") { devices.contains { value in value == member } }
    }
    let source = #"""
    {
      let member = Var<Int>("member", 7)
      let devices = CollectionVar<PredicateDevice, Int>("devices")
      ModelCollection(devices, verificationScope: 2, initial: 7)
      Invariant("allMatch") { devices.allSatisfy { value in value == member } }
      Invariant("anyMatch") { devices.contains { value in value == member } }
    }
    """#
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(named: "PredicateBindings", closure)
    try #require(parsed.diagnostics.isEmpty)
    let compilations = try [built, parsed].map { try $0.compile() }
    #expect(compilations[0].identity == compilations[1].identity)
    for compilation in compilations {
      let runtime = CompiledRuntime(compilation: compilation)
      let state = try #require(runtime.initialStates().first)
      let memberID = try #require(compilation.layout.variables.first { $0.declaration.name == "member" }?.id)
      let different = try state.updating(memberID, to: .integer(8))
      for invariant in compilation.semantics.behavior.invariants {
        #expect(try runtime.invariantHolds(invariant, in: state))
        #expect(try !runtime.invariantHolds(invariant, in: different))
      }
    }
  }

  @Test("Collection actions reject unsupported statements instead of dropping them", arguments: ["UnsupportedStep()", "var ignored = 0"])
  func collectionActionsRejectUnsupportedStatements(_ statement: String) throws {
    let source = """
    {
      let devices = CollectionVar<PredicateDevice, Int>("stored")
      ModelCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("advance", on: devices) { member in
        \(statement)
        devices.update(member, to: 1)
      }
    }
    """
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(named: "InvalidCollectionAction", closure)
    #expect(parsed.actions.isEmpty)
    #expect(parsed.diagnostics.contains { $0.message.contains("unsupported action expression") })
    #expect(parsed.diagnostics.first?.source == statement)
  }

  @Test("Collection actions preserve lexical values and declared collection names")
  func collectionActionsPreserveLexicalValues() throws {
    let source = #"""
    {
      let devices = CollectionVar<PredicateDevice, Int>("stored")
      ModelCollection(devices, verificationScope: 1, initial: 0)
      CollectionAction("advance", on: devices) { selected in
        let previous = devices[selected]
        devices.update(selected, to: previous + 1)
      }
    }
    """#
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(named: "CollectionActionBindings", closure)
    try #require(parsed.diagnostics.isEmpty)
    let action = try #require(parsed.actions.first)
    guard case .existsAction(let member, .domain(.variable("stored")), let body) = action.body else {
      Issue.record("Expected a bound collection action")
      return
    }
    #expect(body == .assign(.named("stored"), .except(.variable("stored"), .variable(member),
      .add(.functionApply(.variable("stored"), .variable(member)), .int(1)))))
    let compilation = try parsed.compile()
    let runtime = CompiledRuntime(compilation: compilation)
    let initial = try #require(runtime.initialStates().first)
    #expect(try runtime.successors(from: initial).count == 1)
  }

  @Test("Collection predicate parameters retain the declared tuple value type")
  func predicateParametersRetainDeclaredValueTypes() throws {
    let source = #"""
    {
      let batches = CollectionVar<PredicateDevice, TupleExpr<Int>>("stored")
      Invariant("nonempty") { batches.allSatisfy { batch in batch.count > 0 } }
    }
    """#
    let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
    let parsed = SpecParser.parseSpecClosure(named: "TupleCollections", closure)
    try #require(parsed.diagnostics.isEmpty)
    let invariant = try #require(parsed.invariants.first)
    guard case .forAll(.domain(.variable("stored")), let member, let body) = invariant.body else {
      Issue.record("Expected a predicate over the declared collection")
      return
    }
    #expect(body == .greaterThan(
      .tupleLength(.functionApply(.variable("stored"), .variable(member))), .int(0)))
  }

  @Test("Parser lowers collection predicates to the direct invariant AST")
  func parserMatchesDirectCollectionPredicateInvariants() throws {
    let parsed = SpecParser.parseSpecClosure(named: "CollectionPredicateSemantics", try predicateClosure())
    let direct = directPredicateSpec()
    let parsedCompilation = try parsed.compile()
    let directCompilation = try direct.compile()

    #expect(parsed.diagnostics.isEmpty)
    #expect(parsed.collections.map(\.metadata)
      == direct.collections.map(\.metadata))
    #expect(parsedCompilation.identity == directCompilation.identity)
    #expect(try renderedInitialStates(in: parsedCompilation) == renderedInitialStates(in: directCompilation))
    #expect(try ModelChecker(compilation: parsedCompilation, configuration: symmetricExplorationConfiguration()).check().description
      == ModelChecker(compilation: directCompilation, configuration: symmetricExplorationConfiguration()).check().description)
  }

  @Test("Parser lowers shorthand collection predicates in ordinary action guards")
  func parserLowersShorthandCollectionPredicateActionGuards() throws {
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", try shorthandPredicateClosure())

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
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", try predicateClosure())
    let builder = try #require(parsed.invariants.first(where: { $0.name == "validPhase" })?.body)

    #expect(alphaKey(direct) == alphaKey(builder))
  }

  @Test("Shorthand collection predicates compile and check")
  func shorthandCollectionPredicatesCompileAndCheck() throws {
    let parsed = SpecParser.parseSpecClosure(named: "ShorthandCollectionPredicates", try shorthandPredicateClosure())
    let compilation = try parsed.compile()

    #expect(parsed.actions.count == 2)
    #expect(parsed.invariants.count == 2)
    #expect(try ModelChecker(
      compilation: compilation,
      configuration: symmetricExplorationConfiguration()
    ).check().description.contains("OK"))
  }

  @Test("Parsed collection predicates preserve invariant violations")
  func parserPreservesCollectionPredicateInvariantViolations() throws {
    let parsed = SpecParser.parseSpecClosure(named: "ViolatingPredicate", try violatingPredicateClosure())
    let parsedCompilation = try parsed.compile()
    let devices = CollectionVar<PredicateDevice, Int>("devices")
    let direct = TLASpec("ViolatingPredicate") {
      ModelCollection(devices, verificationScope: 1, initial: 0)
      Symmetry(devices)
      CollectionAction("break", on: devices) { member in
        devices.update(member, to: 2)
      }
      Invariant("validPhase") {
        devices.allSatisfy { phase in phase <= 1 }
      }
    }

    #expect(parsed.diagnostics.isEmpty)
    let parsedOutcome = try ModelChecker(
      compilation: parsedCompilation,
      configuration: symmetricExplorationConfiguration()
    ).check()
    let directOutcome = try ModelChecker(
      compilation: try direct.compile(),
      configuration: symmetricExplorationConfiguration()
    ).check()
    #expect(parsedOutcome.description == directOutcome.description)
    guard case .invariantViolated(let name, _, _) = parsedOutcome else {
      Issue.record("Expected an invariant violation, got: \(parsedOutcome)")
      return
    }
    #expect(name == "validPhase")
  }

  @Test("Unsupported invariant syntax becomes a source-aware diagnostic")
  func parserRejectsUnsupportedCollectionPredicateInvariant() throws {
    let parsed = SpecParser.parseSpecClosure(named: "Parsed", try unsupportedPredicateClosure())

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
    let build = try buildExternalConsumer("InvalidCollectionPredicateMacro")

    #expect(build.status != 0)
  }

  private func predicateClosure() throws -> ClosureExprSyntax {
    try parseClosure("""
    {
      let devices = CollectionVar<PredicateDevice, Int>("devices")
      ModelCollection(devices, verificationScope: 2, initial: 0)
      Symmetry(devices)
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
      let devices = CollectionVar<PredicateDevice, Int>("devices")
      ModelCollection(devices, verificationScope: 1, initial: 0)
      Symmetry(devices)
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
      let devices = CollectionVar<PredicateDevice, Int>("devices")
      Variable(phase, 0)
      ModelCollection(devices, verificationScope: 2, initial: 0)
      Symmetry(devices)
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
      let devices = CollectionVar<PredicateDevice, Int>("devices")
      ModelCollection(devices, verificationScope: 1, initial: 0)
      Symmetry(devices)
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
    let devices = CollectionVar<PredicateDevice, Int>("devices")
    return TLASpec("CollectionPredicateSemantics") {
      ModelCollection(devices, verificationScope: 2, initial: 0)
      Symmetry(devices)
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
