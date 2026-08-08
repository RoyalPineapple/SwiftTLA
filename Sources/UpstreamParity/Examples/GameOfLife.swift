import SwiftTLA

/// Conway's Game of Life — N=4 grid, blinker start.
/// Upstream uses function constructor `[p \in Pos |-> ...]` — we use `functionLiteral`.
extension Example {
    public static let gameOfLife = Entry(
        id: "GameOfLife/N4",
        upstreamSpec: "GameOfLife",
        upstreamModule: "specifications/GameOfLife/GameOfLife.tla",
        upstreamCfg: "specifications/GameOfLife/GameOfLife.cfg",
        expectedDistinct: 2,
        spec: gameOfLifeSpec(),
        notes: "N=4 blinker. Uses functionLiteral for Next — upstream pattern, zero except chains.",
    )
}

private func gameOfLifeSpec() -> TLASpec {
    let N = 4
    let grid = Var<TLAFunctionType>("grid")
    let positions = (1...N).flatMap { x in (1...N).map { y in (x, y) } }
    let allTiles: [StateExpr] = positions.map { .tupleLiteral([.int($0.0), .int($0.1)]) }

    // Init: blinker at row 2, columns 2-4
    var initCells: [TLAValue: TLAValue] = [:]
    for (x, y) in positions {
        let alive = (x == 2 && y == 2) || (x == 2 && y == 3) || (x == 2 && y == 4)
        initCells[.tuple([.int(x), .int(y)])] = .bool(alive)
    }
    let initFunc = TLAValue.function(Dictionary(uniqueKeysWithValues: initCells.map { ($0.key, $0.value) }))

    // The cell-update body used inside functionLiteral
    func nextValue(at p: StateExpr) -> StateExpr {
        let x = StateExpr.tupleAccess(p, 0)
        let y = StateExpr.tupleAccess(p, 1)
        let alive = grid.applying(p)
        var score: StateExpr = StateExpr.int(0)
        for dx in -1...1 {
            for dy in -1...1 where !(dx == 0 && dy == 0) {
                let nx = StateExpr.add(x, StateExpr.int(dx)); let ny = StateExpr.add(y, StateExpr.int(dy))
                let inBounds = StateExpr.greaterOrEqual(nx, StateExpr.int(1)) && StateExpr.lessOrEqual(nx, StateExpr.int(N)) && StateExpr.greaterOrEqual(ny, StateExpr.int(1)) && StateExpr.lessOrEqual(ny, StateExpr.int(N))
                let neighbor = StateExpr.tupleLiteral([nx, ny])
                score = StateExpr.add(score, StateExpr.ifThenElse(inBounds,
                    StateExpr.ifThenElse(grid.applying(neighbor), StateExpr.int(1), StateExpr.int(0)), StateExpr.int(0)))
            }
        }
        return (alive && StateExpr.greaterOrEqual(score, StateExpr.int(2)) && StateExpr.lessOrEqual(score, StateExpr.int(3))) || StateExpr.not(alive) && StateExpr.equal(score, StateExpr.int(3))
    }

    return TLASpec("GameOfLife") {
        Extends("Integers")
        Variable(grid, initFunc)

        Invariant("TypeOK") {
            for (x, y) in positions {
                StateExpr.in(grid.applying(StateExpr.tupleLiteral([.int(x), .int(y)])),
                    StateExpr.setLiteral([.bool(false), .bool(true)]))
            }
        }

        // grid' = [p \in Pos |-> nextValue(p)]  — the upstream pattern
        Action("Next") {
            let body = nextValue(at: .variable("p"))
            grid.becomes(StateExpr.functionLiteral(StateExpr.setLiteral(allTiles), .fresh(), body))
        }
    }
}
