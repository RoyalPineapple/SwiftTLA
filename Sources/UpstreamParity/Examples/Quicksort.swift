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
            let PCorrect = Invariant()
            let TypeOK = Invariant()
            let Inv = Invariant()
            let Termination = Temporal()
            Algorithm("Quicksort", fairness: .weak, scoped: { scope in
                let seq = scope.sharedVar(in: Sequences(
                    of: Values, lengths: IntRange(1, through: MaxSeqLen)))
                let seq0 = scope.sharedVar(initial: seq)
                let U = scope.sharedVar(initial:
                    Set<Set<Int>>([]).inserting(IntRange(1, through: seq.count)))

                While(Step.a, !U.isEmpty) {
                    With(U) { I in
                        If(I.cardinality == 1) {
                            Assign(U, to: U.removing(I))
                        } else: {
                            Let(Select(from: I) { x in ForAll(in: I) { y in x <= y } }) { minimum in
                                Let(Select(from: I) { x in ForAll(in: I) { y in x >= y } }) { maximum in
                                    With(IntRange(minimum, through: maximum - 1)) { p in
                                        With(Sequences(of: Values,
                                            lengths: IntRange(seq.count, through: seq.count)).filtering { t in
                                            ForAll(in: Values) { value in
                                                IntRange(1, through: seq.count).filtering { i in
                                                    t.expr[i] == value
                                                }.cardinality == IntRange(1, through: seq.count).filtering { i in
                                                    seq[i] == value
                                                }.cardinality
                                            }
                                            && ForAll(in: IntRange(1, through: seq.count).subtracting(I)) { i in
                                                t.expr[i] == seq[i]
                                            }
                                            && ForAll(in: I) { i in
                                                Exists(in: I) { j in t.expr[i] == seq[j] }
                                            }
                                            && ForAll(in: I) { i in
                                                ForAll(in: I) { j in
                                                    i > p || p >= j || t.expr[i] <= t.expr[j]
                                                }
                                            }
                                        }) { newseq in
                                            Assign(seq, to: newseq)
                                            Assign(U, to: U.removing(I)
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
                    && ForAll(in: IntRange(1, through: seq.count)) { i in Values.contains(seq[i]) }
                    && ForAll(in: IntRange(1, through: seq0.count)) { i in Values.contains(seq0[i]) }
                    && ForAll(in: U) { I in
                        !I.isEmpty && I.isSubset(of: IntRange(1, through: seq0.count))
                    }
                let permutation = seq.count == seq0.count && ForAll(in: IntRange(1, through: seq0.count)) { original in
                    IntRange(1, through: seq.count).filtering { i in seq[i] == seq0[original] }.cardinality
                        == IntRange(1, through: seq0.count).filtering { i in seq0[i] == seq0[original] }.cardinality
                }
                let UV = U.union(IntRange(1, through: seq.count)
                    .subtracting(U.flatMapping { I in I.expr })
                    .mapping { i in Set<Int>([]).inserting(i) })
                TypeOK { typeOK }
                PCorrect {
                    !Finished() || (permutation && ForAll(in: IntRange(1, through: seq.count)) { p in
                        ForAll(in: IntRange(p + 1, through: seq.count)) { q in seq[p] <= seq[q] }
                    })
                }
                Inv {
                    typeOK
                    !Finished() || U.isEmpty
                    permutation
                    UV.flatMapping { I in I.expr } == IntRange(1, through: seq0.count)
                    ForAll(in: UV) { I in
                        Exists(in: IntRange(1, through: seq0.count)) { minimum in
                            Exists(in: IntRange(1, through: seq0.count)) { maximum in
                                I == IntRange(minimum, through: maximum)
                            }
                        }
                        && ForAll(in: UV) { J in
                            I == J || (I.intersection(J).isEmpty && ForAll(in: I) { i in
                                ForAll(in: J) { j in i >= j || seq[i] <= seq[j] }
                            })
                        }
                    }
                }
                Termination(.eventually(Finished()))
            })
            Validation("MCQuicksort") {
                Bind(Values, to: Set<Int>([1, 2, 3]))
                Bind(MaxSeqLen, to: 4)
            }
        }
    }
}
