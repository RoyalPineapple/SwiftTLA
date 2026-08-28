import SwiftTLA
import SwiftTLAMacros

package struct GameOfLifeModel: Sendable {
    package struct Position: FiniteTLAValueDomain {
        package let column: Int
        package let row: Int

        private init(column: Int, row: Int) {
            self.column = column
            self.row = row
        }

        package static let defaultValue = Self(column: 1, row: 1)
        package static let finiteValues = (1...4).flatMap { column in
            (1...4).map { row in Self(column: column, row: row) }
        }

        package init?(formalValue: TLAValue) {
            guard case .tuple(let coordinates) = formalValue,
                  coordinates.count == 2,
                  case .int(let column) = coordinates[0],
                  case .int(let row) = coordinates[1],
                  (1...4).contains(column),
                  (1...4).contains(row)
            else { return nil }
            self.init(column: column, row: row)
        }

        package var tlaValue: TLAValue {
            .tuple([.int(column), .int(row)])
        }
    }
}

private extension Expr where T == GameOfLifeModel.Position {
    var column: Expr<Int> { Expr<Int>(.tupleAccess(raw, 1)) }
    var row: Expr<Int> { Expr<Int>(.tupleAccess(raw, 2)) }
}

extension GameOfLifeModel {
    package static var spec: TLASpec {
        #spec("GameOfLife") { scope in
            Extends(.integers)
            let grid = scope.sharedVar(
                "grid",
                initial: Function<Position, Bool>.mapping { boundPosition in
                    let position = boundPosition.expr
                    return Expr(
                        position.column == 2
                            && position.row >= 2
                            && position.row <= 4
                    )
                }
            )

            Invariant("TypeOK") {
                for position in Position.finiteValues {
                    StateExpr.in(
                        grid[position].stateExpr,
                        SetExpr<Bool>.literal(false, true).stateExpr
                    )
                }
            }

            SwiftTLA.Action("Next") {
                grid.becomes(Function<Position, Bool>.mapping { position in
                    nextCell(in: grid, at: position.expr)
                })
            }
        }
    }

    private static func nextCell(
        in grid: SharedVariable<Function<Position, Bool>>,
        at position: Expr<Position>
    ) -> Expr<Bool> {
        var neighborCount = StateExpr.int(0)
        let neighborOffsets = [
            (-1, -1), (-1, 0), (-1, 1),
            (0, -1), (0, 1),
            (1, -1), (1, 0), (1, 1),
        ]
        for (columnOffset, rowOffset) in neighborOffsets {
            let neighborColumn = position.column + columnOffset
            let neighborRow = position.row + rowOffset
            let isInBounds = neighborColumn >= 1
                && neighborColumn <= 4
                && neighborRow >= 1
                && neighborRow <= 4
            let neighbor = Expr<Position>(.tupleLiteral([
                neighborColumn.stateExpr,
                neighborRow.stateExpr,
            ]))
            neighborCount = neighborCount + If(
                isInBounds,
                then: If(grid[neighbor], then: 1, else: 0),
                else: 0
            )
        }

        let alive = grid[position]
        return Expr(
            alive == true && neighborCount >= 2 && neighborCount <= 3
                || alive == false && neighborCount == 3
        )
    }
}
