import SwiftTLA
import SwiftTLAMacros

/// The upstream N-Queens PlusCal algorithm with its published FourQueens scenario.
@TLAModel
package struct NQueensModel: Sendable {
    private enum Step: String, CaseIterable {
        case nextQueen = "nxtQ"
    }

    package static var spec: TLASpec {
        #spec("QueensPluscal") { model in
            Extends(.naturals)
            let N = model.parameter(as: Int.self, in: 1...4)
            Assume(N > 0)
            let TypeInvariant = Invariant()
            let NoSolutions = Invariant()
            let Invariant = Invariant()
            let Termination = Temporal()
            Algorithm("Queens", fairness: .weak, scoped: { scope in
                let todo = scope.sharedVar(initial: Set<[Int]>([Array<Int>([])]))
                let sols = scope.sharedVar(initial: Set<[Int]>([]))

                While(Step.nextQueen, !todo.expr.isEmpty) {
                    With(todo) { queens in
                        Let(queens.expr.count + 1) { nextQueen in
                            Let(
                                IntRange(1, through: N).filtering { column in
                                    !Exists(in: IntRange(1, through: queens.expr.count)) { row in
                                        queens.expr.appending(column.expr).at(row.expr)
                                            == queens.expr.appending(column.expr).at(nextQueen.expr)
                                            || queens.expr.appending(column.expr).at(row.expr)
                                                - queens.expr.appending(column.expr).at(nextQueen.expr)
                                                == row.expr - nextQueen.expr
                                            || queens.expr.appending(column.expr).at(nextQueen.expr)
                                                - queens.expr.appending(column.expr).at(row.expr)
                                                == row.expr - nextQueen.expr
                                    }
                                }
                            ) { columns in
                                Let(columns.expr.mapping { column in
                                    queens.expr.appending(column.expr)
                                }) { extensions in
                                    If(nextQueen.expr == N) {
                                        Assign(todo, to: todo.expr.removing(queens))
                                        Assign(sols, to: sols.expr.union(extensions.expr))
                                    } else: {
                                        Assign(todo, to: todo.expr.removing(queens).union(extensions.expr))
                                    }
                                }
                            }
                        }
                    }
                }

                let validSolutions = Sequences(
                    of: IntRange(1, through: N), lengths: IntRange(N, through: N)
                ).filtering { placement in
                    ForAll(in: IntRange(1, through: N - 1)) { row in
                        ForAll(in: IntRange(row.expr + 1, through: N)) { other in
                            placement.expr[row.expr] != placement.expr[other.expr]
                                && placement.expr[row.expr] - placement.expr[other.expr] != row.expr - other.expr
                                && placement.expr[other.expr] - placement.expr[row.expr] != row.expr - other.expr
                        }
                    }
                }
                Invariant {
                    sols.expr.isSubset(of: validSolutions)
                        && (!todo.expr.isEmpty || validSolutions.isSubset(of: sols.expr))
                }
                NoSolutions { sols.expr.isEmpty }
                Termination(.eventually(Finished()))

                TypeInvariant {
                    ForAll(in: todo.expr) { placement in
                        placement.expr.count < N
                            && ForAll(in: IntRange(1, through: placement.expr.count)) { row in
                                IntRange(1, through: N).contains(placement.expr[row.expr])
                            }
                    }
                    && ForAll(in: sols.expr) { placement in
                        placement.expr.count == N
                            && ForAll(in: IntRange(1, through: placement.expr.count)) { row in
                                IntRange(1, through: N).contains(placement.expr[row.expr])
                            }
                    }
                }
            })
            Validation("FourQueens") { Bind(N, to: 4) }.expect(NoSolutions, .violated)
        }
    }
}
