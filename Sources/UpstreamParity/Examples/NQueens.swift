import SwiftTLA
import SwiftTLAMacros

/// The upstream N-Queens PlusCal algorithm, specialized to the published
/// FourQueens TLC model. A tuple is one partial board: its index is the row
/// and its value is the chosen column.
@TLAModel
package struct NQueensModel: Sendable {
    private enum Step: String, CaseIterable {
        case nextQueen = "nxtQ"
    }

    package static var spec: TLASpec {
        #spec("QueensPluscal") {
            Extends(.naturals)
            Algorithm("Queens", fairness: .weak, scoped: { scope in
                let todo = scope.sharedVar("todo", initial: SetExpr<TupleExpr<Int>>.literal(TupleExpr<Int>()))
                let solutions = scope.sharedVar("sols", initial: SetExpr<TupleExpr<Int>>())

                While(Step.nextQueen, !todo.expr.isEmpty) {
                    With(todo) { queens in
                        Let(queens.expr.count + 1) { nextQueen in
                            Let(
                                IntRange(1, through: 4).filtering { column in
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
                                    If(nextQueen.expr == 4) {
                                        Assign(todo, to: todo.expr.removing(queens))
                                        Assign(solutions, to: solutions.expr.union(extensions.expr))
                                    } else: {
                                        Assign(todo, to: todo.expr.removing(queens).union(extensions.expr))
                                    }
                                }
                            }
                        }
                    }
                }

                let validSolutions = Sequences(
                    of: SetExpr<Int>.literal(1, 2, 3, 4), lengths: 4...4
                ).filtering { placement in
                    ForAll(in: IntRange(1, through: 3)) { row in
                        ForAll(in: IntRange(row.expr + 1, through: 4)) { other in
                            placement.expr[row.expr] != placement.expr[other.expr]
                                && placement.expr[row.expr] - placement.expr[other.expr] != row.expr - other.expr
                                && placement.expr[other.expr] - placement.expr[row.expr] != row.expr - other.expr
                        }
                    }
                }
                Invariant("Invariant") {
                    solutions.expr.isSubset(of: validSolutions)
                        && (!todo.expr.isEmpty || validSolutions.isSubset(of: solutions.expr))
                }
                Eventually("Termination", Finished())

                Invariant("TypeInvariant") {
                    ForAll(in: todo.expr) { placement in
                        placement.expr.count < 4
                            && ForAll(in: IntRange(1, through: placement.expr.count)) { row in
                                IntRange(1, through: 4).contains(placement.expr[row.expr])
                            }
                    }
                    && ForAll(in: solutions.expr) { placement in
                        placement.expr.count == 4
                            && ForAll(in: IntRange(1, through: placement.expr.count)) { row in
                                IntRange(1, through: 4).contains(placement.expr[row.expr])
                            }
                    }
                }
            })
        }
    }
}

extension Example {
    package static let nQueensFour = FiniteModelFixture(
        expectedDistinct: 786,
        maximumStateLimit: 50_000,
        spec: NQueensModel.spec,
    )
}
