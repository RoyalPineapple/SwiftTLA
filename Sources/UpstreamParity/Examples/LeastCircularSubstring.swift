import SwiftTLA

/// Kellogg Booth's published least-circular-substring algorithm.
///
/// This is the upstream PlusCal control flow with its labels preserved. The
/// model imports `ZSequences` as a real module, and configures that module's
/// `Nat` operator with the same finite bound used for model checking.
public enum LeastCircularSubstringModel {
    private enum Step: String, PlusCalLabel {
        case l3 = "L3"
        case l5 = "L5"
        case l6 = "L6"
        case l7 = "L7"
        case l8 = "L8"
        case l9 = "L9"
        case l10 = "L10"
        case l11 = "L11"
        case l12 = "L12"
        case l13 = "L13"
        case l14 = "L14"
        case loopReturn = "LVR"
    }

    private static func character(
        in sequence: SharedVariable<ZeroBasedSequence<Int>>,
        length: SharedVariable<Int>,
        at index: StateExpr
    ) -> StateExpr {
        .functionApply(sequence.stateExpr, .modulo(index, length.stateExpr))
    }

    private static func failure(
        in table: SharedVariable<TLAValue>,
        at index: StateExpr
    ) -> StateExpr {
        .functionApply(table.stateExpr, index)
    }

    private static func mismatch(
        sequence: SharedVariable<ZeroBasedSequence<Int>>,
        length: SharedVariable<Int>,
        offset: SharedVariable<Int>,
        prefix: SharedVariable<Int>,
        position: SharedVariable<Int>
    ) -> StateExpr {
        .notEqual(
            character(in: sequence, length: length, at: position.stateExpr),
            character(
                in: sequence,
                length: length,
                at: .add(.add(offset.stateExpr, prefix.stateExpr), .int(1))
            )
        )
    }

    private static func correctness(
        sequence: SharedVariable<ZeroBasedSequence<Int>>,
        shift: SharedVariable<Int>
    ) -> StateExpr {
        let candidate = ZSequences.rotation(of: sequence.expr, leftBy: shift.expr)
        return .or(
            .not(Finished()),
            All(in: ZSequences.rotations(of: sequence.expr)) { other in
                let otherSequence = Expr<ZeroBasedSequence<Int>>(
                    .recordAccess(other.stateExpr, "seq")
                )
                let otherShift = Expr<Int>(.recordAccess(other.stateExpr, "shift"))
                return StateExpr.and(
                    ZSequences.lexicographicallyPrecedesOrEquals(candidate, otherSequence),
                    StateExpr.or(
                        .notEqual(candidate.raw, otherSequence.raw),
                        .lessOrEqual(shift.stateExpr, otherShift.raw)
                    )
                )
            }
        )
    }

    public static let spec = TLASpec("MCLeastCircularSubstring") {
        Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(0...6))

        Algorithm("LeastCircularSubstring") {
            let characterSet = SetExpr<Int>.literal(0, 1)
            let b = SharedVar(
                "b",
                in: ZSequences.sequences(over: characterSet)
            )
            b
            let n = SharedVar("n", initial: ZSequences.length(of: b.expr))
            n
            let f = SharedVar(
                "f",
                initial: Expr<TLAValue>(.functionLiteral(
                    .integerRange(.int(0), .multiply(.int(2), n.stateExpr)),
                    "index",
                    .int(-1)
                ))
            )
            f
            let i = SharedVar("i", initial: -1)
            i
            let j = SharedVar("j", initial: 1)
            j
            let k = SharedVar("k", initial: 0)
            k

            Do(Step.l3) {
                If(j < n * 2) {
                    Goto(Step.l5)
                } else: {
                    Stop()
                }
            }
            Do(Step.l5) {
                Assign(i, to: failure(in: f, at: .subtract(.subtract(j.stateExpr, k.stateExpr), .int(1))))
            }
            Do(Step.l6) {
                If(mismatch(sequence: b, length: n, offset: k, prefix: i, position: j) && i != -1) {
                    Goto(Step.l7)
                } else: {
                    Goto(Step.l10)
                }
            }
            Do(Step.l7) {
                If(
                    character(in: b, length: n, at: j.stateExpr) <
                        character(in: b, length: n, at: .add(.add(k.stateExpr, i.stateExpr), .int(1)))
                ) {
                    Goto(Step.l8)
                } else: {
                    Goto(Step.l9)
                }
            }
            Do(Step.l8) {
                Assign(k, to: j - i - 1)
            }
            Do(Step.l9) {
                Assign(i, to: failure(in: f, at: i.stateExpr))
                Goto(Step.l6)
            }
            Do(Step.l10) {
                If(mismatch(sequence: b, length: n, offset: k, prefix: i, position: j) && i == -1) {
                    Goto(Step.l11)
                } else: {
                    Goto(Step.l14)
                }
            }
            Do(Step.l11) {
                If(
                    character(in: b, length: n, at: j.stateExpr) <
                        character(in: b, length: n, at: .add(.add(k.stateExpr, i.stateExpr), .int(1)))
                ) {
                    Goto(Step.l12)
                } else: {
                    Goto(Step.l13)
                }
            }
            Do(Step.l12) {
                Assign(k, to: j.expr)
            }
            Do(Step.l13) {
                Assign(f, to: Expr<TLAValue>(.except(
                    f.stateExpr,
                    .subtract(j.stateExpr, k.stateExpr),
                    .int(-1)
                )))
                Goto(Step.loopReturn)
            }
            Do(Step.l14) {
                Assign(f, to: Expr<TLAValue>(.except(
                    f.stateExpr,
                    .subtract(j.stateExpr, k.stateExpr),
                    .add(i.stateExpr, .int(1))
                )))
            }
            Do(Step.loopReturn) {
                Assign(j, to: j + 1)
                Goto(Step.l3)
            }

            Invariant("TypeInvariant") {
                let indexRange = StateExpr.integerRange(.int(0), .multiply(.int(2), n.stateExpr))
                return .and(
                    .in(b.stateExpr, ZSequences.sequences(over: characterSet).raw),
                    .and(
                        .equal(n.stateExpr, ZSequences.length(of: b.expr).raw),
                        .and(
                            .in(f.stateExpr, .functionSet(indexRange, .union(indexRange, .setLiteral([.int(-1)])))),
                            .and(
                                .in(i.stateExpr, .union(indexRange, .setLiteral([.int(-1)]))),
                                .and(
                                    .in(j.stateExpr, .union(indexRange, .setLiteral([.int(1)]))),
                                    .in(k.stateExpr, .union(ZSequences.indices(of: b.expr).raw, .setLiteral([.int(0)])))
                                )
                            )
                        )
                    )
                )
            }
            Invariant("Correctness") {
                correctness(sequence: b, shift: k)
            }
        }
    }
}

extension Example {
    public static let leastCircularSubstring = Entry(
        id: "LeastCircularSubstring/MCLeastCircularSubstringSmall",
        upstreamSpec: "LeastCircularSubstring",
        upstreamModule: "specifications/LeastCircularSubstring/LeastCircularSubstring.tla",
        upstreamCfg: "specifications/LeastCircularSubstring/MCLeastCircularSubstringSmall.cfg",
        expectedDistinct: 8_554,
        verificationStateLimit: 10_000,
        spec: LeastCircularSubstringModel.spec,
        notes: "Published Kellogg Booth least-circular-substring model with CharSetSize = 2 and MaxStringLength = 6."
    )
}
