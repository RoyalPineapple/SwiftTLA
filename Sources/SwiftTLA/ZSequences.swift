/// A typed port of the upstream `ZSequences` TLA+ module.
///
/// The module defines operations on finite sequences whose indexes begin at
/// zero. Import `ZSequences.module` into a model before using these calls.
/// The generated bundle emits `ZSequences.tla` as a separate dependency.
public enum ZSequences {
  /// The formal module exported as `ZSequences.tla`.
  ///
  /// `ZSeq` follows the upstream definition and ranges over `Nat`. A model
  /// checker therefore supplies a finite replacement for that operator in the
  /// consuming model's TLC configuration.
  public static let module = TLASpec("ZSequences") {
    DefineRecursive("ZIndices", params: ["sequence"]) {
      let sequence = StateExpr.variable("sequence")
      return .ifThenElse(
        .equal(sequence, .tupleLiteral([])),
        .setLiteral([]),
        .domain(sequence)
      )
    }

    DefineRecursive("ZSeqOfLength", params: ["elements", "length"]) {
      let elements = StateExpr.variable("elements")
      let length = StateExpr.variable("length")
      return .ifThenElse(
        .equal(length, .int(0)),
        .setLiteral([.tupleLiteral([])]),
        .functionSet(.integerRange(.int(0), .subtract(length, .int(1))), elements)
      )
    }

    DefineRecursive("ZSeq", params: ["elements"]) {
      let elements = StateExpr.variable("elements")
      let length = "__zSequencesLength"
      return .unionAll(.setMap(
        .recursiveCall("ZSeqOfLength", [elements, .variable(length)]),
        length,
        .variable("Nat")
      ))
    }

    DefineRecursive("ZLen", params: ["sequence"]) {
      let sequence = StateExpr.variable("sequence")
      return .ifThenElse(
        .equal(sequence, .tupleLiteral([])),
        .int(0),
        .cardinality(.domain(sequence))
      )
    }

    DefineRecursive("ZSeqFromSeq", params: ["sequence"]) {
      let sequence = StateExpr.variable("sequence")
      let index = "__zSequencesIndex"
      return .ifThenElse(
        .equal(sequence, .tupleLiteral([])),
        .tupleLiteral([]),
        .functionLiteral(
          .integerRange(.int(0), .subtract(.tupleLength(sequence), .int(1))),
          index,
          .tupleDynamicAccess(sequence, .add(.variable(index), .int(1)))
        )
      )
    }

    DefineRecursive("SeqFromZSeq", params: ["sequence"]) {
      let sequence = StateExpr.variable("sequence")
      let index = "__zSequencesIndex"
      return .ifThenElse(
        .equal(sequence, .tupleLiteral([])),
        .tupleLiteral([]),
        .functionLiteral(
          .integerRange(.int(1), .recursiveCall("ZLen", [sequence])),
          index,
          .functionApply(sequence, .subtract(.variable(index), .int(1)))
        )
      )
    }

    DefineRecursive("IsLexLeq", params: ["left", "right", "index"]) {
      let left = StateExpr.variable("left")
      let right = StateExpr.variable("right")
      let index = StateExpr.variable("index")
      return .caseExpr([
        .or(
          .equal(index, .recursiveCall("ZLen", [left])),
          .equal(index, .recursiveCall("ZLen", [right]))
        ),
        .lessOrEqual(
          .recursiveCall("ZLen", [left]),
          .recursiveCall("ZLen", [right])
        ),
        .lessThan(.functionApply(left, index), .functionApply(right, index)), .bool(true),
        .greaterThan(.functionApply(left, index), .functionApply(right, index)), .bool(false)
      ], .recursiveCall("IsLexLeq", [left, right, .add(index, .int(1))]))
    }

    DefineRecursive("LexicographicallyPrecedesOrEquals", params: ["left", "right"]) {
      .recursiveCall("IsLexLeq", [
        .variable("left"), .variable("right"), .int(0)
      ])
    }

    DefineRecursive("Rotation", params: ["sequence", "shift"]) {
      let sequence = StateExpr.variable("sequence")
      let shift = StateExpr.variable("shift")
      let index = "__zSequencesIndex"
      return .ifThenElse(
        .equal(sequence, .tupleLiteral([])),
        .tupleLiteral([]),
        .functionLiteral(
          .recursiveCall("ZIndices", [sequence]),
          index,
          .functionApply(
            sequence,
            .modulo(
              .add(.variable(index), shift),
              .recursiveCall("ZLen", [sequence])
            )
          )
        )
      )
    }

    DefineRecursive("Rotations", params: ["sequence"]) {
      let sequence = StateExpr.variable("sequence")
      let shift = "__zSequencesShift"
      return .ifThenElse(
        .equal(sequence, .tupleLiteral([])),
        .setLiteral([]),
        .setMap(
          .recordLiteral([
            "shift": .variable(shift),
            "seq": .recursiveCall("Rotation", [sequence, .variable(shift)])
          ]),
          shift,
          .recursiveCall("ZIndices", [sequence])
        )
      )
    }
  }

  public static func indices<Element: TLAValueType>(
    of sequence: Expr<ZeroBasedSequence<Element>>
  ) -> Expr<SetExpr<Int>> {
    Expr(.recursiveCall("ZIndices", [sequence.raw]))
  }

  /// The bounded set of zero-indexed sequences over `elements`.
  ///
  /// `Import(ZSequences.module, configuring: ...)` supplies the finite `Nat`
  /// domain used by the upstream `ZSeq` definition.
  public static func sequences<Element: TLAValueType>(
    over elements: Expr<SetExpr<Element>>
  ) -> Expr<SetExpr<ZeroBasedSequence<Element>>> {
    Expr(.recursiveCall("ZSeq", [elements.raw]))
  }

  public static func length<Element: TLAValueType>(
    of sequence: Expr<ZeroBasedSequence<Element>>
  ) -> Expr<Int> {
    Expr(.recursiveCall("ZLen", [sequence.raw]))
  }

  public static func rotation<Element: TLAValueType>(
    of sequence: Expr<ZeroBasedSequence<Element>>,
    leftBy shift: Expr<Int>
  ) -> Expr<ZeroBasedSequence<Element>> {
    Expr(.recursiveCall("Rotation", [sequence.raw, shift.raw]))
  }

  /// Every left rotation of a zero-indexed sequence, as the upstream record
  /// set `{ [shift |-> r, seq |-> Rotation(s, r)] : r \in ZIndices(s) }`.
  public static func rotations<Element: TLAValueType>(
    of sequence: Expr<ZeroBasedSequence<Element>>
  ) -> Expr<SetExpr<TLAValue>> {
    Expr(.recursiveCall("Rotations", [sequence.raw]))
  }

  public static func lexicographicallyPrecedesOrEquals(
    _ left: Expr<ZeroBasedSequence<Int>>,
    _ right: Expr<ZeroBasedSequence<Int>>
  ) -> StateExpr {
    .recursiveCall("LexicographicallyPrecedesOrEquals", [left.raw, right.raw])
  }

  /// Gives the imported module's `Nat` operator a finite TLC model domain.
  public static func boundedNaturalNumbers(
    _ range: ClosedRange<Int>
  ) -> FormalModuleConfiguration {
    FormalModuleConfiguration(
      moduleName: module.name,
      replacements: [
        FormalModuleReplacement(
          operatorName: "Nat",
          definitionName: "ZSequencesNat",
          expression: .integerRange(.int(range.lowerBound), .int(range.upperBound))
        )
      ]
    )
  }
}
