import SwiftTLA
import SwiftTLAMacros

/// The upstream direct-TLA Queens model with its published FourQueens scenario.
@TLAModel
package struct QueensModel: Sendable {
    package enum Step: String, CaseIterable { case placeQueen = "PlaceQueen" }

    package static var spec: TLASpec {
        #spec("Queens") { scope in
            Extends(.naturals, .sequences)
            let N = scope.parameter(as: Int.self, in: 1...4)
            Assume(N > 0)
            let todo = scope.sharedVar(initial: Set<[Int]>([Array<Int>([])]))
            let sols = scope.sharedVar(initial: Set<[Int]>([]))
            let Termination = Temporal()

            Do(Step.placeQueen) {
                With(todo) { queens in
                    let nextQueen = queens.count + 1
                    let columns = IntRange(1, through: N).filter { column in
                        !IntRange(1, through: queens.count).contains { row in
                            queens.appending(column).at(row.expr) == queens.appending(column).at(nextQueen)
                                || queens.appending(column).at(row.expr) - queens.appending(column).at(nextQueen)
                                    == row.expr - nextQueen
                                || queens.appending(column).at(nextQueen) - queens.appending(column).at(row.expr)
                                    == row.expr - nextQueen
                        }
                    }
                    let extensions = columns.mapping { column in queens.appending(column) }
                    If(nextQueen == N) {
                        todo.remove(queens)
                        sols.formUnion(extensions)
                    } else: {
                        todo.set(todo.removing(queens).union(extensions))
                    }
                }
            }
            WeakFairnessNext()

            let solutions = Sequences(of: IntRange(1, through: N), lengths: IntRange(N, through: N))
                .filter { placement in
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
            let typeInvariant = Invariant("TypeInvariant") {
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
            typeInvariant
            let invariant = Invariant("Invariant") {
                sols.isSubset(of: solutions)
                !todo.isEmpty || solutions.isSubset(of: sols)
            }
            invariant
            let noSolutions = Invariant("NoSolutions") { sols.isEmpty }
            noSolutions
            Termination(.eventually(todo.isEmpty))
            let FourQueens = Validation { Bind(N, to: 4) }
                .checking(only: [typeInvariant, invariant, noSolutions])
                .checkingDeadlock(false)
                .expect(noSolutions, .violated)
            FourQueens
        }
    }
}
