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
            Algorithm("SumSequence", fairness: .weak, scoped: { scope in
                let seq = scope.sharedVar(in: Sequences(of: Values))
                let sum = scope.sharedVar(initial: 0)
                let n = scope.sharedVar(initial: 1)

                While(Step.a, n <= seq.count) {
                    Assign(sum, to: sum + seq[n])
                    Assign(n, to: n + 1)
                }

                let sums = LetRec("SeqSum", over: Sequences(of: Int.all), taking: [Int].self,
                    { recursion, current in
                        If(current.count == 0, then: 0,
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
                Eventually("Termination", Finished())
            })
        }
    }
}
