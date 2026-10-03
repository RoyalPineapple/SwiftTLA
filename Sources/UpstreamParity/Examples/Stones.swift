import SwiftTLA
import SwiftTLAMacros

/// The published stone-scale puzzle, evaluated as a configured assumption.
@TLAModel
package struct StonesModel: Sendable {
    package static var spec: TLASpec {
        #spec("Stones") { scope in
            Extends(.integers, .sequences, .finiteSets, .tlc)
            let W = scope.parameter(as: Int.self, in: Int.all)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(W >= 0 && N >= 1 && N <= W &&
                LetRec("SeqSum", taking: [Int].self,
                    { (seqSum: LocalRecursion<[Int], Int>, sequence: WithValue<[Int]>) in
                        If(sequence.count == 0, then: 0,
                            else: sequence.head() + seqSum(sequence.tail()))
                    }, in: { seqSum in
                        LetRec("Partitions", taking: Pair<[Int], Int>.self,
                            { (partitions: LocalRecursion<Pair<[Int], Int>, SetExpr<[Int]>>,
                               input: WithValue<Pair<[Int], Int>>) in
                                If(input.first().count == N,
                                   then: SetExpr<[Int]>.literal(input.first()),
                                   else: IntRange(1, through: If(input.first().count == 0,
                                       then: input.second(), else: input.first().head()))
                                       .filtering { x in
                                           N - input.first().count - 1 <= input.second() - x.expr
                                               && input.second() <= x.expr * (N - input.first().count)
                                       }
                                       .flatMapping { x in
                                           partitions(Pair.literal(
                                               input.first().prepending(x.expr),
                                               input.second() - x.expr))
                                       })
                            }, in: { partitions in
                                Exists(in: partitions(Pair.literal(Array<Int>(), W))) { partition in
                                    If(ForAll(in: IntRange(1, through: W)) { weight in
                                        Exists(in: Functions(from: IntRange(1, through: N),
                                                             to: IntRange(-1, through: 1))) { coefficients in
                                            seqSum(SequenceMapping(length: N) { index in
                                                coefficients[index.expr] * partition[index.expr]
                                            }) == weight.expr
                                        }
                                    }, then: PrintT(partition), else: false)
                                } || PrintT("No solution")
                            })
                    }))
            let Stones = Validation {
                Bind(W, to: 40)
                Bind(N, to: 4)
            }.checkingDeadlock(false)
            Stones
        }
    }
}
