// The board advances one generation according to each cell’s live neighbors.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/GameOfLife/GameOfLife.tla

import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/GameOfLife/GameOfLife.tla
@TLAModel
package struct GameOfLifeModel: Sendable {
    package typealias Position = Pair<Int, Int>
    package enum Step: String, CaseIterable { case advanceGeneration = "Next" }

    package static var spec: TLASpec {
        #spec("GameOfLife") { scope in
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N >= 0)

            let positions = IntRange(1, through: N).flatMapping { column in
                IntRange(1, through: N).mapping { row in
                    Pair<Int, Int>.literal(column.expr, row.expr)
                }
            }
            let grids = Functions(from: positions, to: Bool.all)

            let grid: SharedVariable<[Position: Bool]> = scope.sharedVar(initiallyIn: grids)

            Do(Step.advanceGeneration) {
                grid.set(
                    Dictionary<Position, Bool>.mapping(over: positions) { cell in
                        let liveNeighborCount = positions.filter { neighbor in
                            IntRange(cell.expr.first() - 1, through: cell.expr.first() + 1)
                                .contains(neighbor.expr.first())
                                && IntRange(cell.expr.second() - 1, through: cell.expr.second() + 1)
                                    .contains(neighbor.expr.second())
                                && (neighbor.expr.first() != cell.expr.first()
                                    || neighbor.expr.second() != cell.expr.second())
                                && grid[neighbor.expr]
                        }.count
                        return liveNeighborCount == 3 || (grid[cell.expr] && liveNeighborCount == 2)
                    }
                )
            }

            Invariant("TypeOK") { grids.contains(grid) }

            Validation("GameOfLife") {
                Bind(N, to: 4)
            }
        }
    }
}
