import Testing
import Foundation
@testable import SwiftTLA

@Suite("TLA+ module bundles")
struct TLAModuleBundleTests {
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
