import SwiftTLA
import SwiftTLAMacros

/// The upstream N-Queens PlusCal algorithm, specialized to the published
/// FourQueens TLC model. A tuple is one partial board: its index is the row
/// and its value is the chosen column.
@TLAModel
public struct NQueensModel: Sendable {
    private enum Step: String, PlusCalLabel {
        case nextQueen = "nxtQ"
    }

    public static var spec: TLASpec {
        #spec("QueensPluscal") {
            Extends("Naturals")
            Algorithm("Queens") {
                let todo = SharedVar(initial: SetExpr<TupleExpr<Int>>.literal(TupleExpr<Int>()))
                let solutions = SharedVar(initial: SetExpr<TupleExpr<Int>>())

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
                                    }.raw
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

                Invariant("TypeInvariant") {
                    ForAll(in: todo.expr) { placement in
                        placement.expr.count < 4
                    }
                    && ForAll(in: solutions.expr) { placement in
                        placement.expr.count == 4
                    }
                }
            }
        }
    }
}

extension Example {
    public static let nQueensFour = Entry(
        id: "N-Queens/QueensPluscal/FourQueens",
        upstreamSpec: "N-Queens",
        upstreamModule: "specifications/N-Queens/QueensPluscal.tla",
        upstreamCfg: "specifications/N-Queens/QueensPluscal.toolbox/FourQueens/MC.cfg",
        expectedDistinct: 786,
        spec: NQueensModel.spec,
        notes: "Published sequential PlusCal N-Queens algorithm, specialized to N=4."
    )
}
