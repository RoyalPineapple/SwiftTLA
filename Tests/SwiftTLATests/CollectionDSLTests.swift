import Testing
import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct TypedSetAlgorithm {
  static var spec: TLASpec {
    #spec("TypedSetAlgorithm") {
      let seen = SharedVar(initial: SetExpr<Int>())
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
      let values = SharedVar(initial: TupleExpr<Int>())
      Action("append") {
        values.count < 2 && values.becomes(values.appending(1))
      }
      Invariant("bounded") {
        values.count <= 2
      }
    }
  }
}

@Suite(.serialized)
struct TypedFormalCollectionTests {
  @Test func typedSetLowersAndChecksThroughBothPaths() throws {
    TypedSetAlgorithm._checkParserTree()
    let result = try ModelChecker(spec: TypedSetAlgorithm.spec).check()
    guard case .ok(let count) = result.underlyingOutcome else {
      Issue.record("Expected successful set proof, got \(result)")
      return
    }
    #expect(count == 2)
    #expect(TypedSetAlgorithm.spec.tlaModule.contains("seen' = (seen \\cup {1})"))
  }

  @Test func typedTupleLowersAndChecksThroughBothPaths() throws {
    TypedTupleAlgorithm._checkParserTree()
    let result = try ModelChecker(spec: TypedTupleAlgorithm.spec).check()
    guard case .ok(let count) = result.underlyingOutcome else {
      Issue.record("Expected successful tuple proof, got \(result)")
      return
    }
    #expect(count == 3)
    #expect(TypedTupleAlgorithm.spec.tlaModule.contains("values' = Append(values, 1)"))
  }

  @Test func formalValuesRoundTripWithoutHostCollections() {
    let set = SetExpr<Int>(formalValue: .set([.int(1), .int(2)]))
    #expect(set?.elements == [1, 2])

    let tuple = TupleExpr<Int>(formalValue: .tuple([.int(1), .int(2)]))
    #expect(tuple?.elements == [1, 2])
  }
}
