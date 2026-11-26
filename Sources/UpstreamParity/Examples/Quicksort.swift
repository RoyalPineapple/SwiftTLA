// The algorithm partitions a sequence and sorts its subranges.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/LoopInvariance/Quicksort.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct QuicksortModel: Sendable {
    private enum Step: String, CaseIterable { case a }

    package static var spec: TLASpec {
        #spec("Quicksort") { model in
            Extends(.integers)
            let Values = model.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([1, 2, 3])]))
            let MaxSeqLen = model.parameter(as: Int.self, in: 4...4)
            let Termination = Temporal()
            let Quicksort = Algorithm(fairness: .weak) { scope in
                let seq = scope.sharedVar(initiallyIn: Sequences(
                    of: Values, lengths: IntRange(1, through: MaxSeqLen)))
                let seq0 = scope.sharedVar(initial: seq)
                let U = scope.sharedVar(initial:
                    Set<Set<Int>>([]).inserting(IntRange(1, through: seq.count)))

                While(Step.a, !U.isEmpty) {
                    With(U) { I in
                        If(I.count == 1) {
                            U.remove(I)
                        } else: {
                            Let(Select(from: I) { x in I.allSatisfy { y in x <= y } }) { minimum in
                                Let(Select(from: I) { x in I.allSatisfy { y in x >= y } }) { maximum in
                                    With(IntRange(minimum, through: maximum - 1)) { p in
                                        With(Sequences(of: Values,
                                            lengths: IntRange(seq.count, through: seq.count)).filter { t in
                                            Values.allSatisfy { value in
                                                IntRange(1, through: seq.count).filter { i in
                                                    t.expr[i] == value
                                                }.count == IntRange(1, through: seq.count).filter { i in
                                                    seq[i] == value
                                                }.count
                                            }
                                            && IntRange(1, through: seq.count).subtracting(I).allSatisfy { i in
                                                t.expr[i] == seq[i]
                                            }
                                            && I.allSatisfy { i in
                                                I.contains { j in t.expr[i] == seq[j] }
                                            }
                                            && I.allSatisfy { i in
                                                I.allSatisfy { j in
                                                    i > p || p >= j || t.expr[i] <= t.expr[j]
                                                }
                                            }
                                        }) { newseq in
                                            seq.set(newseq)
                                            U.set(U.removing(I)
                                                .inserting(IntRange(minimum, through: p))
                                                .inserting(IntRange(p + 1, through: maximum)))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                let typeOK = seq.count >= 1 && seq.count <= MaxSeqLen
                    && seq0.count >= 1 && seq0.count <= MaxSeqLen
                    && IntRange(1, through: seq.count).allSatisfy { i in Values.contains(seq[i]) }
                    && IntRange(1, through: seq0.count).allSatisfy { i in Values.contains(seq0[i]) }
                    && U.allSatisfy { I in
                        !I.isEmpty && I.isSubset(of: IntRange(1, through: seq0.count))
                    }
                let permutation = seq.count == seq0.count && IntRange(1, through: seq0.count).allSatisfy { original in
                    IntRange(1, through: seq.count).filter { i in seq[i] == seq0[original] }.count
                        == IntRange(1, through: seq0.count).filter { i in seq0[i] == seq0[original] }.count
                }
                let UV = U.union(IntRange(1, through: seq.count)
                    .subtracting(U.flatMapping { I in I.expr })
                    .mapping { i in Set<Int>([]).inserting(i) })
                Invariant("TypeOK") { typeOK }
                Invariant("PCorrect") {
                    !Finished() || (permutation && IntRange(1, through: seq.count).allSatisfy { p in
                        IntRange(p + 1, through: seq.count).allSatisfy { q in seq[p] <= seq[q] }
                    })
                }
                Invariant("Inv") {
                    typeOK
                    !Finished() || U.isEmpty
                    permutation
                    UV.flatMapping { I in I.expr } == IntRange(1, through: seq0.count)
                    UV.allSatisfy { I in
                        IntRange(1, through: seq0.count).contains { minimum in
                            IntRange(1, through: seq0.count).contains { maximum in
                                I == IntRange(minimum, through: maximum)
                            }
                        }
                        && UV.allSatisfy { J in
                            I == J || (I.intersection(J).isEmpty && I.allSatisfy { i in
                                J.allSatisfy { j in i >= j || seq[i] <= seq[j] }
                            })
                        }
                    }
                }
                Termination(.eventually(Finished()))
            }
            Quicksort
            Validation("MCQuicksort") {
                Bind(Values, to: Set<Int>([1, 2, 3]))
                Bind(MaxSeqLen, to: 4)
            }
        }
    }
}
