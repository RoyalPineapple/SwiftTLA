import SwiftTLA
import SwiftTLAMacros

/// The upstream direct-TLA Queens model with its published FourQueens scenario.
@TLAModel
package struct QueensModel: Sendable {
    package enum Step: String, CaseIterable { case PlaceQueen }

    package static var spec: TLASpec {
        #spec("Queens") { scope in
            Extends(.naturals, .sequences)
            let N = scope.parameter(as: Int.self, in: 1...4)
            Assume(N > 0)
            let todo = scope.sharedVar(initial: Set<[Int]>([Array<Int>([])]))
            let sols = scope.sharedVar(initial: Set<[Int]>([]))
            let TypeInvariant = Invariant()
            let NoSolutions = Invariant()
            let Invariant = Invariant()
            let Termination = Temporal()

            Do(Step.PlaceQueen) {
                With(todo) { queens in
                    let nextQueen = queens.count + 1
                    let columns = IntRange(1, through: N).filtering { column in
                        !Exists(in: IntRange(1, through: queens.count)) { row in
                            queens.appending(column).at(row.expr) == queens.appending(column).at(nextQueen)
                                || queens.appending(column).at(row.expr) - queens.appending(column).at(nextQueen)
                                    == row.expr - nextQueen
                                || queens.appending(column).at(nextQueen) - queens.appending(column).at(row.expr)
                                    == row.expr - nextQueen
                        }
                    }
                    let extensions = columns.mapping { column in queens.appending(column) }
                    If(nextQueen == N) {
                        Assign(todo, to: todo.removing(queens))
                        Assign(sols, to: sols.union(extensions))
                    } else: {
                        Assign(todo, to: todo.removing(queens).union(extensions))
                    }
                }
            }
            WeakFairnessNext()

            let solutions = Sequences(of: IntRange(1, through: N), lengths: IntRange(N, through: N))
                .filtering { placement in
                    ForAll(in: IntRange(1, through: N - 1)) { row in
                        ForAll(in: IntRange(row.expr + 1, through: N)) { other in
                            placement[row.expr] != placement[other.expr]
                                && placement[row.expr] - placement[other.expr] != row.expr - other.expr
                                && placement[other.expr] - placement[row.expr] != row.expr - other.expr
                        }
                    }
                }
            TypeInvariant {
                ForAll(in: todo) { placement in
                    placement.count < N && ForAll(in: IntRange(1, through: placement.count)) { row in
                        IntRange(1, through: N).contains(placement[row.expr])
                    }
                } && ForAll(in: sols) { placement in
                    placement.count == N && ForAll(in: IntRange(1, through: placement.count)) { row in
                        IntRange(1, through: N).contains(placement[row.expr])
                    }
                }
            }
            Invariant { sols.isSubset(of: solutions) && (!todo.isEmpty || solutions.isSubset(of: sols)) }
            NoSolutions { sols.isEmpty }
            Termination(.eventually(todo.isEmpty))
            Validation("FourQueens") { Bind(N, to: 4) }
                .checking(only: [TypeInvariant, Invariant, NoSolutions])
                .checkingDeadlock(false)
                .expect(NoSolutions, .violated)
        }
    }
}
