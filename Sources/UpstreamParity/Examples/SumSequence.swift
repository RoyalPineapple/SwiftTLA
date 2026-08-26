import SwiftTLA
import SwiftTLAMacros

/// A bounded port of the upstream `SumSequence` PlusCal algorithm.
///
/// The published algorithm accepts sequences over an arbitrary integer set.
/// This finite model uses `-1...1` and sequences up to length three, while
/// preserving the algorithm's state and one-element-at-a-time loop.
package struct SumSequenceModel: Sendable {
    private enum Step: String, CaseIterable {
        case a
    }

    package static var spec: TLASpec {
        #spec("SumSequence") {
            Extends(.integers)
            Algorithm("SumSequence", fairness: .weak, scoped: { scope in
                let sequence = scope.sharedVar("sequence", in: Sequences(
                    of: SetExpr<Int>.literal(-1, 0, 1),
                    lengths: 0...3
                ))
                let sum = scope.sharedVar("sum", initial: 0)
                let index = scope.sharedVar("index", initial: 1)

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
                Eventually("EventuallyFinished", Finished())
            })
        }
    }
}

extension Example {
    /// This source model has no published TLC configuration. The expected
    /// state count is pinned by the local finite bounds above, not claimed as
    /// upstream TLC parity.
    package static let sumSequence = Entry(
        id: "LoopInvariance/SumSequence",
        upstreamSpec: "LoopInvariance",
        upstreamModule: "specifications/LoopInvariance/SumSequence.tla",
        upstreamCfg: nil,
        expectedDistinct: 182,
        maximumStateLimit: 50_000,
        spec: SumSequenceModel.spec,
        notes: "Bounded source port: values -1...1 and sequence length at most three. No published TLC model configuration."
    )
}
