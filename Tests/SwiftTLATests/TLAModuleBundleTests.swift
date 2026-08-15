import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct ImportedFormalModuleGeneratedModel {
  static var spec: TLASpec {
    #spec("ImportedFormalModuleGeneratedModel") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
      Algorithm("ImportedFormalModuleGeneratedModel") {
        let value = SharedVar(initial: 0)
        Do("keep") { Assign(value, to: value.expr) }
      }
    }
  }
}

@Suite("TLA+ module bundles")
struct TLAModuleBundleTests {
  @Test("a generated model preserves its imported module")
  func generatedModelRetainsImportedModule() {
    ImportedFormalModuleGeneratedModel._checkParserTree()
    #expect(ImportedFormalModuleGeneratedModel.spec.imports.map { $0.name } == ["ZSequences"])
    #expect(ImportedFormalModuleGeneratedModel.spec.importConfigurations == [
      ZSequences.boundedNaturalNumbers(0...2)
    ])
  }

  @Test("the parser records imports for builder fidelity")
  func parserRetainsImportedModule() {
    let source = "{ Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2)) }"
    let closure = Parser.parse(source: source).statements.first!.item.as(ClosureExprSyntax.self)!
    let parsed = SpecParser.parseSpecClosure(closure)
    let runtime = TLASpec("Imported") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
    }
    let parserTree = ParsedSpecModel(
      variables: [], actions: [], invariants: [], imports: parsed.imports,
      importConfigurations: parsed.importConfigurations
    )
    let runtimeTree = ParsedSpecModel(
      variables: [], actions: [], invariants: [], imports: runtime.imports.map(\.name),
      importConfigurations: runtime.importConfigurations
    )

    #expect(_tlaAlphaEquivalent(parserTree, runtimeTree))
  }

  @Test("the parser preserves qualified ZSequences calls")
  func parserRetainsQualifiedModuleCalls() {
    let source = "ZSequences.rotation(of: corpus, leftBy: 1)"
    let expression = Parser.parse(source: source).statements.first!.item.as(ExprSyntax.self)!
    let parsed = SpecParser.decodeStateExpr(expression)

    #expect(parsed == .recursiveCall("Rotation", [.variable("corpus"), .int(1)]))
  }

  @Test("ZSequences keeps the upstream operators in its own importable module")
  func zeroBasedSequenceModuleIsExecutable() throws {
    let sequence = ZeroBasedSequence<Int>.literal(3, 1, 2)
    let rotated = ZSequences.rotation(of: sequence, leftBy: Expr(.int(1)))
    let result = try rotated.raw.evaluate(
      in: [:], recursiveFuncs: ZSequences.module.resolvedRecursiveFuncs
    )
    #expect(result == .function([
      .int(0): .int(1), .int(1): .int(2), .int(2): .int(3)
    ]))

    let corpus = Var<ZeroBasedSequence<Int>>("corpus", .init())
    let consumer = TLASpec("UsesZSequences") {
      Import(ZSequences.module)
      Variable(corpus, ZeroBasedSequence<Int>())
      Invariant("RotationOrdering") {
        ZSequences.lexicographicallyPrecedesOrEquals(
          ZSequences.rotation(of: Expr(corpus.stateExpr), leftBy: Expr(.int(0))),
          ZSequences.rotation(of: Expr(corpus.stateExpr), leftBy: Expr(.int(0)))
        )
      }
    }

    #expect(consumer.tlaModule.contains("EXTENDS Integers, FiniteSets, Sequences, ZSequences"))
    #expect(consumer.tlaBundle.imports.map { $0.name } == ["ZSequences"])
    #expect(consumer.tlaBundle.imports[0].tla.contains("Rotation(sequence, shift) =="))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try consumer.tlaBundle.write(to: directory)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("UsesZSequences.tla").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ZSequences.tla").path))
    let check = try ModelChecker(spec: consumer).check()
    guard case .ok = check.underlyingOutcome else {
      Issue.record("The imported ZSequences operators did not evaluate successfully.")
      return
    }
  }

  @Test("an imported module keeps its source boundary while receiving a typed TLC replacement")
  func importedModuleUsesScopedFiniteReplacement() throws {
    let consumer = TLASpec("BoundedZSequences") {
      Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...2))
    }

    #expect(consumer.tlaModule.contains("ZSequencesNat == 0..2"))
    #expect(consumer.tlaCfg.contains("CONSTANT Nat <- [ZSequences]ZSequencesNat"))
    #expect(consumer.tlaBundle.imports.map(\.name) == ["ZSequences"])
    #expect(!consumer.tlaBundle.root.tla.contains("ZSeq(elements) =="))

    let sequences = try StateExpr.recursiveCall("ZSeq", [
      .setLiteral([.int(0), .int(1)])
    ]).evaluate(in: [:], recursiveFuncs: consumer.resolvedRecursiveFuncs)
    guard case .set(let values) = sequences else {
      Issue.record("The bounded ZSeq result was not a set.")
      return
    }
    #expect(values.count == 7)
  }

  @Test("an import remains a source dependency and resolves its operators at runtime")
  func importedOperatorIsBundledAndExecutable() throws {
    let arithmetic = TLASpec("FormalArithmetic") {
      DefineRecursive("Twice", params: ["value"]) {
        StateExpr.variable("value") * 2
      }
    }
    let value = Var<Int>("value", 1)
    let consumer = TLASpec("UsesFormalArithmetic") {
      Import(arithmetic)
      Variable(value, 1)
      Invariant("TwiceIsTwo") {
        StateExpr.recursiveCall("Twice", [value.stateExpr]) == 2
      }
    }

    #expect(consumer.tlaModule.contains("EXTENDS Integers, FiniteSets, Sequences, FormalArithmetic"))
    #expect(!consumer.tlaModule.contains("Twice(value) =="))
    #expect(consumer.tlaBundle.imports.map { $0.name } == ["FormalArithmetic"])
    #expect(consumer.tlaBundle.imports.first?.tla.contains("Twice(value) ==") == true)
    let check = try ModelChecker(spec: consumer).check()
    guard case .ok = check.underlyingOutcome else {
      Issue.record("The imported operator did not evaluate successfully.")
      return
    }
  }
}
