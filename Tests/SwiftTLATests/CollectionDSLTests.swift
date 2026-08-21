import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct TypedSetAlgorithm {
  static var spec: TLASpec {
    #spec("TypedSetAlgorithm") {
      let seen = SharedVar("seen", initial: SetExpr<Int>())
      Action("add") {
        seen.becomes(seen.inserting(1))
      }
      Action("remove") {
        seen.contains(1) && seen.becomes(seen.removing(1))
      }
      Invariant("bounded") {
        seen.isEmpty || seen.contains(1)
      }
    }
  }
}

@TLAModel
private struct TypedTupleAlgorithm {
  static var spec: TLASpec {
    #spec("TypedTupleAlgorithm") {
      let values = SharedVar("values", initial: TupleExpr<Int>())
      Action("append") {
        values.count < 2 && values.becomes(values.appending(1))
      }
      Invariant("bounded") {
        values.count <= 2
      }
    }
  }
}

@TLAModel
private struct TypedFiniteInitialAlgorithm {
  static var spec: TLASpec {
    #spec("TypedFiniteInitialAlgorithm") {
      let phase = SharedVar("phase", in: SetExpr<Int>.literal(1, 2))
      Action("prepare") {
        phase == 1 && phase.becomes(2)
      }
      Invariant("knownPhase") {
        phase == 1 || phase == 2
      }
    }
  }
}

@Suite(.serialized)
struct TypedFormalCollectionTests {
  @Test func typedSetLowersAndChecksThroughBothPaths() throws {
    TypedSetAlgorithm._checkParserTree()
    let result = try ModelChecker(compilation: try TypedSetAlgorithm.spec.compile()).check()
    guard case .ok(let count) = result.underlyingOutcome else {
      Issue.record("Expected successful set proof, got \(result)")
      return
    }
    #expect(count == 2)
    #expect(try TypedSetAlgorithm.spec.compile().renderedTLAModuleBundle().tla.contains("seen' = (seen \\cup {1})"))
  }

  @Test func typedTupleLowersAndChecksThroughBothPaths() throws {
    TypedTupleAlgorithm._checkParserTree()
    let result = try ModelChecker(compilation: try TypedTupleAlgorithm.spec.compile()).check()
    guard case .ok(let count) = result.underlyingOutcome else {
      Issue.record("Expected successful tuple proof, got \(result)")
      return
    }
    #expect(count == 3)
    #expect(try TypedTupleAlgorithm.spec.compile().renderedTLAModuleBundle().tla.contains("values' = Append(values, 1)"))
  }

  @Test func formalValuesRoundTripWithoutHostCollections() {
    let set = SetExpr<Int>(formalValue: .set([.int(1), .int(2)]))
    #expect(set?.elements.count == 2)
    #expect(set?.elements.contains(1) == true)
    #expect(set?.elements.contains(2) == true)

    let tuple = TupleExpr<Int>(formalValue: .tuple([.int(1), .int(2)]))
    #expect(tuple?.elements == [1, 2])
  }

  @Test func typedFiniteInitialDomainChecksThroughBothPaths() throws {
    TypedFiniteInitialAlgorithm._checkParserTree()
    let result = try ModelChecker(compilation: try TypedFiniteInitialAlgorithm.spec.compile()).check()
    guard case .ok(let count) = result.underlyingOutcome else {
      Issue.record("Expected successful finite-domain proof, got \(result)")
      return
    }
    #expect(count == 2)
  }
}
