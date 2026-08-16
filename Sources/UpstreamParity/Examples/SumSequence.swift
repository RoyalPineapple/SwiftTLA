import SwiftTLA
import SwiftTLAMacros

/// A bounded port of the upstream `SumSequence` PlusCal algorithm.
///
/// The published algorithm accepts sequences over an arbitrary integer set.
/// This finite model uses `-1...1` and sequences up to length three, while
/// preserving the algorithm's state and one-element-at-a-time loop.
@TLAModel
public struct SumSequenceModel {
    private enum Step: String, PlusCalLabel {
        case a
    }

    public static var spec: TLASpec {
        #spec("SumSequence") {
            Extends("Integers")
            Algorithm("SumSequence") {
                let sequence = SharedVar(in: Sequences(
                    of: SetExpr<Int>.literal(-1, 0, 1),
                    lengths: 0...3
                ))
                let sum = SharedVar(initial: 0)
                let index = SharedVar(initial: 1)

                While(Step.a, index <= sequence.count) {
                    Assign(sum, to: sum + sequence[index])
                    Assign(index, to: index + 1)
                }

                Invariant("TypeOK") {
                    index >= 1 && index <= sequence.count + 1
                    sum >= -3 && sum <= 3
                }
                Invariant("DoneIndex") {
                    !Finished() || index == sequence.count + 1
                }
                WeakFairness("Next")
                Eventually("Termination", Finished())
            }
        }
    }
}

extension Example {
    /// This source model has no published TLC configuration. The expected
    /// state count is pinned by the local finite bounds above, not claimed as
    /// upstream TLC parity.
    public static let sumSequence = Entry(
        id: "LoopInvariance/SumSequence",
        upstreamSpec: "LoopInvariance",
        upstreamModule: "specifications/LoopInvariance/SumSequence.tla",
        upstreamCfg: nil,
        expectedDistinct: 182,
        spec: SumSequenceModel.spec,
        notes: "Bounded source port: values -1...1 and sequence length at most three. No published TLC model configuration."
    )
}
