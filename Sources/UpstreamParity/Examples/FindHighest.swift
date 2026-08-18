import SwiftTLA
import SwiftTLAMacros

/// The bounded `FindHighest` PlusCal algorithm from the LearnProofs corpus.
///
/// The published model replaces `Nat` with `0...4` and `Seq(Nat)` with
/// sequences of length at most three. `Sequences(of:lengths:)` states those
/// bounds directly in SwiftTLA instead of hiding them in host-language data.
@TLAModel
public struct FindHighestModel: Sendable {
    private enum Step: String, PlusCalLabel {
        case lb
    }

    public static var spec: TLASpec {
        #spec("Highest") {
            Extends("Integers")
            Algorithm("Highest") {
                let f = SharedVar(in: Sequences(
                    of: SetExpr<Int>.literal(0, 1, 2, 3, 4),
                    lengths: 0...3
                ))
                let h = SharedVar(initial: -1)
                let i = SharedVar(initial: 1)

                While(Step.lb, i <= f.count) {
                    Assign(h, to: If(h >= f[i], then: h.expr, else: f[i]))
                    Assign(i, to: i + 1)
                }

                Invariant("TypeOK") {
                    i >= 1 && i <= f.count + 1
                    h >= -1
                }
                Invariant("InductiveInvariant") {
                    All(in: IntRange(1, through: i - 1)) { index in
                        f[index.expr] <= h
                    }
                }
                Invariant("DoneIndexValue") {
                    (!Finished()) || i == f.count + 1
                }
                Invariant("Correctness") {
                    (!Finished()) || All(in: IntRange(1, through: f.count)) { index in
                        f[index.expr] <= h
                    }
                }
            }
        }
    }
}

extension Example {
    public static let findHighest = Entry(
        id: "LearnProofs/FindHighest",
        upstreamSpec: "LearnProofs",
        upstreamModule: "specifications/LearnProofs/FindHighest.tla",
        upstreamCfg: "specifications/LearnProofs/MCFindHighest.cfg",
        expectedDistinct: 742,
        spec: FindHighestModel.spec,
        notes: "Published FindHighest with MaxLength = 3 and MaxNat = 4."
    )
}
