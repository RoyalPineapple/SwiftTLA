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
            let NoSolutions = Invariant()
            let Termination = Temporal()
            let Queens = Algorithm(fairness: .weak) { scope in
                let todo = scope.sharedVar(initial: Set<[Int]>([Array<Int>([])]))
                let sols = scope.sharedVar(initial: Set<[Int]>([]))

                While(Step.nextQueen, !todo.expr.isEmpty) {
                    With(todo) { queens in
                        Let(queens.expr.count + 1) { nextQueen in
                            Let(
                                IntRange(1, through: N).filter { column in
                                    !IntRange(1, through: queens.expr.count).contains { row in
                                        let placement = queens.expr.appending(column.expr)
                                        let priorColumn = placement[row]
                                        let newColumn = placement[nextQueen]
                                        let rowDifference = row.expr - nextQueen.expr
                                        return priorColumn == newColumn
                                            || priorColumn - newColumn == rowDifference
                                            || newColumn - priorColumn == rowDifference
                                    }
                                }
                            ) { columns in
                                Let(columns.expr.mapping { column in
                                    queens.expr.appending(column.expr)
                                }) { extensions in
                                    If(nextQueen.expr == N) {
                                        todo.remove(queens)
                                        sols.formUnion(extensions.expr)
                                    } else: {
                                        todo.set(todo.expr.removing(queens).union(extensions.expr))
                                    }
                                }
                            }
                        }
                    }
                }

                let validSolutions = Sequences(
                    of: IntRange(1, through: N), lengths: IntRange(N, through: N)
                ).filter { placement in
                    IntRange(1, through: N - 1).allSatisfy { row in
                        IntRange(row + 1, through: N).allSatisfy { other in
                            let column = placement[row]
                            let otherColumn = placement[other]
                            let rowDifference = row - other
                            return column != otherColumn
                                && column - otherColumn != rowDifference
                                && otherColumn - column != rowDifference
                        }
                    }
                }
                Invariant("Invariant") {
                    sols.expr.isSubset(of: validSolutions)
                        && (!todo.expr.isEmpty || validSolutions.isSubset(of: sols.expr))
                }
                NoSolutions { sols.expr.isEmpty }
                Termination(.eventually(Finished()))

                Invariant("TypeInvariant") {
                    todo.allSatisfy { placement in
                        placement.count < N && IntRange(1, through: placement.count).allSatisfy { row in
                            IntRange(1, through: N).contains(placement[row])
                        }
                    }
                    sols.allSatisfy { placement in
                        placement.count == N && IntRange(1, through: placement.count).allSatisfy { row in
                            IntRange(1, through: N).contains(placement[row])
                        }
                    }
                }
            }
            Queens
            let FourQueens = Validation { Bind(N, to: 4) }.expect(NoSolutions, .violated)
            FourQueens
        }
    }
}
