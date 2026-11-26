// A loop accumulates the sum of a sequence and relates the partial sum to the elements already
// visited.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/LoopInvariance/SumSequence.tla

import SwiftTLA
import SwiftTLAMacros

/// The upstream proof example's unbounded sequence-summing algorithm.
@TLAModel
package struct SumSequenceModel: Sendable {
    private enum Step: String, CaseIterable {
        case a
    }

    package static var spec: TLASpec {
        #spec("SumSequence") { model in
            Extends(.integers)
            let Values = model.parameter(as: Set<Int>.self, in: Subsets(of: Int.all))
            let Termination = Eventually()
            let SumSequence = Algorithm(fairness: .weak) { scope in
                let seq = scope.sharedVar(initiallyIn: Sequences(of: Values))
                let sum = scope.sharedVar(initial: 0)
                let n = scope.sharedVar(initial: 1)

                While(Step.a, n <= seq.count) {
                    sum += seq[n]
                    n += 1
                }

                let sums = LetRec("SeqSum", over: Sequences(of: Int.all), taking: [Int].self,
                    { recursion, current in
                        If(current.isEmpty, then: 0,
                            else: current.head() + recursion(current.tail()))
                    }, in: { recursion in
                        Pair.literal(
                            recursion(seq.prefix(length: n - 1)),
                            recursion(seq.expr)
                        )
                    })
                let typeOK = Sequences(of: Values).contains(seq)
                    && Int.all.contains(sum)
                    && n >= 1 && n <= seq.count + 1
                Invariant("TypeOK") {
                    typeOK
                }
                Invariant("Inv") {
                    typeOK
                    sum == sums.first()
                    !Finished() || n == seq.count + 1
                }
                Invariant("PCorrect") {
                    !Finished() || sum == sums.second()
                }
                Termination(Finished())
            }
            SumSequence
        }
    }
}
