import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/GameOfLife/GameOfLife.tla
@TLAModel
package struct GameOfLifeModel: Sendable {
    package typealias Position = Pair<Int, Int>
    package enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("GameOfLife") { scope in
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N >= 0)

            let positions = IntRange(1, through: N).flatMapping { column in
                IntRange(1, through: N).mapping { row in
                    Pair<Int, Int>.literal(column.expr, row.expr)
                }
            }
            let grids = Functions(from: positions, to: SetExpr<Bool>.literal(false, true))

            let grid: SharedVariable<[Position: Bool]> = scope.sharedVar(initiallyIn: grids)

            Do(Step.next) {
                grid.set(
                    Dictionary<Position, Bool>.mapping(over: positions) { cell in
                        positions.filter { neighbor in
                            IntRange(cell.expr.first() - 1, through: cell.expr.first() + 1)
                                .contains(neighbor.expr.first())
                                && IntRange(cell.expr.second() - 1, through: cell.expr.second() + 1)
                                    .contains(neighbor.expr.second())
                                && (neighbor.expr.first() != cell.expr.first()
                                    || neighbor.expr.second() != cell.expr.second())
                                && grid[neighbor.expr]
                        }.count == 3
                            || (grid[cell.expr] && positions.filter { neighbor in
                                IntRange(cell.expr.first() - 1, through: cell.expr.first() + 1)
                                    .contains(neighbor.expr.first())
                                    && IntRange(cell.expr.second() - 1, through: cell.expr.second() + 1)
                                        .contains(neighbor.expr.second())
                                    && (neighbor.expr.first() != cell.expr.first()
                                        || neighbor.expr.second() != cell.expr.second())
                                    && grid[neighbor.expr]
                            }.count == 2)
                    }
                )
            }

            Invariant("TypeOK") { grids.contains(grid) }

            let GameOfLife = Validation {
                Bind(N, to: 4)
            }
            GameOfLife
        }
    }
}
